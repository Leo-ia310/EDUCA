-- Índices para paginación, búsquedas administrativas y lecturas frecuentes del backend Node.

create extension if not exists pg_trgm;

create index if not exists idx_files_institution_created_active
  on files(institution_id, created_at desc)
  where deleted_at is null;

create index if not exists idx_sync_queue_user_status_created
  on sync_queue(institution_id, user_id, status, created_at desc);

create index if not exists idx_change_log_institution_changed
  on change_log(institution_id, changed_at);

create index if not exists idx_developer_audit_events_created
  on developer_audit_events(created_at desc);

create index if not exists idx_developer_api_registry_status_created
  on developer_api_registry(frontend_status, backend_status, created_at desc)
  where deleted_at is null;

create index if not exists idx_developer_tasks_status_created
  on developer_tasks(status, created_at desc)
  where deleted_at is null;

create index if not exists idx_persons_first_name_trgm
  on persons using gin (first_name gin_trgm_ops)
  where deleted_at is null;

create index if not exists idx_persons_last_name_trgm
  on persons using gin (last_name gin_trgm_ops)
  where deleted_at is null;

create index if not exists idx_persons_email_trgm
  on persons using gin (email gin_trgm_ops)
  where deleted_at is null;

create index if not exists idx_users_full_name_trgm
  on users using gin (full_name gin_trgm_ops)
  where deleted_at is null;

create index if not exists idx_users_email_trgm
  on users using gin (email gin_trgm_ops)
  where deleted_at is null;

create index if not exists idx_users_username_trgm
  on users using gin (username gin_trgm_ops)
  where deleted_at is null;

create index if not exists idx_messages_conversation_created
  on messages(conversation_id, created_at desc);

create index if not exists idx_conversation_participants_user_conversation
  on conversation_participants(user_id, conversation_id);

create index if not exists idx_period_grades_report_lookup
  on period_grades(institution_id, student_id, academic_period_id, subject_id);

create index if not exists idx_report_cards_lookup
  on report_cards(institution_id, student_id, academic_period_id);

create index if not exists idx_charges_institution_student_status
  on charges(institution_id, student_id, status);

create index if not exists idx_payments_institution_uuid
  on payments(institution_id, uuid);

create index if not exists idx_devices_user_endpoint
  on devices(user_id, device_uuid);
