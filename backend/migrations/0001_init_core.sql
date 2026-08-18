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
