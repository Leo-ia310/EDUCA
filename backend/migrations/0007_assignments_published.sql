-- =============================================================================
-- Educa360 — 0007 ASSIGNMENTS.PUBLISHED
-- El dominio Flutter (`Assignment.published`, default true) esperaba un
-- estado publicado/borrador propio. `assignments.task_status_id` no sirve
-- para esto: su catálogo (`catalog_task_statuses` = PEND/ENTR/CALI/VENC/REV)
-- describe el ciclo de vida de una ENTREGA, no de la tarea en sí. Se agrega
-- una columna dedicada en vez de forzar un catálogo que no encaja.
-- Idempotente.
-- =============================================================================

alter table assignments
  add column if not exists published boolean not null default true;

-- Constraints únicas para poder hacer upsert idempotente de adjuntos desde
-- el repo Flutter (`assignment_files`/`submission_files` no las tenían).
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'assignment_files_assignment_file_key'
  ) then
    alter table assignment_files
      add constraint assignment_files_assignment_file_key unique (assignment_id, file_id);
  end if;

  if not exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'submission_files_submission_file_key'
  ) then
    alter table submission_files
      add constraint submission_files_submission_file_key unique (submission_id, file_id);
  end if;
end$$;
