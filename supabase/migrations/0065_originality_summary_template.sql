-- Nivra Originality: resumen por actividad y plantilla (texto a excluir) por actividad.
-- Aditiva. La plantilla vive en una tabla privada (sin grants a clientes) para que
-- ningún SELECT sobre assignments la exponga a estudiantes o padres.

alter table public.originality_audit
  add column if not exists assignment_id bigint references public.assignments(id) on delete cascade;
create index if not exists originality_audit_assignment on public.originality_audit(assignment_id);

create table if not exists public.originality_templates (
  assignment_id bigint primary key references public.assignments(id) on delete cascade,
  institution_id bigint not null references public.institutions(id) on delete cascade,
  template text not null check (length(template) <= 20000),
  updated_by bigint references public.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp()
);
create index if not exists originality_templates_institution on public.originality_templates(institution_id);
create index if not exists originality_templates_updated_by on public.originality_templates(updated_by);
alter table public.originality_templates enable row level security;
revoke all on public.originality_templates from public, anon, authenticated;
grant select, insert, update, delete on public.originality_templates to service_role;

-- Acceso común: docente con los tres permisos sobre la clase de la actividad.
create or replace function public.originality_assignment_access(p_assignment bigint, p_permission text)
returns public.assignments language plpgsql stable security definer set search_path=public as $$
declare a public.assignments%rowtype;
begin
  select * into a from public.assignments
    where id = p_assignment and institution_id = public.current_institution_id() and deleted_at is null;
  if a.id is null or not public.is_teacher_actor()
     or not public.class_permission(a.class_id, 'class.view')
     or not public.class_permission(a.class_id, p_permission)
     or not public.class_permission(a.class_id, 'students.view') then
    raise exception 'Actividad no disponible.' using errcode = '42501';
  end if;
  return a;
end $$;

-- Lectura de la plantilla.
create or replace function public.originality_template_get(p_assignment bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare a public.assignments%rowtype; t public.originality_templates%rowtype;
begin
  a := public.originality_assignment_access(p_assignment, 'assignments.review');
  select * into t from public.originality_templates where assignment_id = a.id;
  return jsonb_build_object('template', coalesce(t.template, ''), 'updatedAt', t.updated_at,
    'instructionsLines', (select count(*) from regexp_split_to_table(coalesce(a.instructions, '') || E'\n' || coalesce(a.description, ''), E'\r?\n') l where length(trim(l)) >= 20));
end $$;

-- Guarda la plantilla y reanaliza la actividad con las nuevas exclusiones.
-- Los pares previos se borran porque se calcularon con otras exclusiones.
create or replace function public.originality_template_set(p_assignment bigint, p_template text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare a public.assignments%rowtype; old text; txt text := coalesce(p_template, ''); requeued integer := 0; actor bigint := public.chat_actor();
begin
  a := public.originality_assignment_access(p_assignment, 'assignments.create');
  if length(txt) > 20000 then raise exception 'Plantilla demasiado larga.' using errcode = '22023'; end if;
  txt := regexp_replace(txt, E'\r\n?', E'\n', 'g');
  select template into old from public.originality_templates where assignment_id = a.id;
  if coalesce(old, '') is distinct from txt then
    if txt = '' then delete from public.originality_templates where assignment_id = a.id;
    else
      insert into public.originality_templates(assignment_id, institution_id, template, updated_by, updated_at)
        values (a.id, a.institution_id, txt, actor, clock_timestamp())
        on conflict (assignment_id) do update set template = excluded.template, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
    end if;
    delete from public.originality_pairs where a_id in (select id from public.originality_documents where assignment_id = a.id)
      or b_id in (select id from public.originality_documents where assignment_id = a.id);
    with q as (
      -- El texto escrito en la entrega se purga tras procesarse: se restaura desde la entrega vigente.
      update public.originality_documents d set state = 'queued', processed_at = null, error_code = null,
          source_notes = case when d.file_id is null
            then (select s.student_notes from public.submissions s where s.id = d.submission_id) else d.source_notes end
        where d.assignment_id = a.id and d.active and d.state in ('completed', 'insufficient_text', 'unsupported_format', 'failed')
        returning d.id)
    insert into public.originality_jobs(document_id) select id from q
      on conflict (document_id) do update set finished_at = null, available_at = clock_timestamp(), attempts = 0,
        lock_token = null, lease_until = null, error_code = null;
    get diagnostics requeued = row_count;
    insert into public.originality_audit(institution_id, assignment_id, actor_id, action)
      values (a.institution_id, a.id, actor, 'template');
  end if;
  return jsonb_build_object('template', txt, 'reanalyzing', requeued);
end $$;

-- Resumen por actividad: una fila por entrega, sin fragmentos ni nombres de fuentes.
create or replace function public.originality_summary(p_assignment bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare a public.assignments%rowtype; rows jsonb; eligible integer; actor bigint := public.chat_actor(); pending boolean;
begin
  a := public.originality_assignment_access(p_assignment, 'assignments.review');
  select coalesce(jsonb_agg(r.row order by r.sort), '[]'), count(*) into rows, eligible from (
    select s.id sort, jsonb_build_object(
      'submissionId', s.id, 'studentId', s.student_id,
      'state', case
        when bool_or(d.state = 'failed') then 'failed'
        when bool_or(d.state = 'processing') then 'processing'
        when bool_or(d.state = 'queued') or count(d.id) = 0 then 'queued'
        when bool_or(d.state = 'completed') then 'completed'
        when bool_or(d.state = 'insufficient_text') then 'insufficient_text'
        else 'unsupported_format' end,
      'compared', coalesce(bool_or(d.state = 'completed' and exists (
        select 1 from public.originality_documents c
         where c.active and c.state = 'completed' and c.assignment_id = d.assignment_id and c.institution_id = d.institution_id
           and c.submission_id <> d.submission_id and c.algorithm_version = d.algorithm_version
           and public.originality_eligible(c.submission_id)
           and c.submitted_at = (select live.submitted_at from public.submissions live where live.id = c.submission_id))), false),
      'coverage', max(top.coverage),
      'binaryIdentical', coalesce(bool_or(top.binary_identical), false),
      'textIdentical', coalesce(bool_or(top.text_identical), false),
      'submittedAt', s.submitted_at) row
    from public.submissions s
    left join public.originality_documents d on d.submission_id = s.id and d.active
    left join lateral (
      select case when p.a_id = d.id then p.a_coverage else p.b_coverage end coverage, p.binary_identical, p.text_identical
        from public.originality_pairs p
        join public.originality_documents o on o.id = case when p.a_id = d.id then p.b_id else p.a_id end
        join public.submissions os on os.id = o.submission_id
       where d.state in ('completed', 'insufficient_text', 'unsupported_format') and (p.a_id = d.id or p.b_id = d.id)
         and o.active and o.state in ('completed', 'insufficient_text', 'unsupported_format')
         and o.institution_id = d.institution_id and o.assignment_id = d.assignment_id
         and p.algorithm_version = d.algorithm_version and o.algorithm_version = d.algorithm_version
         and public.originality_eligible(o.submission_id) and o.submitted_at = os.submitted_at
         and (o.file_id is null or public.originality_source_allowed(o.submission_id, o.file_id))
       order by case when p.a_id = d.id then p.a_coverage else p.b_coverage end desc, o.id asc limit 1
    ) top on true
    where s.assignment_id = a.id and s.institution_id = a.institution_id and public.originality_eligible(s.id)
    group by s.id
  ) r;
  select coalesce(a.due_at > clock_timestamp(), true)
    or exists (select 1 from public.originality_documents d where d.assignment_id = a.id and d.active and d.state in ('queued', 'processing', 'failed'))
    or exists (select 1 from public.submissions s where s.assignment_id = a.id and public.originality_eligible(s.id)
        and not exists (select 1 from public.originality_documents r where r.submission_id = s.id and r.active and r.submitted_at = s.submitted_at))
    into pending;
  insert into public.originality_audit(institution_id, assignment_id, actor_id, action) values (a.institution_id, a.id, actor, 'summary');
  return jsonb_build_object('assignmentId', a.id, 'eligible', eligible, 'preliminary', pending, 'items', rows,
    'hasTemplate', exists (select 1 from public.originality_templates where assignment_id = a.id),
    'notice', 'Este resultado es orientativo; una coincidencia textual no demuestra plagio ni identifica al autor original. La valoración corresponde al docente.');
end $$;

do $$ declare f record; begin
  for f in select oid::regprocedure sig, proname from pg_proc where pronamespace = 'public'::regnamespace
           and proname in ('originality_assignment_access', 'originality_template_get', 'originality_template_set', 'originality_summary') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname <> 'originality_assignment_access' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;
notify pgrst, 'reload schema';
