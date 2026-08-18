-- =============================================================================
-- Educa360 — 0006 HARDENING
-- Cierra los gaps detectados en la auditoría de 0001–0005:
--   1) RLS real (hoy `using(true)`) en 5 tablas sin institution_id directo.
--   2) Bucket de Storage `files` + políticas por institución (hoy solo
--      documentado en comentario, nunca ejecutado).
--   3) Triggers `updated_at` (las columnas existen pero nada las actualiza).
--   4) Índices en institution_id/FKs consultados sin índice.
--   5) Fix puntual: `sessions.device_id` sin FK declarada.
--
-- Idempotente: se puede correr varias veces sin error (igual que 0005).
-- Aplicar en el SQL Editor de Supabase (o vía CLI) DESPUÉS de 0001–0005.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) RLS real para tablas sin institution_id directo que quedaron en 0003
--    con `using (true)` ("se afinará en 0004", nunca se hizo). Se aíslan vía
--    join a la tabla padre, que sí lleva institution_id y ya tiene su propia
--    política tenant_isolation (no hay recursión: es un join en un solo
--    sentido, no una auto-referencia como el caso de chat en 0005).
-- -----------------------------------------------------------------------------
alter table grading_scale_ranges enable row level security;
drop policy if exists tenant_isolation on grading_scale_ranges;
create policy tenant_isolation on grading_scale_ranges
  using (scale_id in (select id from grading_scales where institution_id = public.current_institution_id()))
  with check (scale_id in (select id from grading_scales where institution_id = public.current_institution_id()));

alter table assignment_files enable row level security;
drop policy if exists tenant_isolation on assignment_files;
create policy tenant_isolation on assignment_files
  using (assignment_id in (select id from assignments where institution_id = public.current_institution_id()))
  with check (assignment_id in (select id from assignments where institution_id = public.current_institution_id()));

alter table submission_files enable row level security;
drop policy if exists tenant_isolation on submission_files;
create policy tenant_isolation on submission_files
  using (submission_id in (select id from submissions where institution_id = public.current_institution_id()))
  with check (submission_id in (select id from submissions where institution_id = public.current_institution_id()));

alter table report_card_lines enable row level security;
drop policy if exists tenant_isolation on report_card_lines;
create policy tenant_isolation on report_card_lines
  using (report_card_id in (select id from report_cards where institution_id = public.current_institution_id()))
  with check (report_card_id in (select id from report_cards where institution_id = public.current_institution_id()));

alter table announcement_reads enable row level security;
drop policy if exists tenant_isolation on announcement_reads;
create policy tenant_isolation on announcement_reads
  using (announcement_id in (select id from announcements where institution_id = public.current_institution_id()))
  with check (announcement_id in (select id from announcements where institution_id = public.current_institution_id()));

-- -----------------------------------------------------------------------------
-- 2) Storage: bucket `files` (privado) + políticas reales.
--    Convención de path: {institution_id}/{folder}/{uuid}_{filename}
--    (ya usada por SupabaseFileUploadService). El comentario de 0003
--    apuntaba a `auth.current_institution_id()`, que no existe — la función
--    real vive en `public`.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('files', 'files', false)
on conflict (id) do nothing;

drop policy if exists "files_tenant_isolation_select" on storage.objects;
create policy "files_tenant_isolation_select" on storage.objects
  for select using (
    bucket_id = 'files'
    and (storage.foldername(name))[1] = public.current_institution_id()::text
  );

drop policy if exists "files_tenant_isolation_insert" on storage.objects;
create policy "files_tenant_isolation_insert" on storage.objects
  for insert with check (
    bucket_id = 'files'
    and (storage.foldername(name))[1] = public.current_institution_id()::text
  );

drop policy if exists "files_tenant_isolation_update" on storage.objects;
create policy "files_tenant_isolation_update" on storage.objects
  for update using (
    bucket_id = 'files'
    and (storage.foldername(name))[1] = public.current_institution_id()::text
  );

drop policy if exists "files_tenant_isolation_delete" on storage.objects;
create policy "files_tenant_isolation_delete" on storage.objects
  for delete using (
    bucket_id = 'files'
    and (storage.foldername(name))[1] = public.current_institution_id()::text
  );

-- -----------------------------------------------------------------------------
-- 3) Triggers `updated_at` — las columnas existen desde 0001/0002 pero nada
--    las mantenía; quedaban NULL para siempre salvo que la app las setee a mano.
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  tbl text;
  updated_at_tables text[] := array[
    'institutions', 'persons', 'users', 'enrollments', 'attendances',
    'assignments', 'submissions', 'grades', 'institution_settings'
  ];
begin
  foreach tbl in array updated_at_tables loop
    execute format('drop trigger if exists trg_set_updated_at on %I', tbl);
    execute format(
      'create trigger trg_set_updated_at before update on %I for each row execute function public.set_updated_at()',
      tbl
    );
  end loop;
end$$;

-- -----------------------------------------------------------------------------
-- 4) Índices en institution_id/FKs consultados sin índice (RLS filtra casi
--    toda query por institution_id; estas son las tablas de mayor volumen
--    operativo que no tenían ningún índice más allá de la PK).
-- -----------------------------------------------------------------------------
create index if not exists idx_groups_institution on groups(institution_id);
create index if not exists idx_classes_institution on classes(institution_id);
create index if not exists idx_classes_group on classes(group_id);
create index if not exists idx_enrollments_group on enrollments(group_id);
create index if not exists idx_enrollments_student on enrollments(student_id);
create index if not exists idx_grades_institution on grades(institution_id);
create index if not exists idx_grades_student on grades(student_id);
create index if not exists idx_evaluations_class on evaluations(class_id);
create index if not exists idx_evaluations_period on evaluations(academic_period_id);
create index if not exists idx_evaluations_assignment on evaluations(assignment_id);
create index if not exists idx_messages_conversation on messages(conversation_id);
create index if not exists idx_messages_sender on messages(sender_id);
create index if not exists idx_conversation_participants_user on conversation_participants(user_id);
create index if not exists idx_payments_student on payments(student_id);
create index if not exists idx_payments_charge on payments(charge_id);
create index if not exists idx_charges_student on charges(student_id);
create index if not exists idx_charges_institution on charges(institution_id);
create index if not exists idx_assignments_class on assignments(class_id);
create index if not exists idx_submissions_student on submissions(student_id);

-- -----------------------------------------------------------------------------
-- 5) Fix puntual: `sessions.device_id` era `bigint` suelto, sin FK, a
--    diferencia de toda otra relación del esquema.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'sessions_device_id_fkey' and table_name = 'sessions'
  ) then
    alter table sessions
      add constraint sessions_device_id_fkey
      foreign key (device_id) references devices(id) on delete set null;
  end if;
end$$;
