-- =============================================================================
-- Educa360 — 0002 ACADÉMICO EXTRAS
-- Tareas, evaluaciones, calificaciones, boletines, comunicación, chat, pagos.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tareas y entregas.
-- -----------------------------------------------------------------------------
create table assignments (
  id                    bigserial primary key,
  uuid                  uuid not null default uuid_generate_v4() unique,
  institution_id        bigint references institutions(id) on delete cascade,
  class_id              bigint references classes(id) on delete cascade,
  academic_period_id    bigint references academic_periods(id) on delete set null,
  title                 varchar(200) not null,
  description           text,
  instructions          text,
  assigned_at           timestamptz,
  due_at                timestamptz,
  max_score             numeric(6,2),
  is_graded             boolean default true,
  allow_late            boolean default false,
  task_status_id        int references catalog_task_statuses(id),
  created_by            bigint references teachers(id) on delete set null,
  created_at            timestamptz default now(),
  updated_at            timestamptz,
  deleted_at            timestamptz
);

create table assignment_files (
  id              bigserial primary key,
  assignment_id   bigint references assignments(id) on delete cascade,
  file_id         bigint references files(id) on delete cascade,
  created_at      timestamptz default now()
);

create table submissions (
  id                    bigserial primary key,
  uuid                  uuid not null default uuid_generate_v4() unique,
  institution_id        bigint references institutions(id) on delete cascade,
  assignment_id         bigint references assignments(id) on delete cascade,
  student_id            bigint references students(id) on delete cascade,
  submitted_at          timestamptz,
  student_notes         text,
  task_status_id        int references catalog_task_statuses(id),
  is_late               boolean default false,
  created_at            timestamptz default now(),
  updated_at            timestamptz,
  unique (assignment_id, student_id)
);

create table submission_files (
  id              bigserial primary key,
  submission_id   bigint references submissions(id) on delete cascade,
  file_id         bigint references files(id) on delete cascade,
  created_at      timestamptz default now()
);

-- -----------------------------------------------------------------------------
-- Escalas de calificación, evaluaciones, notas, boletines.
-- -----------------------------------------------------------------------------
create table grading_scales (
  id                  bigserial primary key,
  institution_id      bigint references institutions(id) on delete cascade,
  name                varchar(80) not null,
  scale_type          varchar(20),                  -- numeric / qualitative / letters
  min_value           numeric(6,2),
  max_value           numeric(6,2),
  pass_value          numeric(6,2),
  decimals            int default 0,
  active              boolean default true,
  created_at          timestamptz default now()
);

create table grading_scale_ranges (
  id              bigserial primary key,
  scale_id        bigint references grading_scales(id) on delete cascade,
  label           varchar(30),
  range_min       numeric(6,2),
  range_max       numeric(6,2),
  description     varchar(150),
  passed          boolean default true,
  color           varchar(7)
);

create table evaluations (
  id                      bigserial primary key,
  uuid                    uuid not null default uuid_generate_v4() unique,
  institution_id          bigint references institutions(id) on delete cascade,
  class_id                bigint references classes(id) on delete cascade,
  academic_period_id      bigint references academic_periods(id) on delete cascade,
  evaluation_type_id      int references catalog_evaluation_types(id),
  assignment_id           bigint references assignments(id) on delete set null,
  title                   varchar(200),
  description             text,
  max_score               numeric(6,2),
  weight                  numeric(5,2),
  date                    date,
  published               boolean default false,
  created_by              bigint references teachers(id) on delete set null,
  created_at              timestamptz default now()
);

create table grades (
  id                  bigserial primary key,
  uuid                uuid not null default uuid_generate_v4() unique,
  institution_id      bigint references institutions(id) on delete cascade,
  evaluation_id       bigint references evaluations(id) on delete cascade,
  student_id          bigint references students(id) on delete cascade,
  score               numeric(6,2),
  qualitative_label   varchar(30),
  notes               text,
  recorded_by         bigint references users(id) on delete set null,
  created_at          timestamptz default now(),
  updated_at          timestamptz,
  unique (evaluation_id, student_id)
);

create table period_grades (
  id                  bigserial primary key,
  institution_id      bigint references institutions(id) on delete cascade,
  student_id          bigint references students(id) on delete cascade,
  class_id            bigint references classes(id) on delete cascade,
  subject_id          bigint references subjects(id) on delete cascade,
  academic_period_id  bigint references academic_periods(id) on delete cascade,
  final_score         numeric(6,2),
  qualitative_label   varchar(30),
  passed              boolean,
  notes               text,
  calculated_at       timestamptz,
  created_at          timestamptz default now(),
  unique (student_id, class_id, academic_period_id)
);

create table report_cards (
  id                       bigserial primary key,
  institution_id           bigint references institutions(id) on delete cascade,
  student_id               bigint references students(id) on delete cascade,
  enrollment_id            bigint references enrollments(id) on delete cascade,
  academic_year_id         bigint references academic_years(id) on delete cascade,
  academic_period_id       bigint references academic_periods(id) on delete cascade,
  overall_average          numeric(6,2),
  rank                     int,
  general_notes            text,
  pdf_url                  text,
  status                   varchar(20),
  generated_at             timestamptz,
  created_at               timestamptz default now()
);

create table report_card_lines (
  id                  bigserial primary key,
  report_card_id      bigint references report_cards(id) on delete cascade,
  subject_id          bigint references subjects(id) on delete cascade,
  final_score         numeric(6,2),
  qualitative_label   varchar(30),
  passed              boolean,
  notes               text,
  teacher_id          bigint references teachers(id) on delete set null
);

-- -----------------------------------------------------------------------------
-- Notificaciones / Comunicados / Chat.
-- -----------------------------------------------------------------------------
create table email_templates (
  id                     bigserial primary key,
  institution_id         bigint references institutions(id) on delete cascade,
  notification_type_id   int references catalog_notification_types(id),
  name                   varchar(100),
  subject                varchar(200),
  html_body              text,
  variables              jsonb,
  active                 boolean default true,
  created_at             timestamptz default now()
);

create table notifications (
  id                     bigserial primary key,
  institution_id         bigint references institutions(id) on delete cascade,
  user_id                bigint references users(id) on delete cascade,
  notification_type_id   int references catalog_notification_types(id),
  title                  varchar(200),
  message                text,
  data                   jsonb,
  read                   boolean default false,
  read_at                timestamptz,
  created_at             timestamptz default now()
);
create index idx_notifications_user_unread on notifications(user_id, read);

create table notification_deliveries (
  id               bigserial primary key,
  notification_id  bigint references notifications(id) on delete cascade,
  channel_id       int references catalog_notification_channels(id),
  destination      varchar(200),
  status           varchar(20),
  provider         varchar(50),
  external_ref     varchar(150),
  error            text,
  sent_at          timestamptz,
  created_at       timestamptz default now()
);

create table announcements (
  id                bigserial primary key,
  institution_id    bigint references institutions(id) on delete cascade,
  title             varchar(200),
  content           text,
  kind              varchar(50),
  audience          varchar(50),
  group_id          bigint references groups(id) on delete set null,
  published         boolean default false,
  published_at      timestamptz,
  created_by        bigint references users(id) on delete set null,
  created_at        timestamptz default now()
);

create table announcement_reads (
  id              bigserial primary key,
  announcement_id bigint references announcements(id) on delete cascade,
  user_id         bigint references users(id) on delete cascade,
  read_at         timestamptz,
  unique (announcement_id, user_id)
);

create table conversations (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  kind            varchar(20),
  title           varchar(150),
  created_by      bigint references users(id) on delete set null,
  created_at      timestamptz default now()
);

create table conversation_participants (
  id                bigserial primary key,
  conversation_id   bigint references conversations(id) on delete cascade,
  user_id           bigint references users(id) on delete cascade,
  role              varchar(20),
  joined_at         timestamptz default now(),
  unique (conversation_id, user_id)
);

create table messages (
  id                bigserial primary key,
  uuid              uuid not null default uuid_generate_v4() unique,
  conversation_id   bigint references conversations(id) on delete cascade,
  sender_id         bigint references users(id) on delete set null,
  content           text,
  file_id           bigint references files(id) on delete set null,
  edited            boolean default false,
  created_at        timestamptz default now(),
  deleted_at        timestamptz
);

create table message_reads (
  id           bigserial primary key,
  message_id   bigint references messages(id) on delete cascade,
  user_id      bigint references users(id) on delete cascade,
  read_at      timestamptz default now(),
  unique (message_id, user_id)
);

-- -----------------------------------------------------------------------------
-- Pagos escolares (opcional v2).
-- -----------------------------------------------------------------------------
create table payment_concepts (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  name            varchar(100) not null,
  description     text,
  base_amount     numeric(12,2),
  currency_id     int references catalog_currencies(id),
  recurring       boolean default false,
  periodicity     varchar(20),
  active          boolean default true,
  created_at      timestamptz default now()
);

create table charges (
  id                bigserial primary key,
  institution_id    bigint references institutions(id) on delete cascade,
  student_id        bigint references students(id) on delete cascade,
  concept_id        bigint references payment_concepts(id) on delete restrict,
  academic_year_id  bigint references academic_years(id) on delete set null,
  description       varchar(150),
  amount            numeric(12,2),
  discount          numeric(12,2) default 0,
  late_fee          numeric(12,2) default 0,
  total_amount      numeric(12,2),
  due_at            date,
  status            varchar(20),
  created_at        timestamptz default now()
);

create table payments (
  id                bigserial primary key,
  uuid              uuid not null default uuid_generate_v4() unique,
  institution_id    bigint references institutions(id) on delete cascade,
  charge_id         bigint references charges(id) on delete set null,
  student_id        bigint references students(id) on delete cascade,
  parent_id         bigint references parents(id) on delete set null,
  payment_method    varchar(40),
  amount            numeric(12,2),
  currency_id       int references catalog_currencies(id),
  reference         varchar(150),
  receipt_number    varchar(50),
  status            varchar(20),
  paid_at           timestamptz,
  recorded_by       bigint references users(id) on delete set null,
  created_at        timestamptz default now()
);

-- -----------------------------------------------------------------------------
-- Sincronización offline.
-- -----------------------------------------------------------------------------
create table sync_queue (
  id                bigserial primary key,
  institution_id    bigint references institutions(id) on delete cascade,
  user_id           bigint references users(id) on delete cascade,
  device_id         bigint references devices(id) on delete set null,
  table_name        varchar(80),
  record_uuid       uuid,
  operation         varchar(20),
  payload           jsonb,
  status            varchar(20),
  attempts          int default 0,
  client_timestamp  timestamptz,
  server_timestamp  timestamptz,
  error             text,
  created_at        timestamptz default now()
);
create index idx_sync_queue_device_status on sync_queue(device_id, status);

create table change_log (
  id                bigserial primary key,
  institution_id    bigint references institutions(id) on delete cascade,
  table_name        varchar(80),
  record_id         bigint,
  record_uuid       uuid,
  version           int,
  operation         varchar(20),
  updated_at        timestamptz default now()
);
create index idx_change_log_table on change_log(table_name, updated_at);

-- -----------------------------------------------------------------------------
-- Configuración por institución (escala, branding, idioma, etc.)
-- -----------------------------------------------------------------------------
create table institution_settings (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  key             varchar(100) not null,
  value           text,
  data_type       varchar(20),
  description     varchar(200),
  updated_at      timestamptz,
  unique (institution_id, key)
);
