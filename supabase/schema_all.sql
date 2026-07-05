-- =============================================================================
-- Educa360 — 0001 INIT CORE
-- Núcleo SaaS multi-tenant + RBAC + personas + estructura académica.
-- Convenciones: snake_case, soft delete, timestamps con timezone.
-- Aislamiento: cada tabla operativa lleva institution_id; políticas RLS en 0002.
-- =============================================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- Catálogos globales (compartidos por todas las instituciones).
-- -----------------------------------------------------------------------------
create table catalog_countries (
  id          serial primary key,
  iso_code    varchar(3) unique,
  name        varchar(100) not null,
  phone_code  varchar(10),
  active      boolean default true
);

create table catalog_currencies (
  id        serial primary key,
  iso_code  varchar(3) unique,
  name      varchar(50),
  symbol    varchar(5),
  active    boolean default true
);

create table catalog_document_types (
  id     serial primary key,
  name   varchar(50) not null,
  code   varchar(20),
  active boolean default true
);

create table catalog_genders (
  id   serial primary key,
  name varchar(30) not null,
  code varchar(5)
);

create table catalog_relationships (
  id     serial primary key,
  name   varchar(50) not null,
  active boolean default true
);

create table catalog_education_levels (
  id           serial primary key,
  name         varchar(50) not null,
  display_order int,
  active       boolean default true
);

create table catalog_weekdays (
  id            serial primary key,
  name          varchar(20) not null,
  abbreviation  varchar(5),
  display_order int
);

create table catalog_attendance_statuses (
  id                serial primary key,
  name              varchar(30) not null,
  code              varchar(10),
  counts_as_absent  boolean default false,
  color             varchar(7),
  active            boolean default true
);

create table catalog_evaluation_types (
  id     serial primary key,
  name   varchar(50) not null,
  code   varchar(20),
  active boolean default true
);

create table catalog_task_statuses (
  id   serial primary key,
  name varchar(30) not null,
  code varchar(20)
);

create table catalog_enrollment_statuses (
  id   serial primary key,
  name varchar(30) not null,
  code varchar(20)
);

create table catalog_notification_channels (
  id     serial primary key,
  name   varchar(30) not null,
  code   varchar(20),
  active boolean default true
);

create table catalog_notification_types (
  id     serial primary key,
  name   varchar(80) not null,
  code   varchar(30),
  active boolean default true
);

create table catalog_file_types (
  id        serial primary key,
  name      varchar(30) not null,
  extension varchar(10),
  mime_type varchar(100),
  active    boolean default true
);

-- -----------------------------------------------------------------------------
-- Instituciones (tenants).
-- -----------------------------------------------------------------------------
create table institutions (
  id                  bigserial primary key,
  uuid                uuid not null default uuid_generate_v4() unique,
  code                varchar(50) not null unique,
  name                varchar(200) not null,
  commercial_name     varchar(200),
  subdomain           varchar(100) unique,
  tax_id              varchar(50),
  country_id          int references catalog_countries(id),
  address             text,
  phone               varchar(30),
  email               varchar(150),
  website             varchar(150),
  logo_url            text,
  primary_color       varchar(7),
  secondary_color     varchar(7),
  timezone            varchar(50) default 'America/Managua',
  currency_id         int references catalog_currencies(id),
  primary_level_id    int references catalog_education_levels(id),
  active              boolean default true,
  registered_at       timestamptz default now(),
  created_at          timestamptz default now(),
  updated_at          timestamptz,
  deleted_at          timestamptz
);
create index idx_institutions_active on institutions(active) where deleted_at is null;

-- -----------------------------------------------------------------------------
-- Roles y permisos. Los roles pueden ser globales (institution_id NULL) o
-- definidos por institución.
-- -----------------------------------------------------------------------------
create table roles (
  id             serial primary key,
  institution_id bigint references institutions(id) on delete cascade,
  name           varchar(50) not null,
  code           varchar(30) not null,
  description    text,
  is_system      boolean default false,
  active         boolean default true,
  created_at     timestamptz default now(),
  unique (institution_id, code)
);

create table permissions (
  id          serial primary key,
  module      varchar(50) not null,
  name        varchar(100) not null,
  code        varchar(80) not null unique,
  description text
);

create table role_permissions (
  id            bigserial primary key,
  role_id       int references roles(id) on delete cascade,
  permission_id int references permissions(id) on delete cascade,
  unique (role_id, permission_id)
);

-- -----------------------------------------------------------------------------
-- Personas: una persona física (alumno, docente, acudiente, personal).
-- -----------------------------------------------------------------------------
create table persons (
  id                  bigserial primary key,
  uuid                uuid not null default uuid_generate_v4() unique,
  institution_id      bigint not null references institutions(id) on delete cascade,
  document_type_id    int references catalog_document_types(id),
  document_number     varchar(50),
  first_name          varchar(100) not null,
  last_name           varchar(100) not null,
  birth_date          date,
  gender_id           int references catalog_genders(id),
  email               varchar(150),
  phone               varchar(30),
  address             text,
  photo_url           text,
  created_at          timestamptz default now(),
  updated_at          timestamptz,
  deleted_at          timestamptz,
  unique (institution_id, document_number)
);
create index idx_persons_institution on persons(institution_id) where deleted_at is null;

-- -----------------------------------------------------------------------------
-- Usuarios (cuentas de la app). Enlazadas a auth.users de Supabase.
-- -----------------------------------------------------------------------------
create table users (
  id                  bigserial primary key,
  uuid                uuid not null default uuid_generate_v4() unique,
  auth_user_id        uuid unique references auth.users(id) on delete cascade,
  institution_id      bigint references institutions(id) on delete cascade,
  person_id           bigint references persons(id) on delete set null,
  username            varchar(100) unique,
  email               varchar(150) not null,
  phone               varchar(30),
  full_name           varchar(200) not null,
  avatar_url          text,
  email_verified      boolean default false,
  phone_verified      boolean default false,
  two_factor          boolean default false,
  last_sign_in        timestamptz,
  failed_attempts     int default 0,
  locked_until        timestamptz,
  active              boolean default true,
  created_at          timestamptz default now(),
  updated_at          timestamptz,
  deleted_at          timestamptz,
  unique (institution_id, email)
);
create index idx_users_institution on users(institution_id) where deleted_at is null;

create table user_roles (
  id              bigserial primary key,
  user_id         bigint references users(id) on delete cascade,
  role_id         int references roles(id) on delete cascade,
  institution_id  bigint references institutions(id) on delete cascade,
  assigned_at     timestamptz default now(),
  unique (user_id, role_id, institution_id)
);

create table sessions (
  id                  bigserial primary key,
  user_id             bigint references users(id) on delete cascade,
  device_id           bigint,
  refresh_token_hash  text not null,
  ip                  varchar(45),
  user_agent          text,
  expires_at          timestamptz,
  revoked             boolean default false,
  created_at          timestamptz default now()
);

create table devices (
  id                bigserial primary key,
  user_id           bigint references users(id) on delete cascade,
  device_uuid       varchar(150),
  platform          varchar(20),
  model             varchar(100),
  push_token        text,
  app_version       varchar(20),
  last_synced_at    timestamptz,
  active            boolean default true,
  created_at        timestamptz default now()
);

create table login_attempts (
  id           bigserial primary key,
  email        varchar(150),
  user_id      bigint references users(id) on delete set null,
  successful   boolean,
  ip           varchar(45),
  user_agent   text,
  created_at   timestamptz default now()
);

create table audit_log (
  id             bigserial primary key,
  institution_id bigint references institutions(id) on delete cascade,
  user_id        bigint references users(id) on delete set null,
  table_name     varchar(80),
  record_id      varchar(80),
  action         varchar(20),
  data_before    jsonb,
  data_after     jsonb,
  ip             varchar(45),
  created_at     timestamptz default now()
);

-- -----------------------------------------------------------------------------
-- Estudiantes / Docentes / Acudientes / Personal.
-- -----------------------------------------------------------------------------
create table students (
  id                   bigserial primary key,
  person_id            bigint not null references persons(id) on delete cascade,
  institution_id       bigint not null references institutions(id) on delete cascade,
  student_code         varchar(50),
  enrollment_date      date,
  blood_type           varchar(5),
  allergies            text,
  medical_notes        text,
  active               boolean default true,
  created_at           timestamptz default now(),
  unique (institution_id, student_code)
);

create table teachers (
  id                bigserial primary key,
  person_id         bigint not null references persons(id) on delete cascade,
  institution_id    bigint not null references institutions(id) on delete cascade,
  teacher_code      varchar(50),
  specialty         varchar(100),
  academic_title    varchar(100),
  hired_at          date,
  active            boolean default true,
  created_at        timestamptz default now()
);

create table parents (
  id                          bigserial primary key,
  person_id                   bigint not null references persons(id) on delete cascade,
  institution_id              bigint not null references institutions(id) on delete cascade,
  occupation                  varchar(100),
  workplace                   varchar(150),
  work_phone                  varchar(30),
  is_emergency_contact        boolean default false,
  created_at                  timestamptz default now()
);

create table parent_students (
  id                       bigserial primary key,
  student_id               bigint references students(id) on delete cascade,
  parent_id                bigint references parents(id) on delete cascade,
  relationship_id          int references catalog_relationships(id),
  is_main_responsible      boolean default false,
  can_pickup               boolean default true,
  lives_with               boolean default true,
  unique (student_id, parent_id)
);

create table staff (
  id                bigserial primary key,
  person_id         bigint references persons(id) on delete cascade,
  institution_id    bigint references institutions(id) on delete cascade,
  position          varchar(100),
  area              varchar(100),
  hired_at          date,
  active            boolean default true,
  created_at        timestamptz default now()
);

-- -----------------------------------------------------------------------------
-- Estructura académica.
-- -----------------------------------------------------------------------------
create table academic_years (
  id                bigserial primary key,
  institution_id    bigint not null references institutions(id) on delete cascade,
  name              varchar(50) not null,
  year              int not null,
  start_date        date,
  end_date          date,
  active            boolean default true,
  is_current        boolean default false,
  created_at        timestamptz default now()
);

create table academic_periods (
  id                  bigserial primary key,
  institution_id      bigint references institutions(id) on delete cascade,
  academic_year_id    bigint references academic_years(id) on delete cascade,
  name                varchar(50) not null,
  display_order       int,
  start_date          date,
  end_date            date,
  weight              numeric(5,2),
  closed              boolean default false,
  created_at          timestamptz default now()
);

create table grade_levels (
  id                  bigserial primary key,
  institution_id      bigint references institutions(id) on delete cascade,
  education_level_id  int references catalog_education_levels(id),
  name                varchar(50) not null,
  display_order       int,
  active              boolean default true
);

create table sections (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  name            varchar(20) not null,
  active          boolean default true
);

create table classrooms (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  name            varchar(50) not null,
  capacity        int,
  location        varchar(100),
  active          boolean default true
);

create table subjects (
  id                  bigserial primary key,
  institution_id      bigint references institutions(id) on delete cascade,
  name                varchar(100) not null,
  code                varchar(20),
  education_level_id  int references catalog_education_levels(id),
  area                varchar(50),
  active              boolean default true
);

create table groups (
  id                 bigserial primary key,
  institution_id     bigint references institutions(id) on delete cascade,
  academic_year_id   bigint references academic_years(id) on delete cascade,
  grade_level_id     bigint references grade_levels(id) on delete cascade,
  section_id         bigint references sections(id) on delete cascade,
  classroom_id       bigint references classrooms(id) on delete set null,
  guide_teacher_id   bigint references teachers(id) on delete set null,
  name               varchar(80),
  max_capacity       int,
  active             boolean default true,
  created_at         timestamptz default now(),
  unique (academic_year_id, grade_level_id, section_id)
);

create table classes (
  id                 bigserial primary key,
  institution_id     bigint references institutions(id) on delete cascade,
  group_id           bigint references groups(id) on delete cascade,
  subject_id         bigint references subjects(id) on delete cascade,
  teacher_id         bigint references teachers(id) on delete set null,
  academic_year_id   bigint references academic_years(id) on delete cascade,
  active             boolean default true,
  created_at         timestamptz default now(),
  unique (group_id, subject_id)
);

create table schedules (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  class_id        bigint references classes(id) on delete cascade,
  weekday_id      int references catalog_weekdays(id),
  start_time      time,
  end_time        time,
  classroom_id    bigint references classrooms(id) on delete set null,
  created_at      timestamptz default now()
);

create table enrollments (
  id                       bigserial primary key,
  institution_id           bigint references institutions(id) on delete cascade,
  student_id               bigint references students(id) on delete cascade,
  group_id                 bigint references groups(id) on delete cascade,
  academic_year_id         bigint references academic_years(id) on delete cascade,
  enrollment_status_id     int references catalog_enrollment_statuses(id),
  enrolled_at              date,
  enrollment_number        varchar(50),
  notes                    text,
  created_at               timestamptz default now(),
  updated_at               timestamptz,
  unique (student_id, academic_year_id)
);

-- -----------------------------------------------------------------------------
-- Calendario / Feriados.
-- -----------------------------------------------------------------------------
create table holidays (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  name            varchar(100),
  date            date,
  recurring       boolean default false,
  created_at      timestamptz default now()
);

create table calendar_events (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  title           varchar(150),
  description     text,
  type            varchar(50),
  start_at        timestamptz,
  end_at          timestamptz,
  audience        varchar(50),
  created_by      bigint references users(id) on delete set null,
  created_at      timestamptz default now()
);

-- -----------------------------------------------------------------------------
-- Asistencia (con UUID para sincronización offline).
-- -----------------------------------------------------------------------------
create table class_sessions (
  id                bigserial primary key,
  institution_id    bigint references institutions(id) on delete cascade,
  class_id          bigint references classes(id) on delete cascade,
  group_id          bigint references groups(id) on delete cascade,
  date              date not null,
  start_time        time,
  topic             varchar(200),
  recorded_by       bigint references teachers(id) on delete set null,
  synced            boolean default true,
  created_at        timestamptz default now()
);
create index idx_class_sessions_class_date on class_sessions(class_id, date);
create index idx_class_sessions_group_date on class_sessions(group_id, date);

create table attendances (
  id                          bigserial primary key,
  uuid                        uuid not null default uuid_generate_v4() unique,
  institution_id              bigint references institutions(id) on delete cascade,
  class_session_id            bigint references class_sessions(id) on delete cascade,
  student_id                  bigint references students(id) on delete cascade,
  attendance_status_id        int references catalog_attendance_statuses(id),
  recorded_at                 timestamptz,
  notes                       text,
  recorded_by                 bigint references users(id) on delete set null,
  source                      varchar(20),
  created_at                  timestamptz default now(),
  updated_at                  timestamptz,
  unique (class_session_id, student_id)
);
create index idx_attendances_student on attendances(student_id);

create table attendance_justifications (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  attendance_id   bigint references attendances(id) on delete cascade,
  student_id      bigint references students(id) on delete cascade,
  reason          text,
  requested_on    date,
  requested_by    bigint references users(id) on delete set null,
  approved        boolean,
  approved_by     bigint references users(id) on delete set null,
  file_url        text,
  created_at      timestamptz default now()
);

-- -----------------------------------------------------------------------------
-- Almacenamiento central de archivos.
-- -----------------------------------------------------------------------------
create table files (
  id              bigserial primary key,
  uuid            uuid not null default uuid_generate_v4() unique,
  institution_id  bigint references institutions(id) on delete cascade,
  file_type_id    int references catalog_file_types(id),
  original_name   varchar(255),
  storage_path    text,
  url             text,
  size_bytes      bigint,
  mime_type       varchar(100),
  uploaded_by     bigint references users(id) on delete set null,
  created_at      timestamptz default now(),
  deleted_at      timestamptz
);
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
-- =============================================================================
-- Educa360 — 0003 ROW LEVEL SECURITY (multi-tenant)
-- Política base: cada tabla operativa solo es visible/escribible si
-- institution_id coincide con el claim `institution_id` del JWT del usuario.
--
-- Para que esto funcione, al confirmar el alta o crear el usuario en Supabase,
-- almacenar en `auth.users.raw_app_meta_data` los campos:
--   { "institution_id": 1, "roles": ["teacher"] }
-- =============================================================================

-- Helper: lee el institution_id del JWT.
create or replace function auth.current_institution_id() returns bigint
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'institution_id', '')::bigint,
    (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'institution_id')::bigint
  );
$$;

-- Helper: roles del usuario.
create or replace function auth.current_roles() returns text[]
language sql stable as $$
  select coalesce(
    array(select jsonb_array_elements_text(
      current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' -> 'roles'
    )),
    array[]::text[]
  );
$$;

create or replace function auth.has_role(role_code text) returns boolean
language sql stable as $$
  select role_code = any(auth.current_roles());
$$;

-- -----------------------------------------------------------------------------
-- Activar RLS y aplicar política tenant a tablas operativas.
-- -----------------------------------------------------------------------------
do $$
declare
  tbl text;
  tenant_tables text[] := array[
    'institutions','roles','users','user_roles','sessions','devices','login_attempts','audit_log',
    'persons','students','teachers','parents','parent_students','staff',
    'academic_years','academic_periods','grade_levels','sections','classrooms','subjects','groups',
    'classes','schedules','enrollments',
    'holidays','calendar_events',
    'class_sessions','attendances','attendance_justifications',
    'files',
    'assignments','assignment_files','submissions','submission_files',
    'grading_scales','grading_scale_ranges','evaluations','grades','period_grades',
    'report_cards','report_card_lines',
    'email_templates','notifications','notification_deliveries',
    'announcements','announcement_reads',
    'conversations','conversation_participants','messages','message_reads',
    'payment_concepts','charges','payments',
    'sync_queue','change_log','institution_settings'
  ];
begin
  foreach tbl in array tenant_tables loop
    execute format('alter table %I enable row level security', tbl);
    execute format('drop policy if exists tenant_isolation on %I', tbl);
    -- institutions usa su propio id; el resto usa institution_id.
    if tbl = 'institutions' then
      execute format($f$
        create policy tenant_isolation on %I
          using (id = auth.current_institution_id())
          with check (id = auth.current_institution_id())
      $f$, tbl);
    elsif tbl in ('grading_scale_ranges','assignment_files','submission_files','report_card_lines',
                   'conversation_participants','messages','message_reads','announcement_reads') then
      -- Estas no llevan institution_id directo; se restringen vía join al padre
      -- mediante security definer functions o vistas. Aquí dejamos USING true y
      -- confiamos en políticas más finas (se afinará en 0004).
      execute format('create policy tenant_isolation on %I using (true) with check (true)', tbl);
    else
      execute format($f$
        create policy tenant_isolation on %I
          using (institution_id = auth.current_institution_id())
          with check (institution_id = auth.current_institution_id())
      $f$, tbl);
    end if;
  end loop;
end$$;

-- -----------------------------------------------------------------------------
-- Catálogos globales: lectura libre, sin escritura.
-- -----------------------------------------------------------------------------
do $$
declare
  tbl text;
  catalog_tables text[] := array[
    'catalog_countries','catalog_currencies','catalog_document_types','catalog_genders',
    'catalog_relationships','catalog_education_levels','catalog_weekdays',
    'catalog_attendance_statuses','catalog_evaluation_types','catalog_task_statuses',
    'catalog_enrollment_statuses','catalog_notification_channels','catalog_notification_types',
    'catalog_file_types','permissions','role_permissions'
  ];
begin
  foreach tbl in array catalog_tables loop
    execute format('alter table %I enable row level security', tbl);
    execute format('drop policy if exists public_read on %I', tbl);
    execute format('create policy public_read on %I for select using (true)', tbl);
  end loop;
end$$;

-- -----------------------------------------------------------------------------
-- Política específica para mensajería: el usuario solo ve mensajes de
-- conversaciones donde participa.
-- -----------------------------------------------------------------------------
drop policy if exists tenant_isolation on messages;
create policy participants_only on messages
  using (
    conversation_id in (
      select conversation_id from conversation_participants cp
      join users u on u.id = cp.user_id
      where u.auth_user_id = auth.uid()
    )
  );

drop policy if exists tenant_isolation on conversation_participants;
create policy own_participation on conversation_participants
  using (
    user_id in (select id from users where auth_user_id = auth.uid())
    or conversation_id in (
      select conversation_id from conversation_participants cp2
      join users u on u.id = cp2.user_id
      where u.auth_user_id = auth.uid()
    )
  );

-- -----------------------------------------------------------------------------
-- Storage: el bucket "files" usa la convención de carpeta
--   {institution_id}/{folder}/{filename}
-- y se valida con un policy que extrae el primer segmento del path.
-- -----------------------------------------------------------------------------
-- (Se aplica desde la consola de Supabase Storage o vía:)
--   create policy "files_tenant_isolation"
--     on storage.objects for select using (
--       bucket_id = 'files'
--       and (storage.foldername(name))[1] = auth.current_institution_id()::text
--     );
-- =============================================================================
-- Educa360 — 0004 SEED CATÁLOGOS + INSTITUCIÓN DEMO
-- =============================================================================

insert into catalog_countries (iso_code, name, phone_code) values
  ('NIC', 'Nicaragua', '505'),
  ('CRI', 'Costa Rica', '506'),
  ('HND', 'Honduras', '504'),
  ('GTM', 'Guatemala', '502'),
  ('SLV', 'El Salvador', '503'),
  ('PAN', 'Panamá', '507'),
  ('MEX', 'México', '52'),
  ('USA', 'Estados Unidos', '1')
on conflict do nothing;

insert into catalog_currencies (iso_code, name, symbol) values
  ('NIO', 'Córdoba',  'C$'),
  ('USD', 'Dólar',    '$'),
  ('EUR', 'Euro',     '€'),
  ('CRC', 'Colón',    '₡')
on conflict do nothing;

insert into catalog_document_types (name, code) values
  ('Cédula', 'CED'),
  ('Pasaporte', 'PAS'),
  ('Partida de nacimiento', 'PN')
on conflict do nothing;

insert into catalog_genders (name, code) values
  ('Masculino', 'M'),
  ('Femenino', 'F'),
  ('No especificado', 'NE')
on conflict do nothing;

insert into catalog_relationships (name) values
  ('Padre'), ('Madre'), ('Tutor'), ('Abuelo/a'), ('Tío/a')
on conflict do nothing;

insert into catalog_education_levels (name, display_order) values
  ('Preescolar', 1), ('Primaria', 2), ('Secundaria', 3), ('Bachillerato', 4),
  ('Universidad', 5)
on conflict do nothing;

insert into catalog_weekdays (name, abbreviation, display_order) values
  ('Lunes', 'Lun', 1), ('Martes', 'Mar', 2), ('Miércoles', 'Mié', 3),
  ('Jueves', 'Jue', 4), ('Viernes', 'Vie', 5), ('Sábado', 'Sáb', 6),
  ('Domingo', 'Dom', 7)
on conflict do nothing;

insert into catalog_attendance_statuses (name, code, counts_as_absent, color) values
  ('Presente', 'PRE', false, '#22C55E'),
  ('Ausente', 'AUS', true, '#EF4444'),
  ('Tarde', 'TAR', false, '#F59E0B'),
  ('Justificado', 'JUS', false, '#3B82F6'),
  ('Permiso', 'PER', false, '#8B5CF6')
on conflict do nothing;

insert into catalog_evaluation_types (name, code) values
  ('Examen', 'EXM'), ('Tarea', 'TAR'), ('Proyecto', 'PRO'),
  ('Quiz', 'QZ'), ('Exposición', 'EXP'), ('Participación', 'PART')
on conflict do nothing;

insert into catalog_task_statuses (name, code) values
  ('Pendiente', 'PEND'), ('Entregada', 'ENTR'),
  ('Calificada', 'CALI'), ('Vencida', 'VENC'), ('Revisada', 'REV')
on conflict do nothing;

insert into catalog_enrollment_statuses (name, code) values
  ('Activa', 'ACT'), ('Retirada', 'RET'),
  ('Trasladada', 'TRA'), ('Egresada', 'EGR')
on conflict do nothing;

insert into catalog_notification_channels (name, code) values
  ('Email', 'EMAIL'), ('Push', 'PUSH'), ('SMS', 'SMS'), ('In-App', 'INAPP')
on conflict do nothing;

insert into catalog_notification_types (name, code) values
  ('Asistencia', 'ATT'),
  ('Calificación', 'GRADE'),
  ('Tarea', 'TASK'),
  ('Comunicado', 'ANN'),
  ('Pago', 'PAY'),
  ('Mensaje', 'MSG')
on conflict do nothing;

insert into catalog_file_types (name, extension, mime_type) values
  ('PDF', 'pdf', 'application/pdf'),
  ('Imagen', 'jpg', 'image/jpeg'),
  ('Documento', 'docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  ('Video', 'mp4', 'video/mp4')
on conflict do nothing;

-- Permisos base
insert into permissions (module, name, code) values
  ('attendance', 'Crear asistencia', 'attendance.create'),
  ('attendance', 'Ver asistencia',   'attendance.read'),
  ('assignments', 'Crear tarea',     'assignments.create'),
  ('assignments', 'Calificar tarea', 'assignments.grade'),
  ('grades', 'Ver calificaciones',   'grades.read'),
  ('grades', 'Registrar nota',       'grades.write'),
  ('reports', 'Ver reportes',        'reports.read'),
  ('users', 'Gestionar usuarios',    'users.manage'),
  ('announcements', 'Publicar anuncio', 'announcements.publish'),
  ('messages', 'Enviar mensajes', 'messages.send')
on conflict do nothing;

-- Roles globales del sistema
insert into roles (institution_id, name, code, is_system) values
  (null, 'Super Administrador', 'super_admin', true),
  (null, 'Estudiante',         'student',     true),
  (null, 'Maestro',            'teacher',     true),
  (null, 'Padre/Tutor',        'parent',      true),
  (null, 'Administrador',      'admin',       true),
  (null, 'Coordinador',        'coordinator', true),
  (null, 'Director',           'director',    true)
on conflict do nothing;

-- Institución demo
insert into institutions (code, name, primary_color, secondary_color, timezone, active)
values ('EDU360', 'Colegio Demo Educa360', '#9BE000', '#1E2218', 'America/Managua', true)
on conflict (code) do nothing;
