-- =============================================================================
-- 0008_business_rules.sql — Reglas de negocio y restricciones en el BACKEND
--
-- Objetivo: que la lógica que hoy vive en el frontend Dart (clamp de notas,
-- cálculo de is_late, validaciones de montos, promedio ponderado, y el flujo
-- de "calificar") se aplique en Postgres, de modo que el cliente NO pueda
-- saltarse las reglas. Idempotente: se puede correr varias veces.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) CHECK constraints (validaciones que antes solo hacía `isValid` en el UI).
--    Se agregan NOT VALID para no fallar con datos legados; luego se validan.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'assignments_max_score_pos') then
    alter table assignments
      add constraint assignments_max_score_pos
      check (max_score is null or max_score > 0) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'evaluations_max_score_pos') then
    alter table evaluations
      add constraint evaluations_max_score_pos
      check (max_score is null or max_score > 0) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'evaluations_weight_nonneg') then
    alter table evaluations
      add constraint evaluations_weight_nonneg
      check (weight is null or weight >= 0) not valid;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'grades_score_nonneg') then
    alter table grades
      add constraint grades_score_nonneg
      check (score is null or score >= 0) not valid;
  end if;
end $$;

-- Validar contra datos existentes (si alguna fila viola, el usuario lo verá aquí).
do $$
begin
  alter table assignments validate constraint assignments_max_score_pos;
  alter table evaluations validate constraint evaluations_max_score_pos;
  alter table evaluations validate constraint evaluations_weight_nonneg;
  alter table grades      validate constraint grades_score_nonneg;
exception when others then
  raise notice 'validate constraints: % (revisa filas legadas)', sqlerrm;
end $$;

-- -----------------------------------------------------------------------------
-- 2) Nota dentro de [0, evaluation.max_score]. Un CHECK no puede referenciar
--    otra tabla, así que se aplica por trigger. Se CLAMPEA (igual que el UI hoy)
--    en lugar de rechazar, para no romper flujos, pero ya del lado servidor.
-- -----------------------------------------------------------------------------
create or replace function public.enforce_grade_within_max()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max numeric(6,2);
begin
  if new.score is null then
    return new;
  end if;
  select max_score into v_max from evaluations where id = new.evaluation_id;
  if v_max is not null then
    new.score := least(greatest(new.score, 0), v_max);
  elsif new.score < 0 then
    new.score := 0;
  end if;
  return new;
end $$;

drop trigger if exists trg_grade_within_max on grades;
create trigger trg_grade_within_max
  before insert or update of score on grades
  for each row execute function public.enforce_grade_within_max();

-- -----------------------------------------------------------------------------
-- 3) is_late calculado en el servidor (el cliente ya no decide la puntualidad).
--    Compara submitted_at contra assignments.due_at.
-- -----------------------------------------------------------------------------
create or replace function public.set_submission_is_late()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_due timestamptz;
begin
  select due_at into v_due from assignments where id = new.assignment_id;
  new.is_late := (new.submitted_at is not null
                  and v_due is not null
                  and new.submitted_at > v_due);
  return new;
end $$;

drop trigger if exists trg_submission_is_late on submissions;
create trigger trg_submission_is_late
  before insert or update of submitted_at, assignment_id on submissions
  for each row execute function public.set_submission_is_late();

-- -----------------------------------------------------------------------------
-- 4) RPC `grade_submission`: encapsula el flujo de calificar (buscar/crear la
--    evaluación de la tarea, registrar la nota, marcar la entrega como CALI).
--    El frontend deja de escribir en varias tablas: solo llama a este RPC.
-- -----------------------------------------------------------------------------
create or replace function public.grade_submission(
  p_submission_id bigint,
  p_score         numeric,
  p_feedback      text default null
)
returns bigint            -- id de la fila `grades`
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution   bigint;
  v_assignment    bigint;
  v_student       bigint;
  v_class         bigint;
  v_period        bigint;
  v_max           numeric(6,2);
  v_title         text;
  v_eval          bigint;
  v_grade         bigint;
  v_cali          int;
begin
  select s.institution_id, s.assignment_id, s.student_id
    into v_institution, v_assignment, v_student
    from submissions s where s.id = p_submission_id;
  if v_assignment is null then
    raise exception 'Entrega % no encontrada', p_submission_id;
  end if;

  select a.class_id, a.academic_period_id, a.max_score, a.title
    into v_class, v_period, v_max, v_title
    from assignments a where a.id = v_assignment;

  -- Evaluación asociada a la tarea (una por tarea).
  select e.id into v_eval from evaluations e where e.assignment_id = v_assignment limit 1;
  if v_eval is null then
    insert into evaluations (institution_id, class_id, academic_period_id,
                             assignment_id, title, max_score, published)
    values (v_institution, v_class, v_period, v_assignment, v_title, v_max, true)
    returning id into v_eval;
  end if;

  -- Registrar/actualizar la nota (el trigger de arriba clampa a [0, max]).
  insert into grades (institution_id, evaluation_id, student_id, score, notes)
  values (v_institution, v_eval, v_student, p_score, p_feedback)
  on conflict (evaluation_id, student_id)
  do update set score = excluded.score, notes = excluded.notes, updated_at = now()
  returning id into v_grade;

  -- Marcar la entrega como calificada (CALI) si el catálogo lo define.
  select id into v_cali from catalog_task_statuses where code = 'CALI' limit 1;
  if v_cali is not null then
    update submissions set task_status_id = v_cali, updated_at = now()
     where id = p_submission_id;
  end if;

  return v_grade;
end $$;

-- -----------------------------------------------------------------------------
-- 5) Promedio ponderado por estudiante/clase/periodo, del lado servidor
--    (reemplaza a GradesCalculator del frontend):
--       avg = Σ(score/max · weight) / Σ(weight)
-- -----------------------------------------------------------------------------
create or replace view public.student_weighted_averages as
select
  g.institution_id,
  g.student_id,
  e.class_id,
  e.academic_period_id,
  round(
    sum( (g.score / nullif(e.max_score, 0)) * coalesce(e.weight, 1) )
    / nullif(sum(coalesce(e.weight, 1)), 0) * 100
  , 2) as weighted_pct
from grades g
join evaluations e on e.id = g.evaluation_id
where g.score is not null and e.max_score is not null
group by g.institution_id, g.student_id, e.class_id, e.academic_period_id;

-- Permisos: el RPC y la vista respetan multi-tenant por las tablas base (RLS).
grant execute on function public.grade_submission(bigint, numeric, text) to authenticated;
grant select on public.student_weighted_averages to authenticated;
