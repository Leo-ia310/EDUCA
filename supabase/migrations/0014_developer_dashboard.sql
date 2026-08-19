-- =============================================================================
-- Educa360 - 0014 DEVELOPER DASHBOARD
-- Tablas de soporte para un panel tecnico/operativo futuro.
--
-- No conecta interfaz Flutter. Deja lista la base para administrar modulos,
-- APIs pendientes, feature flags, health checks, tareas tecnicas y auditoria
-- propia del panel.
-- =============================================================================

create or replace function public.can_use_developer_dashboard()
returns boolean
language sql
stable
as $$
  select public.has_role('super_admin')
      or public.has_role('admin')
      or public.has_role('coordinator')
      or public.has_role('director');
$$;

create table if not exists developer_dashboard_modules (
  id              bigserial primary key,
  uuid            uuid not null default uuid_generate_v4() unique,
  institution_id  bigint references institutions(id) on delete cascade,
  module_key      varchar(80) not null,
  title           varchar(120) not null,
  description     text,
  category        varchar(50) default 'operations',
  icon            varchar(50),
  frontend_route  varchar(150),
  required_roles  text[] not null default array['admin','super_admin']::text[],
  enabled         boolean not null default true,
  display_order   int not null default 0,
  metadata        jsonb not null default '{}'::jsonb,
  created_by      bigint references users(id) on delete set null,
  updated_by      bigint references users(id) on delete set null,
  created_at      timestamptz default now(),
  updated_at      timestamptz,
  deleted_at      timestamptz
);

create unique index if not exists developer_dashboard_modules_key_uidx
  on developer_dashboard_modules (coalesce(institution_id, 0::bigint), module_key)
  where deleted_at is null;

create table if not exists developer_api_registry (
  id                  bigserial primary key,
  uuid                uuid not null default uuid_generate_v4() unique,
  institution_id      bigint references institutions(id) on delete cascade,
  module_id           bigint references developer_dashboard_modules(id) on delete set null,
  module_key          varchar(80) not null,
  method              varchar(10) not null,
  path                varchar(200) not null,
  action              varchar(120),
  summary             varchar(180) not null,
  description         text,
  auth_required       boolean not null default true,
  required_roles      text[] not null default array['admin','super_admin']::text[],
  backend_status      varchar(30) not null default 'planned',
  frontend_status     varchar(30) not null default 'pending',
  request_schema      jsonb not null default '{}'::jsonb,
  response_schema     jsonb not null default '{}'::jsonb,
  source_file         varchar(250),
  owner               varchar(120),
  priority            varchar(20) not null default 'medium',
  notes               text,
  active              boolean not null default true,
  metadata            jsonb not null default '{}'::jsonb,
  created_by          bigint references users(id) on delete set null,
  updated_by          bigint references users(id) on delete set null,
  created_at          timestamptz default now(),
  updated_at          timestamptz,
  deleted_at          timestamptz,
  constraint developer_api_registry_method_check check (method in ('GET','POST','PUT','PATCH','DELETE')),
  constraint developer_api_registry_backend_status_check check (backend_status in ('planned','implemented','blocked','deprecated')),
  constraint developer_api_registry_frontend_status_check check (frontend_status in ('pending','connected','blocked','not_needed')),
  constraint developer_api_registry_priority_check check (priority in ('low','medium','high','critical'))
);

create unique index if not exists developer_api_registry_path_uidx
  on developer_api_registry (coalesce(institution_id, 0::bigint), method, path)
  where deleted_at is null;

create unique index if not exists developer_api_registry_action_uidx
  on developer_api_registry (coalesce(institution_id, 0::bigint), action)
  where action is not null and deleted_at is null;

create table if not exists developer_tasks (
  id                  bigserial primary key,
  uuid                uuid not null default uuid_generate_v4() unique,
  institution_id      bigint references institutions(id) on delete cascade,
  api_registry_id     bigint references developer_api_registry(id) on delete set null,
  module_key          varchar(80),
  title               varchar(180) not null,
  description         text,
  status              varchar(30) not null default 'pending',
  priority            varchar(20) not null default 'medium',
  owner               varchar(120),
  frontend_required   boolean not null default true,
  backend_ready       boolean not null default false,
  due_at              timestamptz,
  completed_at        timestamptz,
  notes               text,
  metadata            jsonb not null default '{}'::jsonb,
  created_by          bigint references users(id) on delete set null,
  updated_by          bigint references users(id) on delete set null,
  created_at          timestamptz default now(),
  updated_at          timestamptz,
  deleted_at          timestamptz,
  constraint developer_tasks_status_check check (status in ('pending','ready','in_progress','blocked','done','cancelled')),
  constraint developer_tasks_priority_check check (priority in ('low','medium','high','critical'))
);

create index if not exists developer_tasks_status_idx
  on developer_tasks (status, priority, module_key)
  where deleted_at is null;

create unique index if not exists developer_tasks_title_uidx
  on developer_tasks (coalesce(institution_id, 0::bigint), coalesce(module_key, ''), title)
  where deleted_at is null;

create table if not exists developer_feature_flags (
  id              bigserial primary key,
  uuid            uuid not null default uuid_generate_v4() unique,
  institution_id  bigint references institutions(id) on delete cascade,
  flag_key        varchar(100) not null,
  title           varchar(150) not null,
  description     text,
  enabled         boolean not null default false,
  rollout_percent int not null default 0,
  config          jsonb not null default '{}'::jsonb,
  metadata        jsonb not null default '{}'::jsonb,
  created_by      bigint references users(id) on delete set null,
  updated_by      bigint references users(id) on delete set null,
  created_at      timestamptz default now(),
  updated_at      timestamptz,
  deleted_at      timestamptz,
  constraint developer_feature_flags_rollout_check check (rollout_percent between 0 and 100)
);

create unique index if not exists developer_feature_flags_key_uidx
  on developer_feature_flags (coalesce(institution_id, 0::bigint), flag_key)
  where deleted_at is null;

create table if not exists developer_system_checks (
  id              bigserial primary key,
  uuid            uuid not null default uuid_generate_v4() unique,
  institution_id  bigint references institutions(id) on delete cascade,
  check_key       varchar(100) not null,
  title           varchar(150) not null,
  description     text,
  check_type      varchar(30) not null default 'manual',
  target          text,
  severity        varchar(20) not null default 'medium',
  status          varchar(30) not null default 'unknown',
  enabled         boolean not null default true,
  last_result     jsonb not null default '{}'::jsonb,
  last_checked_at timestamptz,
  metadata        jsonb not null default '{}'::jsonb,
  created_by      bigint references users(id) on delete set null,
  updated_by      bigint references users(id) on delete set null,
  created_at      timestamptz default now(),
  updated_at      timestamptz,
  deleted_at      timestamptz,
  constraint developer_system_checks_type_check check (check_type in ('manual','sql','http','script')),
  constraint developer_system_checks_severity_check check (severity in ('low','medium','high','critical')),
  constraint developer_system_checks_status_check check (status in ('unknown','passing','warning','failing','disabled'))
);

create unique index if not exists developer_system_checks_key_uidx
  on developer_system_checks (coalesce(institution_id, 0::bigint), check_key)
  where deleted_at is null;

create table if not exists developer_audit_events (
  id              bigserial primary key,
  institution_id  bigint references institutions(id) on delete cascade,
  actor_user_id   bigint references users(id) on delete set null,
  entity_table    varchar(80) not null,
  entity_id       varchar(80),
  action          varchar(40) not null,
  data_before     jsonb,
  data_after      jsonb,
  ip              varchar(45),
  created_at      timestamptz default now()
);

create index if not exists developer_audit_events_entity_idx
  on developer_audit_events (entity_table, entity_id, created_at desc);

create index if not exists developer_audit_events_actor_idx
  on developer_audit_events (actor_user_id, created_at desc);

do $$
declare
  tbl text;
  dashboard_tables text[] := array[
    'developer_dashboard_modules',
    'developer_api_registry',
    'developer_tasks',
    'developer_feature_flags',
    'developer_system_checks',
    'developer_audit_events'
  ];
begin
  foreach tbl in array dashboard_tables loop
    execute format('alter table %I enable row level security', tbl);
    execute format('drop policy if exists developer_dashboard_access on %I', tbl);
    execute format($p$
      create policy developer_dashboard_access on %I
        using (
          public.can_use_developer_dashboard()
          and (
            institution_id is null
            or institution_id = public.current_institution_id()
            or public.has_role('super_admin')
          )
        )
        with check (
          public.can_use_developer_dashboard()
          and (
            institution_id is null
            or institution_id = public.current_institution_id()
            or public.has_role('super_admin')
          )
        )
    $p$, tbl);
  end loop;
end $$;

grant execute on function public.can_use_developer_dashboard() to authenticated;

grant select, insert, update on
  developer_dashboard_modules,
  developer_api_registry,
  developer_tasks,
  developer_feature_flags,
  developer_system_checks,
  developer_audit_events
to authenticated;

grant usage, select on all sequences in schema public to authenticated;

do $$
declare
  tbl text;
begin
  foreach tbl in array array[
    'developer_dashboard_modules',
    'developer_api_registry',
    'developer_tasks',
    'developer_feature_flags',
    'developer_system_checks'
  ] loop
    execute format('drop trigger if exists trg_set_updated_at on %I', tbl);
    execute format(
      'create trigger trg_set_updated_at before update on %I for each row execute function public.set_updated_at()',
      tbl
    );
  end loop;
end $$;

insert into permissions (module, name, code, description) values
  ('developer', 'Ver dashboard tecnico', 'developer.read', 'Permite consultar el dashboard tecnico.'),
  ('developer', 'Gestionar dashboard tecnico', 'developer.manage', 'Permite crear y modificar elementos del dashboard tecnico.')
on conflict do nothing;

insert into developer_dashboard_modules
  (module_key, title, description, category, icon, frontend_route, display_order, metadata)
values
  ('overview', 'Resumen tecnico', 'KPIs operativos, salud general y accesos rapidos.', 'operations', 'layout-dashboard', '/developer', 10, '{"frontend_status":"pending"}'),
  ('institutions', 'Instituciones', 'Gestion de tenants, branding y estado operativo.', 'platform', 'building-2', '/developer/institutions', 20, '{"frontend_status":"pending"}'),
  ('users', 'Usuarios y roles', 'Administracion de cuentas, roles y permisos.', 'identity', 'users', '/developer/users', 30, '{"frontend_status":"pending"}'),
  ('academic', 'Academico', 'Control tecnico de clases, grupos, materias y periodos.', 'school', 'graduation-cap', '/developer/academic', 40, '{"frontend_status":"pending"}'),
  ('assignments', 'Tareas', 'Monitoreo de tareas, entregas y adjuntos.', 'school', 'clipboard-list', '/developer/assignments', 50, '{"frontend_status":"pending"}'),
  ('attendance', 'Asistencia', 'Monitoreo de sesiones, marcaciones y sincronizacion offline.', 'school', 'calendar-check', '/developer/attendance', 60, '{"frontend_status":"pending"}'),
  ('grades', 'Notas', 'Control de escalas, evaluaciones, notas y boletines.', 'school', 'bar-chart-3', '/developer/grades', 70, '{"frontend_status":"pending"}'),
  ('payments', 'Pagos', 'Monitoreo de cargos, pagos y conciliacion.', 'finance', 'credit-card', '/developer/payments', 80, '{"frontend_status":"pending"}'),
  ('communications', 'Comunicacion', 'Chat, anuncios, notificaciones y push.', 'communication', 'messages-square', '/developer/communications', 90, '{"frontend_status":"pending"}'),
  ('storage', 'Storage', 'Archivos, adjuntos y buckets Supabase.', 'platform', 'folder', '/developer/storage', 100, '{"frontend_status":"pending"}'),
  ('apis', 'APIs pendientes', 'Inventario de endpoints listos para conectar en interfaz.', 'developer', 'plug', '/developer/apis', 110, '{"frontend_status":"pending"}'),
  ('feature_flags', 'Feature flags', 'Activacion controlada de funcionalidades.', 'developer', 'toggle-left', '/developer/feature-flags', 120, '{"frontend_status":"pending"}'),
  ('system_health', 'Salud del sistema', 'Checks manuales/HTTP/SQL/script para operaciones.', 'developer', 'activity', '/developer/health', 130, '{"frontend_status":"pending"}'),
  ('audit', 'Auditoria tecnica', 'Historial de cambios hechos desde el dashboard tecnico.', 'developer', 'scroll-text', '/developer/audit', 140, '{"frontend_status":"pending"}')
on conflict do nothing;

insert into developer_api_registry
  (module_key, method, path, action, summary, description, backend_status, frontend_status, request_schema, response_schema, source_file, priority, notes)
values
  ('overview', 'GET', '/api/developer/summary', null, 'Resumen del dashboard tecnico', 'Devuelve conteos, tareas pendientes y ultimos eventos.', 'implemented', 'pending', '{}', '{"ok":true,"data":{"counts":{},"pendingTasks":[]}}', 'backend/src/routes/developer.routes.ts', 'high', 'Pendiente conectar UI.'),
  ('institutions', 'GET', '/api/developer/institutions', null, 'Listar instituciones visibles', 'Lista instituciones segun RLS/rol.', 'implemented', 'pending', '{}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'high', 'Pendiente conectar UI.'),
  ('users', 'GET', '/api/developer/users', null, 'Listar usuarios visibles', 'Lista usuarios segun RLS/rol.', 'implemented', 'pending', '{}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'high', 'Pendiente conectar UI.'),
  ('apis', 'GET', '/api/developer/apis', null, 'Listar APIs registradas', 'Inventario filtrable de endpoints y actions.', 'implemented', 'pending', '{"query":{"moduleKey":"string?","frontendStatus":"string?"}}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'high', 'Pendiente conectar UI.'),
  ('apis', 'POST', '/api/developer/apis', null, 'Crear registro API', 'Agrega una API al inventario tecnico.', 'implemented', 'pending', '{"body":{"moduleKey":"string","method":"GET|POST|PUT|PATCH|DELETE","path":"string","summary":"string"}}', '{"ok":true,"data":{"api":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('apis', 'PATCH', '/api/developer/apis/:id', null, 'Actualizar registro API', 'Actualiza estado, notas o schemas de una API.', 'implemented', 'pending', '{"params":{"id":"number"},"body":{}}', '{"ok":true,"data":{"api":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('modules', 'GET', '/api/developer/modules', null, 'Listar modulos del dashboard', 'Lista modulos configurables para la futura interfaz.', 'implemented', 'pending', '{}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'high', 'Pendiente conectar UI.'),
  ('modules', 'POST', '/api/developer/modules', null, 'Crear modulo del dashboard', 'Crea un modulo configurable.', 'implemented', 'pending', '{"body":{"moduleKey":"string","title":"string"}}', '{"ok":true,"data":{"module":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('modules', 'PATCH', '/api/developer/modules/:id', null, 'Actualizar modulo del dashboard', 'Actualiza modulo configurable.', 'implemented', 'pending', '{"params":{"id":"number"},"body":{}}', '{"ok":true,"data":{"module":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('tasks', 'GET', '/api/developer/tasks', null, 'Listar tareas tecnicas', 'Lista backlog tecnico para conectar la UI.', 'implemented', 'pending', '{"query":{"status":"string?","moduleKey":"string?"}}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'high', 'Pendiente conectar UI.'),
  ('tasks', 'POST', '/api/developer/tasks', null, 'Crear tarea tecnica', 'Crea tareas de seguimiento tecnico.', 'implemented', 'pending', '{"body":{"title":"string","moduleKey":"string?"}}', '{"ok":true,"data":{"task":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('tasks', 'PATCH', '/api/developer/tasks/:id', null, 'Actualizar tarea tecnica', 'Actualiza estado/prioridad/owner de una tarea.', 'implemented', 'pending', '{"params":{"id":"number"},"body":{}}', '{"ok":true,"data":{"task":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('feature_flags', 'GET', '/api/developer/feature-flags', null, 'Listar feature flags', 'Lista flags globales o de institucion visibles.', 'implemented', 'pending', '{}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('feature_flags', 'POST', '/api/developer/feature-flags', null, 'Crear feature flag', 'Crea un flag de activacion controlada.', 'implemented', 'pending', '{"body":{"flagKey":"string","title":"string","enabled":"boolean?"}}', '{"ok":true,"data":{"featureFlag":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('feature_flags', 'PATCH', '/api/developer/feature-flags/:id', null, 'Actualizar feature flag', 'Actualiza estado/configuracion de un flag.', 'implemented', 'pending', '{"params":{"id":"number"},"body":{}}', '{"ok":true,"data":{"featureFlag":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('system_health', 'GET', '/api/developer/system-checks', null, 'Listar checks de sistema', 'Lista checks manuales/SQL/HTTP/script.', 'implemented', 'pending', '{}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('system_health', 'POST', '/api/developer/system-checks', null, 'Crear check de sistema', 'Crea un check configurable.', 'implemented', 'pending', '{"body":{"checkKey":"string","title":"string"}}', '{"ok":true,"data":{"systemCheck":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('system_health', 'PATCH', '/api/developer/system-checks/:id', null, 'Actualizar check de sistema', 'Actualiza estado o resultado de un check.', 'implemented', 'pending', '{"params":{"id":"number"},"body":{}}', '{"ok":true,"data":{"systemCheck":{}}}', 'backend/src/routes/developer.routes.ts', 'medium', 'Pendiente conectar UI.'),
  ('audit', 'GET', '/api/developer/audit-events', null, 'Listar auditoria tecnica', 'Lista eventos generados por el dashboard tecnico.', 'implemented', 'pending', '{}', '{"ok":true,"data":[]}', 'backend/src/routes/developer.routes.ts', 'low', 'Pendiente conectar UI.')
on conflict do nothing;

insert into developer_tasks
  (module_key, title, description, status, priority, frontend_required, backend_ready, notes)
values
  ('overview', 'Construir UI del dashboard tecnico', 'Crear pantallas Flutter que consuman /api/developer/*.', 'pending', 'high', true, true, 'Backend y tablas preparados en 0014_developer_dashboard.sql.'),
  ('apis', 'Conectar inventario de APIs pendientes', 'Mostrar developer_api_registry y permitir cambiar frontend_status.', 'pending', 'high', true, true, 'La documentacion se genera en docs/APIS_PENDIENTES_POR_CONECTAR.md.'),
  ('system_health', 'Definir checks ejecutables', 'Decidir cuales checks seran manuales, SQL, HTTP o scripts.', 'pending', 'medium', true, true, 'La tabla ya soporta status y last_result.')
on conflict do nothing;

insert into developer_feature_flags
  (flag_key, title, description, enabled, rollout_percent, config)
values
  ('developer_dashboard_enabled', 'Developer dashboard', 'Activa la futura interfaz tecnica cuando este lista.', false, 0, '{"frontend_connected":false}'),
  ('developer_dashboard_write_actions', 'Escritura desde developer dashboard', 'Permite operaciones de escritura en la futura UI tecnica.', false, 0, '{"requires_confirmation":true}')
on conflict do nothing;

insert into developer_system_checks
  (check_key, title, description, check_type, target, severity, status, metadata)
values
  ('backend_health', 'Backend health endpoint', 'Verifica GET /health del backend Node.', 'http', '/health', 'high', 'unknown', '{"frontend_status":"pending"}'),
  ('supabase_rls_smoke', 'Smoke test Supabase/RLS', 'Ejecuta backend/scripts/e2e_smoke.mjs por roles demo.', 'script', 'backend/scripts/e2e_smoke.mjs', 'critical', 'unknown', '{"frontend_status":"pending"}'),
  ('business_api_e2e', 'E2E business-api', 'Ejecuta backend/scripts/business_api_e2e.mjs por roles demo.', 'script', 'backend/scripts/business_api_e2e.mjs', 'critical', 'unknown', '{"frontend_status":"pending"}')
on conflict do nothing;
