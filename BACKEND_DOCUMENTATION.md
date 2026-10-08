# Nubi Backend Documentation

> Estado documentado a partir del código actual del repositorio `EDUCA`.
> El backend se identifica en el código como **Educa360**; esta documentación usa
> **Nubi** como nombre de producto solicitado y conserva los nombres técnicos
> reales de carpetas, paquetes y servicios.

## 1. Descripción General

El backend de Nubi es una API Node.js + TypeScript para una plataforma SaaS
escolar multi-institución. Expone operaciones autenticadas para tareas,
asistencia, calificaciones, pagos, eventos, chat, notificaciones Web Push y un
panel técnico de desarrollador.

Problema que resuelve:

- Centraliza datos académicos y operativos de una institución educativa.
- Aísla datos por colegio mediante `institution_id` y políticas RLS de Supabase.
- Permite que Flutter consuma una API estable mientras conviven rutas REST y un
  dispatcher compatible con una Edge Function previa.
- Delega autenticación, base de datos, Storage y RLS a Supabase/PostgreSQL.

Tecnologías utilizadas:

| Capa | Tecnología real |
| --- | --- |
| Runtime | Node.js >= 20 |
| Lenguaje | TypeScript estricto, CommonJS |
| Framework HTTP | Express 4 |
| Seguridad HTTP | Helmet, CORS, express-rate-limit |
| Base de datos | PostgreSQL gestionado por Supabase |
| Auth | Supabase Auth con JWT Bearer |
| Storage | Supabase Storage, bucket privado `files` |
| Scripts DB/E2E | Node.js, `pg`, Fetch API |
| Frontend consumidor | Flutter, fuera del alcance de este documento |

Responsabilidades principales:

- Validar JWT y construir contexto de aplicación.
- Aplicar autorización por rol, pertenencia a institución y relación con
  docente/estudiante/padre.
- Validar payloads y reglas de negocio antes de persistir.
- Ejecutar operaciones contra Supabase usando el JWT del usuario para respetar
  RLS.
- Generar inventario de APIs pendientes desde `backend/src/lib/api-manifest.ts`.

## 2. Contexto del Producto

Nubi es una plataforma SaaS escolar multi-institución para colegios, academias e
instituciones educativas. Su objetivo es centralizar:

- Asistencia.
- Tareas y entregas.
- Comunicación y chat.
- Calificaciones.
- Boletines.
- Notificaciones.
- Reportes.
- Archivos.
- Pagos escolares, implementados parcialmente como módulo opcional.

El producto separa cada colegio como tenant. El campo principal para aislamiento
es `institution_id`; cada request autenticado queda asociada a una institución
por el usuario de aplicación enlazado al JWT de Supabase.

## 3. Arquitectura del Proyecto

Patrón arquitectónico usado:

```text
HTTP client
  -> Express route
  -> middleware de seguridad/auth/permisos
  -> controller
  -> service
  -> repository
  -> Supabase/PostgreSQL
  -> response JSON
```

Capas del backend:

| Carpeta/archivo | Responsabilidad |
| --- | --- |
| `backend/src/app.ts` | Crea la app Express, middlewares globales, healthcheck y monta módulos. |
| `backend/src/server.ts` | Inicia el servidor HTTP en `env.port`. |
| `backend/src/routes/` | Define URLs, verbos HTTP y middleware por ruta. |
| `backend/src/controllers/` | Lee `req`, normaliza params/body y delega a servicios. |
| `backend/src/services/` | Casos de uso, reglas de negocio, permisos y validación semántica. |
| `backend/src/repositories/` | Acceso a tablas/RPC de Supabase. Es la capa que usa `.from()`, `.rpc()`, etc. |
| `backend/src/middleware/` | Auth, permisos, seguridad, request-id y errores. |
| `backend/src/validators/` | Validadores comunes de string, número, fecha, ID, lista y record. |
| `backend/src/lib/` | Env, cliente Supabase, errores, helpers DB y archivos. |
| `backend/src/types/` | Tipos transversales de request/contexto. |
| `backend/scripts/` | Migraciones remotas, seeds, smoke tests y E2E conectados. |
| `supabase/migrations/` | Esquema SQL, RLS, hardening, seeds y tablas auxiliares. |
| `supabase/functions/` | Edge Functions legacy/independientes (`business-api`, `send-push`). |

Flujo de request:

1. Express recibe la request y aplica `requestIdMiddleware`, Helmet, CORS,
   `noStore`, rate limiting y `express.json`.
2. Las rutas `/api/*` aplican `authenticatedRateLimit`.
3. La ruta del módulo aplica `authMiddleware`.
4. `authMiddleware` extrae `Authorization: Bearer <jwt>`, valida el usuario con
   `supabase.auth.getUser(token)`, busca `public.users` y roles, y llena
   `req.appContext`.
5. Middleware de permisos o el service verifica roles y relaciones.
6. El controller normaliza `params`/`body` y llama al service.
7. El service valida negocio y llama al repository.
8. El repository opera contra Supabase/PostgreSQL.
9. El controller responde `{ "ok": true, "data": ... }`.
10. Errores controlados responden `{ "ok": false, "error": { code, message, requestId } }`.

## 4. Instalación y Ejecución

Requisitos previos:

- Node.js 20 o superior.
- npm.
- Proyecto Supabase disponible.
- Credenciales de Supabase y Postgres para scripts conectados.
- Opcional: CLI de Supabase para `db push`, Edge Functions y Storage.

Instalación:

```bash
cd backend
npm install
```

Configuración:

```bash
cd backend
copy .env.example .env
```

Completar `backend/.env` con valores reales. No subir `.env` al repositorio.

Desarrollo:

```bash
cd backend
npm run dev
```

Producción:

```bash
cd backend
npm run build
npm start
```

Validación y pruebas disponibles:

```bash
cd backend
npm run typecheck
npm test
```

`npm test` ejecuta `npm run docs:apis` y `tsc --noEmit`.

Generación de documentación de APIs pendientes:

```bash
cd backend
npm run docs:apis
```

Migraciones y seeds mediante scripts propios:

```bash
cd backend/scripts
node db.mjs check
node db.mjs migrate
node db.mjs seed
node db.mjs apply ../../supabase/migrations/0015_sync_developer_api_registry.sql
```

Migraciones con Supabase CLI:

```bash
supabase link --project-ref <project-ref>
supabase db push
supabase db execute --file supabase/seed.sql
supabase db execute --file supabase/seed_auth_users.sql
```

E2E conectados:

```bash
cd backend
npm run build
cd scripts
node e2e_smoke.mjs
node business_api_e2e.mjs
node developer_api_e2e.mjs
```

## 5. Variables de Entorno

No incluir secretos reales en documentación, issues, commits ni logs.

| Variable | Descripción | Obligatoria/Opcional | Ejemplo seguro |
| --- | --- | --- | --- |
| `NODE_ENV` | Ambiente de ejecución. | Opcional | `development` |
| `PORT` | Puerto HTTP del backend. | Opcional | `3000` |
| `CORS_ORIGIN` | Orígenes permitidos, separados por coma. `*` solo en desarrollo. | Opcional | `http://localhost:8080` |
| `TRUST_PROXY` | Habilita `app.set("trust proxy", 1)`. | Opcional | `false` |
| `JSON_BODY_LIMIT` | Límite del body JSON. | Opcional | `512kb` |
| `RATE_LIMIT_WINDOW_MS` | Ventana del rate limit global. | Opcional | `900000` |
| `RATE_LIMIT_MAX` | Máximo global de requests por IP/ventana. | Opcional | `300` |
| `AUTH_RATE_LIMIT_MAX` | Máximo para rutas autenticadas por token/IP. | Opcional | `120` |
| `FILE_UPLOAD_MAX_BYTES` | Tamaño máximo para subidas firmadas a Storage. | Opcional | `10485760` |
| `FILE_ALLOWED_MIME_TYPES` | Allowlist de tipos MIME aceptados. | Opcional | `application/pdf,image/png` |
| `PASSWORD_RESET_REDIRECT_URL` | Redirect opcional para recuperación de contraseña. | Opcional | `https://app.example/reset` |
| `SEND_PUSH_URL` | URL opcional de `send-push`; si falta se deriva de `SUPABASE_URL`. | Opcional | `https://example.supabase.co/functions/v1/send-push` |
| `EMAIL_PROVIDER` | Proveedor de correo transaccional. | Opcional | `resend` |
| `RESEND_API_KEY` | API key de Resend. No se guarda en el repo ni se expone al cliente. | Requerida para enviar correos reales | `re_********` |
| `RESEND_FROM_EMAIL` | Remitente transaccional. | Opcional | `no-reply@nivramop.com` |
| `INTERNAL_API_SECRET` | Secreto interno servidor-servidor, usado por Edge Functions sensibles. | Opcional, requerido para `send-push` segura | `internal-secret-placeholder` |
| `BACKEND_API_BASE_URL` | Base pública usada por Flutter. | Opcional para backend, necesaria para cliente | `http://localhost:3000/api` |
| `SUPABASE_PROJECT_REF` | Ref del proyecto Supabase. | Opcional para scripts/CLI | `abc123projectref` |
| `SUPABASE_URL` | URL pública del proyecto Supabase. | Obligatoria | `https://example.supabase.co` |
| `SUPABASE_ANON_KEY` | Clave pública anon; respeta RLS. | Obligatoria | `eyJ...public...` |
| `SUPABASE_SERVICE_ROLE_KEY` | Clave service role, ignora RLS. | Opcional, solo backend/admin | `eyJ...service...` |
| `SUPABASE_DB_PASSWORD` | Password Postgres para scripts. | Obligatoria para scripts DB | `********` |
| `SUPABASE_DB_HOST` | Host/pooler Postgres. | Obligatoria para scripts DB | `aws-1-us-west-2.pooler.supabase.com` |
| `SUPABASE_DB_PORT` | Puerto Postgres. | Opcional | `5432` |
| `SUPABASE_DB_USER` | Usuario Postgres. | Obligatoria para scripts DB | `postgres.projectref` |
| `SUPABASE_DB_NAME` | Base de datos. | Opcional | `postgres` |
| `VAPID_PUBLIC_KEY` | Clave pública Web Push. | Opcional, necesaria para push web | `BExamplePublicKey` |
| `VAPID_PRIVATE_KEY` | Clave privada Web Push. | Opcional, necesaria para `send-push` | `********` |

Variables realmente leídas por la API Node en `backend/src/lib/env.ts`:

- `NODE_ENV`
- `PORT`
- `CORS_ORIGIN`
- `TRUST_PROXY`
- `JSON_BODY_LIMIT`
- `RATE_LIMIT_WINDOW_MS`
- `RATE_LIMIT_MAX`
- `AUTH_RATE_LIMIT_MAX`
- `FILE_UPLOAD_MAX_BYTES`
- `FILE_ALLOWED_MIME_TYPES`
- `PASSWORD_RESET_REDIRECT_URL`
- `SEND_PUSH_URL`
- `EMAIL_PROVIDER`
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INTERNAL_API_SECRET`

## 6. Base de Datos

Motor:

- PostgreSQL en Supabase.
- Supabase Auth para usuarios autenticados (`auth.users`).
- Supabase Storage para archivos.
- RLS activado en tablas operativas.

Migraciones principales:

| Archivo | Propósito |
| --- | --- |
| `0001_init_core.sql` | Catálogos, instituciones, RBAC, personas, usuarios, estructura académica, asistencia y archivos. |
| `0002_init_academic_extras.sql` | Tareas, entregas, calificaciones, boletines, comunicación, chat, pagos, offline sync y settings. |
| `0003_rls_policies.sql` | Helpers RLS y políticas multi-tenant. |
| `0004_seed_catalogs.sql` | Catálogos/roles iniciales. |
| `0005_fix_chat_rls.sql` | Ajustes RLS de chat. |
| `0006_hardening.sql` | Hardening RLS, Storage bucket `files`, índices y triggers. |
| `0007_assignments_published.sql` | Campo `published` en tareas y constraints de adjuntos. |
| `0008_business_rules.sql` | Reglas de negocio/RPC adicionales. |
| `0009` a `0013` | Datos demo: vínculos, chat, anuncios, eventos, hijos adicionales. |
| `0014_developer_dashboard.sql` | Tablas del dashboard técnico. |
| `0015_sync_developer_api_registry.sql` | Sincronización de inventario de APIs developer. |

Tablas principales:

| Dominio | Tablas reales |
| --- | --- |
| Instituciones | `institutions`, `institution_settings` |
| RBAC | `roles`, `permissions`, `role_permissions`, `user_roles` |
| Identidad | `persons`, `users`, `sessions`, `devices`, `login_attempts`, `audit_log` |
| Comunidad escolar | `students`, `teachers`, `parents`, `parent_students`, `staff` |
| Académico | `academic_years`, `academic_periods`, `grade_levels`, `sections`, `classrooms`, `subjects`, `groups`, `classes`, `schedules`, `enrollments` |
| Calendario | `holidays`, `calendar_events` |
| Asistencia | `class_sessions`, `attendances`, `attendance_justifications` |
| Archivos | `files`, `assignment_files`, `submission_files` |
| Tareas | `assignments`, `submissions` |
| Calificaciones | `grading_scales`, `grading_scale_ranges`, `evaluations`, `grades`, `period_grades`, `report_cards`, `report_card_lines` |
| Comunicación | `email_templates`, `notifications`, `notification_deliveries`, `announcements`, `announcement_reads` |
| Chat | `conversations`, `conversation_participants`, `messages`, `message_reads` |
| Pagos | `payment_concepts`, `charges`, `payments` |
| Offline | `sync_queue`, `change_log` |
| Developer | `developer_dashboard_modules`, `developer_api_registry`, `developer_tasks`, `developer_feature_flags`, `developer_system_checks`, `developer_audit_events` |

Campos y relaciones importantes:

- Casi todas las tablas operativas incluyen `institution_id` como FK a
  `institutions(id)`.
- `users.auth_user_id` referencia `auth.users(id)`.
- `users.person_id` referencia `persons(id)`.
- `students`, `teachers`, `parents` referencian `persons(id)`.
- `parent_students` vincula padres con estudiantes.
- `classes` vincula `groups`, `subjects`, `teachers` y `academic_years`.
- `enrollments` vincula estudiantes con grupos/año académico.
- `assignments` pertenece a `classes` y opcionalmente a `academic_periods`.
- `submissions` es única por `(assignment_id, student_id)`.
- `evaluations` puede enlazarse a una `assignment_id`.
- `grades` es única por `(evaluation_id, student_id)`.
- `class_sessions` representa una clase en una fecha; `attendances` es única por
  `(class_session_id, student_id)`.
- `files` guarda metadatos; Storage guarda el binario.
- `payments` registra abonos contra `charges`.

Índices relevantes documentados en migraciones:

- `idx_institutions_active`
- `idx_persons_institution`
- `idx_users_institution`
- `idx_class_sessions_class_date`
- `idx_class_sessions_group_date`
- `idx_attendances_student`
- `idx_notifications_user_unread`
- `idx_sync_queue_device_status`
- `idx_change_log_table`
- Índices de hardening sobre `groups`, `classes`, `enrollments`, `grades`,
  `evaluations`, `messages`, `conversation_participants`, `payments`,
  `charges`, `assignments` y `submissions`.

Reglas multi-institución:

- El aislamiento base es `institution_id`.
- `authMiddleware` obtiene `institutionId` desde `public.users`, no desde el
  body.
- Los services escriben siempre `institution_id: ctx.institutionId` cuando crean
  datos operativos.
- Los repositories filtran por `ctx.institutionId` en operaciones sensibles.
- RLS define `public.current_institution_id()` desde claims JWT o app metadata.
- Las tablas sin `institution_id` directo se aíslan por join a tablas padre.
- Storage usa carpeta `{institution_id}/...` en bucket `files`.

Seeds:

- `supabase/seed.sql` carga datos base/demo.
- `supabase/seed_auth_users.sql` crea usuarios demo en `auth.users`,
  `public.users` y `user_roles`.
- Los scripts E2E esperan usuarios demo con password `demo1234`.

## 7. Autenticación

Estado real:

- Existe endpoint Node `POST /api/auth/login` para login institucional con
  código de colegio, usuario y contraseña.
- El backend resuelve `institutions.code` + `users.username` usando
  `SUPABASE_SERVICE_ROLE_KEY` y luego autentica la contraseña contra Supabase
  Auth. Node no guarda ni valida hashes de contraseña propios.
- El cliente sigue usando el `access_token` de Supabase como Bearer token:

```http
Authorization: Bearer <access_token>
```

Endpoints:

| Método | Ruta | Auth | Descripción |
| --- | --- | --- | --- |
| `POST` | `/api/auth/login` | Público | Resuelve colegio/usuario y devuelve sesión Supabase + contexto institucional. |
| `POST` | `/api/auth/refresh` | Público | Renueva sesión con `refreshToken`. |
| `POST` | `/api/auth/recover-password` | Público | Genera link con Supabase Admin y envía recuperación por Resend si la cuenta existe. |
| `POST` | `/api/auth/logout` | Usuario autenticado | Cierra sesión contra Supabase Auth. |

Request de login:

```json
{
  "institutionCode": "EDU360",
  "username": "teacher",
  "password": "********"
}
```

Funcionamiento de `authMiddleware`:

1. Lee `Authorization`.
2. Extrae el Bearer token.
3. Crea un cliente Supabase por request con ese JWT.
4. Ejecuta `auth.getUser(token)`.
5. Busca en `public.users` un usuario activo con `auth_user_id`.
6. Carga `user_roles(roles(code))`.
7. Construye `AppContext`:

```ts
{
  authUserId: string;
  userId: number;
  institutionId: number;
  personId: number | null;
  fullName: string;
  roles: Set<string>;
}
```

Errores de autenticación:

- `401 unauthorized`: sin token.
- `401 unauthorized`: token inválido o expirado.
- `403 forbidden`: usuario sin roles asignados.

Login con código de colegio + usuario + contraseña:

- Implementado en `/api/auth/login`.
- Usa `institutions.code` y `users.username`.
- Requiere `SUPABASE_SERVICE_ROLE_KEY` en backend porque el usuario aún no tiene
  JWT y RLS no puede resolver tenant antes del login.
- Autenticación real de contraseña: Supabase Auth por email asociado al usuario.

Refresh token:

- Implementado en `/api/auth/refresh`.
- El backend delega en `supabase.auth.refreshSession`.

Recuperación de contraseña:

- Implementada en `/api/auth/recover-password`.
- El backend busca colegio + usuario, genera el link de recuperación con
  Supabase Admin y envía el correo con Resend.
- `PASSWORD_RESET_REDIRECT_URL` permite definir redirect seguro si el frontend lo
  requiere.
- Remitente previsto: `no-reply@nivramop.com`.

Logout:

- Implementado en `/api/auth/logout`.
- El cliente también debe descartar tokens locales.

## 8. Roles y Permisos

Roles observados en código y seeds:

- `super_admin`
- `director`
- `admin`
- `coordinator`
- `teacher`
- `parent`
- `student`

Regla técnica central:

- `PermissionsService.isAdmin(ctx)` considera administrativos a:
  `admin`, `super_admin`, `coordinator`, `director`.
- `PermissionsService.hasAnyRole(ctx, roles)` permite el rol solicitado o
  cualquier rol administrativo.
- Por eso muchas rutas con `requireRoles(["teacher"])` también aceptan admin,
  coordinator, director y super_admin por lógica de service/middleware.

Tabla de permisos efectiva:

| Rol | Puede hacer | Restricciones |
| --- | --- | --- |
| `super_admin` | Equipo desarrollador; puede gestionar todos los colegios en `/api/admin/*` y filtrar por `institutionId`, `search` o `active`. | Debe estar autenticado. |
| `director` | Acceso administrativo académico en módulos protegidos por `isAdmin`. | No puede usar `/api/admin/*`. |
| `admin` | Administración institucional y uso de `/api/admin/*` solo para su colegio. | Limitado a su institución. |
| `coordinator` | Tratado como administrativo académico por `isAdmin`. | No puede usar `/api/admin/*`. |
| `teacher` | Crear/editar/publicar/eliminar tareas, registrar asistencia, crear eventos, calificar entregas, setear notas, operar chat. | Solo clases que imparte, salvo si también tiene rol admin. |
| `parent` | Registrar pagos de cargos de estudiantes vinculados y usar chat/notificaciones. | Solo estudiantes asociados en `parent_students`. |
| `student` | Entregar tareas, chat, notificaciones. | Solo su estudiante enlazado a `person_id`. |

Restricciones por relación:

- Un profesor no puede modificar clases/tareas de otro profesor.
- Un estudiante no puede operar sobre otro estudiante.
- Un padre no puede operar sobre estudiantes no vinculados.
- Un usuario solo puede participar en conversaciones donde existe
  `conversation_participants`.
- Un archivo adjunto debe pertenecer a la misma institución.

## 9. Módulos del Sistema

### Auth

- Propósito: autenticar JWT y construir `AppContext`.
- Archivos: `auth.middleware.ts`, `auth.repository.ts`,
  `permissions.service.ts`, `permissions.middleware.ts`.
- Entidades: `auth.users`, `users`, `roles`, `user_roles`, `teachers`,
  `students`, `parents`, `parent_students`.
- Endpoints propios: `/api/auth/login`, `/api/auth/refresh`,
  `/api/auth/recover-password`, `/api/auth/logout`.
- Reglas: requiere Bearer token Supabase; usuario activo; al menos un rol.
- Login institucional: resuelve `institutions.code` + `users.username` y
  autentica contra Supabase Auth.

### Institutions

- Propósito: tenant principal.
- Archivos: `admin.routes.ts`, `admin.service.ts`, `admin.repository.ts` y
  `developer.repository.ts` para dashboard.
- Entidades: `institutions`, `institution_settings`.
- Endpoints: `/api/admin/institutions` y `GET /api/developer/institutions`.
- Reglas: RLS por tenant; `/api/admin/*` solo acepta `admin` y `super_admin`.
  `super_admin` puede listar todos los colegios y filtrar por `search`/`active`;
  `admin` solo ve su institución.
- Implementación: `/api/admin/*` usa `SUPABASE_SERVICE_ROLE_KEY` en el backend
  para permitir operaciones multi-colegio de `super_admin`; el service aplica
  manualmente el límite institucional de `admin`.
- Estado: CRUD administrativo implementado.

### Users

- Propósito: cuentas de aplicación enlazadas a Supabase Auth.
- Archivos: `auth.repository.ts`, `admin.repository.ts`,
  `developer.repository.ts`.
- Entidades: `users`, `user_roles`, `roles`, `persons`.
- Endpoints: `/api/admin/users` y `GET /api/developer/users`.
- Estado: CRUD administrativo implementado. `super_admin` puede filtrar por
  `institutionId`; `admin` solo opera en su institución. Invitaciones y avisos
  usarán Resend.

### Roles

- Propósito: RBAC y permisos.
- Archivos: `permissions.service.ts`, `admin.service.ts`.
- Entidades: `roles`, `permissions`, `role_permissions`, `user_roles`.
- Endpoints: `/api/admin/roles`.
- Estado: CRUD de roles institucionales no sistémicos implementado.

### Students

- Propósito: representar alumnos y validar acceso.
- Archivos: `auth.repository.ts`, `permissions.service.ts`,
  `admin.service.ts`.
- Entidades: `students`, `enrollments`, `parent_students`.
- Endpoints directos: `/api/admin/students`.
- Usado por: assignments, attendance, grades, payments.

### Teachers

- Propósito: representar docentes y validar clases.
- Archivos: `auth.repository.ts`, `permissions.service.ts`,
  `assignments.service.ts`, `attendance.service.ts`, `grades.service.ts`,
  `admin.service.ts`.
- Entidades: `teachers`, `classes`.
- Endpoints directos: `/api/admin/teachers`.
- Reglas: el usuario docente debe estar enlazado por `person_id`.

### Parents

- Propósito: representar acudientes/padres y acceso a estudiantes.
- Archivos: `permissions.service.ts`, `payments.service.ts`,
  `admin.service.ts`.
- Entidades: `parents`, `parent_students`.
- Endpoints directos: `/api/admin/parents`.
- Reglas: pagos solo sobre estudiantes vinculados.

### Attendance

- Propósito: sesiones de clase y marcaciones de asistencia offline-first.
- Archivos: `attendance.routes.ts`, `attendance.controller.ts`,
  `attendance.service.ts`, `attendance.repository.ts`.
- Entidades: `class_sessions`, `attendances`,
  `catalog_attendance_statuses`, `enrollments`.
- Endpoints: `/api/attendance/class-sessions/upsert`,
  `/api/attendance/upsert`, actions `attendance.*`.
- Reglas: solo teacher/admin; clase debe pertenecer a institución; estudiante
  debe estar matriculado en el grupo; `uuid` evita duplicados.

### Assignments

- Propósito: tareas, publicación, entregas, adjuntos y calificación.
- Archivos: `assignments.routes.ts`, `assignments.controller.ts`,
  `assignments.service.ts`, `assignments.repository.ts`.
- Entidades: `assignments`, `assignment_files`, `submissions`,
  `submission_files`, `files`, `evaluations`, `grades`.
- Endpoints: `/api/assignments/*`, actions `assignments.*`.
- Reglas: teacher/admin solo puede usar sus clases; entrega requiere tarea
  publicada; `allow_late=false` bloquea entregas vencidas; calificar usa RPC
  `grade_submission`.

### Grades

- Propósito: escalas, escala default y registro de notas.
- Archivos: `grades.routes.ts`, `grades.controller.ts`,
  `grades.service.ts`, `grades.repository.ts`.
- Entidades: `grading_scales`, `grading_scale_ranges`,
  `institution_settings`, `evaluations`, `grades`.
- Endpoints: `/api/grades/*`, actions `grades.*`.
- Reglas: escalas solo admin; rangos dentro de min/max; notas no negativas;
  estudiante debe pertenecer a la clase de la evaluación.

### Notifications

- Propósito: guardar suscripciones/dispositivos Web Push.
- Archivos: `notifications.routes.ts`, `notifications.controller.ts`,
  `notifications.service.ts`, `notifications.repository.ts`,
  `supabase/functions/send-push`.
- Entidades: `devices`, `notifications`, `notification_deliveries`.
- Endpoints: `/api/notifications/web-push-device`,
  action `notifications.saveWebPushDevice`.
- Estado: guardar dispositivo implementado; creación automática de
  notificaciones y webhook a `send-push` pendiente.

### Reports

- Propósito esperado: boletines y reportes.
- Entidades existentes: `report_cards`, `report_card_lines`, `period_grades`.
- Endpoints Node: no existen.
- Estado: **Pendiente / No implementado en backend Node**.

### Files

- Propósito: metadatos de archivos y adjuntos.
- Entidades: `files`, `assignment_files`, `submission_files`.
- Helpers: `backend/src/lib/files.ts`.
- Endpoints Node de subida: no existen.
- Estado: el backend solo vincula archivos ya registrados; la subida real se
  maneja fuera de estas rutas, probablemente desde Supabase Storage/cliente.

### Dashboard / Developer

- Propósito: dashboard técnico para inventario de módulos, APIs, tareas, flags,
  checks, usuarios e instituciones.
- Archivos: `developer.routes.ts`, `developer.controller.ts`,
  `developer.service.ts`, `developer.repository.ts`.
- Entidades: tablas `developer_*`.
- Endpoints: `/api/developer/*`.
- Reglas: solo roles administrativos; soft-delete con `deleted_at`; auditoría en
  `developer_audit_events`.

### Events

- Propósito: crear eventos/anuncios de calendario.
- Archivos: `events.routes.ts`, `events.controller.ts`, `events.service.ts`,
  `events.repository.ts`.
- Entidades: `calendar_events`.
- Endpoints: `POST /api/events`, action `events.create`.
- Reglas: teacher/admin; `title`, `description`, `date`, `audience`.

### Chats

- Propósito: conversaciones individuales, mensajes y lectura.
- Archivos: `chats.routes.ts`, `chats.controller.ts`, `chats.service.ts`,
  `chats.repository.ts`.
- Entidades: `conversations`, `conversation_participants`, `messages`,
  `message_reads`, `files`.
- Endpoints: `/api/chats/*`, actions `chat.*`.
- Reglas: participante requerido para enviar/leer; mensaje requiere contenido o
  adjunto; no se permite conversación consigo mismo.

### Payments

- Propósito: registrar pagos contra cargos y anular cargos.
- Archivos: `payments.routes.ts`, `payments.controller.ts`,
  `payments.service.ts`, `payments.repository.ts`.
- Entidades: `payment_concepts`, `charges`, `payments`, `parents`,
  `parent_students`.
- Endpoints: `/api/payments/*`, actions `payments.*`.
- Reglas: método permitido `card|transfer|cash|wallet`; monto > 0; no excede
  saldo pendiente; idempotencia por UUID opcional; cargo pagado/cancelado no se
  reabre.
- Pendiente: integración con pasarela real.

## 10. Documentación de Endpoints/API

Formato común de respuesta exitosa:

```json
{
  "ok": true,
  "data": {}
}
```

Formato común de error:

```json
{
  "ok": false,
  "error": {
    "code": "validation_error",
    "message": "Mensaje legible.",
    "requestId": "uuid-opaco"
  }
}
```

Headers para endpoints autenticados:

```json
{
  "Authorization": "Bearer <supabase_access_token>",
  "Content-Type": "application/json"
}
```

### GET /health

Descripción: healthcheck público de la API Node.

Rol requerido: público.

Autenticación requerida: no.

Response 200:

```json
{
  "ok": true,
  "service": "educa360-backend"
}
```

Errores posibles: 500 si la app falla antes de responder.

### POST /api/business-api

Descripción: dispatcher compatible para acciones sensibles del frontend.

Rol requerido: depende de `action`.

Autenticación requerida: sí.

Body:

```json
{
  "action": "assignments.teacherClasses",
  "payload": {}
}
```

Response 200:

```json
{
  "ok": true,
  "data": {}
}
```

Errores posibles:

- 400: payload inválido.
- 401: sesión requerida/inválida.
- 403: rol o relación insuficiente.
- 404: acción no soportada.
- 429: rate limit.

Notas técnicas:

- Alias legacy: `POST /functions/v1/business-api`.
- Acciones soportadas:
  `assignments.teacherClasses`, `assignments.upsert`,
  `assignments.delete`, `assignments.publish`, `assignments.submit`,
  `assignments.gradeSubmission`, `payments.register`,
  `payments.cancelCharge`, `events.create`,
  `attendance.upsertClassSession`, `attendance.upsertAttendance`,
  `grades.upsertScale`, `grades.setDefaultScale`, `grades.setGrade`,
  `chat.sendMessage`, `chat.markAsRead`, `chat.ensureIndividual`,
  `notifications.saveWebPushDevice`.

### POST /functions/v1/business-api

Descripción: alias Express para compatibilidad con clientes que apuntan al path
de Edge Function.

Rol requerido: depende de `action`.

Autenticación requerida: sí.

Body/response/errores: iguales a `POST /api/business-api`.

### POST /api/assignments/teacher-classes

Descripción: lista clases activas disponibles para crear tareas.

Rol requerido: `teacher`; administrativos también pasan por `isAdmin`.

Autenticación requerida: sí.

Body:

```json
{}
```

Response 200:

```json
{
  "ok": true,
  "data": [
    {
      "classId": 1,
      "groupId": 1,
      "subjectName": "Matemáticas",
      "groupName": "7mo A",
      "startTime": "",
      "endTime": "",
      "studentCount": 25
    }
  ]
}
```

Errores posibles: 401, 403, 400 `db_error`.

### POST /api/assignments/upsert

Descripción: crea o actualiza una tarea.

Rol requerido: `teacher` o admin equivalente.

Autenticación requerida: sí.

Body:

```json
{
  "assignmentId": 123,
  "classId": 10,
  "title": "Ensayo",
  "description": "Opcional",
  "instructions": "Opcional",
  "dueAt": "2026-10-01T23:59:00.000Z",
  "maxScore": 100,
  "allowLate": true,
  "published": true,
  "attachments": [{ "id": 55 }]
}
```

Response 200:

```json
{
  "ok": true,
  "data": {
    "assignment": {
      "id": "123",
      "classId": 10,
      "title": "Ensayo",
      "maxScore": 100,
      "published": true,
      "attachments": []
    }
  }
}
```

Errores posibles:

- 400: campos inválidos, `maxScore <= 0`, adjunto de otra institución.
- 403: clase/tarea no pertenece al docente.

### POST /api/assignments/delete

Descripción: archiva una tarea por soft-delete.

Rol requerido: `teacher` o admin equivalente.

Body:

```json
{ "id": 123 }
```

Response 200:

```json
{ "ok": true, "data": { "ok": true } }
```

Errores posibles: 400, 401, 403.

### DELETE /api/assignments/:id

Descripción: equivalente REST de borrado lógico de tarea.

Path params: `id`.

Body:

```json
{}
```

Response/errores: iguales a `POST /api/assignments/delete`.

### POST /api/assignments/publish

Descripción: publica u oculta una tarea.

Rol requerido: `teacher` o admin equivalente.

Body:

```json
{
  "id": 123,
  "published": false
}
```

Response 200:

```json
{ "ok": true, "data": { "ok": true } }
```

### PATCH /api/assignments/:id/publish

Descripción: equivalente REST para cambiar publicación.

Path params: `id`.

Body:

```json
{ "published": true }
```

Response/errores: iguales a `POST /api/assignments/publish`.

### POST /api/assignments/submit

Descripción: registra o actualiza entrega de un estudiante.

Rol requerido: `student` o admin equivalente.

Body:

```json
{
  "assignmentId": 123,
  "studentId": 45,
  "attachments": [{ "id": 55 }],
  "notes": "Entrego adjunto"
}
```

Response 200:

```json
{
  "ok": true,
  "data": {
    "submission": {
      "id": "88",
      "assignmentId": "123",
      "studentId": 45,
      "status": "submitted",
      "submittedAt": "2026-09-23T12:00:00.000Z"
    }
  }
}
```

Errores posibles:

- 400: tarea no publicada; entrega tarde no permitida; adjunto inválido.
- 403: estudiante no pertenece a clase o intenta operar sobre otro estudiante.

### POST /api/assignments/grade-submission

Descripción: califica una entrega y sincroniza nota vía RPC `grade_submission`.

Rol requerido: `teacher` o admin equivalente.

Body:

```json
{
  "submissionId": 88,
  "score": 95,
  "feedback": "Buen trabajo"
}
```

Response 200:

```json
{
  "ok": true,
  "data": {
    "submission": {
      "id": "88",
      "status": "graded",
      "score": 95,
      "feedback": "Buen trabajo"
    }
  }
}
```

Errores posibles: 400 si `score < 0`, 403 si no imparte la clase.

### PATCH /api/assignments/submissions/:submissionId/grade

Descripción: equivalente REST de calificación.

Path params: `submissionId`.

Body:

```json
{ "score": 95, "feedback": "Buen trabajo" }
```

Response/errores: iguales a `POST /api/assignments/grade-submission`.

### POST /api/attendance/class-sessions/upsert

Descripción: crea o actualiza sesión de clase para asistencia.

Rol requerido: `teacher` o admin equivalente.

Body:

```json
{
  "classId": 10,
  "dateMs": 1798848000000
}
```

Response 200:

```json
{ "ok": true, "data": { "id": 77 } }
```

Errores posibles: 400 fecha/clase inválida, 403 docente sin clase.

### POST /api/attendance/upsert

Descripción: sincroniza una marcación de asistencia.

Rol requerido: `teacher` o admin equivalente.

Body:

```json
{
  "uuid": "0fb6f8d5-7a47-44ae-84d4-7c6f3b7b63c7",
  "classId": 10,
  "classSessionId": 77,
  "studentId": 45,
  "statusId": 1,
  "recordedAtMs": 1798848000000,
  "notes": "Presente"
}
```

Response 200:

```json
{ "ok": true, "data": { "id": 99 } }
```

Errores posibles:

- 400: estado de asistencia inválido.
- 403: clase no autorizada o estudiante no matriculado.

Notas técnicas:

- Si existe `uuid`, actualiza esa fila.
- Si no existe, hace upsert por `(class_session_id, student_id)`.

### POST /api/chats/messages

Descripción: envía mensaje de chat con texto o adjunto.

Rol requerido: usuario autenticado participante.

Body:

```json
{
  "conversationId": 15,
  "content": "Hola",
  "attachment": { "id": 55 }
}
```

Response 200:

```json
{
  "ok": true,
  "data": {
    "message": {
      "id": "120",
      "uuid": "uuid",
      "conversationId": "15",
      "senderId": "7",
      "senderName": "Usuario",
      "content": "Hola",
      "attachment": null
    }
  }
}
```

Errores posibles: 400 sin texto ni adjunto, 403 no participante.

### POST /api/chats/mark-as-read

Descripción: marca como leídos los mensajes de una conversación.

Body:

```json
{ "conversationId": 15 }
```

Response 200:

```json
{ "ok": true, "data": { "ok": true } }
```

### PATCH /api/chats/conversations/:conversationId/read

Descripción: equivalente REST para marcar conversación como leída.

Path params: `conversationId`.

Body:

```json
{}
```

Response/errores: iguales a `POST /api/chats/mark-as-read`.

### POST /api/chats/individual

Descripción: crea o reutiliza conversación individual entre usuario actual y
otro usuario de la misma institución.

Body:

```json
{ "otherUserId": 8 }
```

Response 200:

```json
{
  "ok": true,
  "data": { "conversationId": "16" }
}
```

Errores posibles:

- 400: conversación consigo mismo.
- 400/404 lógico: usuario destino no encontrado.

### POST /api/events

Descripción: crea evento en calendario.

Rol requerido: `teacher` o admin equivalente.

Body:

```json
{
  "title": "Reunión",
  "description": "Reunión con padres",
  "date": "2026-10-05T14:00:00.000Z",
  "audience": "parents"
}
```

Response 200:

```json
{
  "ok": true,
  "data": {
    "event": {
      "id": "33",
      "title": "Reunión",
      "description": "Reunión con padres",
      "date": "2026-10-05T14:00:00.000Z",
      "audience": "parents"
    }
  }
}
```

Errores posibles: 400 campos inválidos, 403 rol insuficiente.

### POST /api/grades/scales/upsert

Descripción: crea o actualiza escala de calificación.

Rol requerido: admin, coordinator, director o super_admin.

Body:

```json
{
  "id": 1,
  "name": "Numérica 0-100",
  "type": "numeric",
  "minValue": 0,
  "maxValue": 100,
  "passValue": 60,
  "decimals": 0,
  "ranges": [
    { "label": "Aprobado", "rangeMin": 60, "rangeMax": 100, "passed": true, "color": "#22c55e" }
  ]
}
```

Response 200:

```json
{
  "ok": true,
  "data": { "scale": { "id": 1, "name": "Numérica 0-100" } }
}
```

Errores posibles:

- 400: tipo fuera de `numeric|qualitative|letters`.
- 400: rango fuera de min/max o color inválido.
- 403: no admin.

### POST /api/grades/scales/default

Descripción: define escala institucional por defecto.

Rol requerido: admin, coordinator, director o super_admin.

Body:

```json
{ "id": 1 }
```

Response 200:

```json
{ "ok": true, "data": { "ok": true } }
```

### PATCH /api/grades/scales/:id/default

Descripción: equivalente REST para escala default.

Path params: `id`.

Body:

```json
{}
```

Response/errores: iguales a `POST /api/grades/scales/default`.

### POST /api/grades/set-grade

Descripción: registra o actualiza nota de estudiante.

Rol requerido: `teacher` o admin equivalente.

Body:

```json
{
  "evaluationId": 12,
  "studentId": 45,
  "rawScore": 88,
  "notes": "Recuperación"
}
```

Response 200:

```json
{ "ok": true, "data": { "ok": true } }
```

Errores posibles:

- 400: nota negativa.
- 403: docente no imparte la clase o estudiante no matriculado.

### POST /api/notifications/web-push-device

Descripción: guarda o actualiza la suscripción Web Push del usuario.

Rol requerido: usuario autenticado.

Body:

```json
{
  "endpoint": "https://push.example/subscription/abc",
  "pushToken": "{\"endpoint\":\"https://push.example/subscription/abc\",\"keys\":{\"p256dh\":\"...\",\"auth\":\"...\"}}"
}
```

Response 200:

```json
{ "ok": true, "data": { "ok": true } }
```

Errores posibles: 400 endpoint/token inválido, 401.

### POST /api/payments/register

Descripción: registra un pago contra un cargo.

Rol requerido: `parent` o admin equivalente.

Body:

```json
{
  "chargeId": 10,
  "amount": 25.5,
  "method": "cash",
  "payerName": "María López",
  "reference": "REC-001",
  "gatewayName": "Caja",
  "idempotencyKey": "0fb6f8d5-7a47-44ae-84d4-7c6f3b7b63c7"
}
```

Response 200:

```json
{
  "ok": true,
  "data": {
    "payment": {
      "id": "100",
      "chargeId": "10",
      "chargeConcept": "Mensualidad",
      "studentName": "Estudiante",
      "method": "cash",
      "amount": 25.5,
      "currencyCode": "USD",
      "status": "paid",
      "receiptNumber": "RC-1790000000000"
    }
  }
}
```

Errores posibles:

- 400: monto <= 0, método inválido, idempotencyKey no UUID.
- 400: cargo cerrado o monto excede saldo pendiente.
- 403: padre no vinculado al estudiante.

### POST /api/payments/cancel-charge

Descripción: anula cargo.

Rol requerido: admin, coordinator, director o super_admin.

Body:

```json
{ "chargeId": 10 }
```

Response 200:

```json
{ "ok": true, "data": { "ok": true } }
```

### PATCH /api/payments/charges/:chargeId/cancel

Descripción: equivalente REST para anular cargo.

Path params: `chargeId`.

Body:

```json
{}
```

Response/errores: iguales a `POST /api/payments/cancel-charge`.

### GET /api/developer/summary

Descripción: resumen operativo del dashboard técnico.

Rol requerido: admin, coordinator, director o super_admin.

Response 200:

```json
{
  "ok": true,
  "data": {
    "counts": {},
    "pendingTasks": [],
    "recentAuditEvents": []
  }
}
```

### GET /api/developer/institutions

Descripción: lista instituciones visibles.

Rol requerido: admin, coordinator, director o super_admin.

Response 200:

```json
{ "ok": true, "data": [] }
```

### GET /api/developer/users

Descripción: lista usuarios visibles con roles.

Rol requerido: admin, coordinator, director o super_admin.

Response 200:

```json
{ "ok": true, "data": [] }
```

### GET /api/developer/audit-events

Descripción: lista eventos de auditoría técnica.

Rol requerido: admin, coordinator, director o super_admin.

Response 200:

```json
{ "ok": true, "data": [] }
```

### GET /api/developer/modules

Descripción: lista módulos configurables.

Query params: filtros directos soportados por repository; service reconoce
`moduleKey` para recursos con `module_key`.

Response 200:

```json
{ "ok": true, "data": [] }
```

### POST /api/developer/modules

Descripción: crea módulo configurable.

Body:

```json
{
  "moduleKey": "reports",
  "title": "Reportes",
  "description": "Módulo de reportes",
  "category": "academic",
  "icon": "bar_chart",
  "frontendRoute": "/reports",
  "requiredRoles": ["admin"],
  "enabled": true,
  "displayOrder": 10,
  "metadata": {}
}
```

Response 201:

```json
{ "ok": true, "data": { "module": {} } }
```

### PATCH /api/developer/modules/:id

Descripción: actualiza módulo configurable.

Path params: `id`.

Body: campos parciales del módulo.

Response 200:

```json
{ "ok": true, "data": { "module": {} } }
```

### DELETE /api/developer/modules/:id

Descripción: archiva módulo configurable con `deleted_at`.

Path params: `id`.

Response 200:

```json
{ "ok": true, "data": { "module": {} } }
```

### GET /api/developer/apis

Descripción: lista inventario de APIs.

Query params:

- `moduleKey`
- `backendStatus`
- `frontendStatus`

Response 200:

```json
{ "ok": true, "data": [] }
```

### POST /api/developer/apis

Descripción: crea registro en inventario de APIs.

Body:

```json
{
  "moduleKey": "assignments",
  "method": "POST",
  "path": "/api/assignments/upsert",
  "summary": "Crea o actualiza tarea",
  "action": "assignments.upsert",
  "authRequired": true,
  "requiredRoles": ["teacher"],
  "backendStatus": "implemented",
  "frontendStatus": "connected",
  "requestSchema": {},
  "responseSchema": {}
}
```

Response 201:

```json
{ "ok": true, "data": { "api": {} } }
```

### PATCH /api/developer/apis/:id

Descripción: actualiza registro API.

Path params: `id`.

Body: campos parciales.

Response 200:

```json
{ "ok": true, "data": { "api": {} } }
```

### DELETE /api/developer/apis/:id

Descripción: archiva registro API.

Path params: `id`.

Response 200:

```json
{ "ok": true, "data": { "api": {} } }
```

### GET /api/developer/tasks

Descripción: lista tareas técnicas.

Query params: `moduleKey`, `status`.

Response 200:

```json
{ "ok": true, "data": [] }
```

### POST /api/developer/tasks

Descripción: crea tarea técnica.

Body:

```json
{
  "title": "Conectar reportes",
  "moduleKey": "reports",
  "description": "Implementar endpoint",
  "status": "pending",
  "priority": "high",
  "owner": "backend",
  "frontendRequired": true,
  "backendReady": false,
  "dueAt": "2026-10-01T00:00:00.000Z"
}
```

Response 201:

```json
{ "ok": true, "data": { "task": {} } }
```

### PATCH /api/developer/tasks/:id

Descripción: actualiza tarea técnica.

Path params: `id`.

Body: campos parciales.

Response 200:

```json
{ "ok": true, "data": { "task": {} } }
```

### DELETE /api/developer/tasks/:id

Descripción: archiva tarea técnica.

Path params: `id`.

Response 200:

```json
{ "ok": true, "data": { "task": {} } }
```

### GET /api/developer/feature-flags

Descripción: lista feature flags.

Query params: `enabled`.

Response 200:

```json
{ "ok": true, "data": [] }
```

### POST /api/developer/feature-flags

Descripción: crea feature flag.

Body:

```json
{
  "flagKey": "new_dashboard",
  "title": "Nuevo dashboard",
  "description": "Activa el nuevo dashboard",
  "enabled": false,
  "rolloutPercent": 10,
  "config": {},
  "metadata": {}
}
```

Response 201:

```json
{ "ok": true, "data": { "featureFlag": {} } }
```

### PATCH /api/developer/feature-flags/:id

Descripción: actualiza feature flag.

Path params: `id`.

Response 200:

```json
{ "ok": true, "data": { "featureFlag": {} } }
```

### DELETE /api/developer/feature-flags/:id

Descripción: archiva feature flag.

Path params: `id`.

Response 200:

```json
{ "ok": true, "data": { "featureFlag": {} } }
```

### GET /api/developer/system-checks

Descripción: lista checks de sistema.

Query params: `status`, `severity`.

Response 200:

```json
{ "ok": true, "data": [] }
```

### POST /api/developer/system-checks

Descripción: crea check de sistema.

Body:

```json
{
  "checkKey": "backend_health",
  "title": "Backend health",
  "description": "Verifica /health",
  "checkType": "http",
  "target": "/health",
  "severity": "high",
  "status": "unknown",
  "enabled": true,
  "lastResult": {},
  "lastCheckedAt": "2026-09-23T00:00:00.000Z"
}
```

Response 201:

```json
{ "ok": true, "data": { "systemCheck": {} } }
```

### PATCH /api/developer/system-checks/:id

Descripción: actualiza check de sistema.

Path params: `id`.

Response 200:

```json
{ "ok": true, "data": { "systemCheck": {} } }
```

### DELETE /api/developer/system-checks/:id

Descripción: archiva check de sistema.

Path params: `id`.

Response 200:

```json
{ "ok": true, "data": { "systemCheck": {} } }
```

## 11. DTOs, Validaciones y Modelos

Validadores comunes:

| Función | Regla |
| --- | --- |
| `requiredString(value, label, max)` | String obligatorio, trim, longitud máxima. |
| `optionalString(value, max)` | String opcional, trim, vacío -> null. |
| `requiredId(value, label)` | Entero positivo. |
| `optionalId(value)` | ID opcional o null. |
| `requiredNumber(value, label)` | Número finito. |
| `requiredDate(value, label)` | Fecha parseable desde string o number. |
| `asList(value)` | Array o `[]`. |
| `asRecord(value)` | Objeto plano o `{}`. |

DTOs principales:

| DTO | Campos requeridos | Campos opcionales | Validaciones |
| --- | --- | --- | --- |
| Business action | `action`, `payload` | - | `action` string max 100. |
| Assignment upsert | `classId`, `title`, `dueAt`, `maxScore` | `assignmentId`, `description`, `instructions`, `allowLate`, `published`, `attachments` | `maxScore > 0`; clase permitida. |
| Assignment submit | `assignmentId` | `studentId`, `attachments`, `notes` | tarea publicada; fecha según `allow_late`; estudiante válido. |
| Grade submission | `submissionId`, `score` | `feedback` | `score >= 0`. |
| Attendance session | `classId`, `dateMs` | - | fecha válida; clase del docente. |
| Attendance mark | `uuid`, `classId`, `studentId`, `statusId`, `recordedAtMs`, `classSessionId` | `notes` | estado existe; estudiante en grupo. |
| Chat message | `conversationId` | `content`, `attachment.id` | requiere texto o adjunto; usuario participante. |
| Event create | `title`, `description`, `date`, `audience` | - | longitudes máximas. |
| Grade scale | `name`, `type`, `minValue`, `maxValue`, `passValue`, `decimals` | `id`, `ranges` | tipo permitido; rango válido; color `#RRGGBB`. |
| Set grade | `evaluationId`, `studentId`, `rawScore` | `notes` | `rawScore >= 0`; estudiante en clase. |
| Web push device | `endpoint`, `pushToken` | - | string max 2000/5000. |
| Register payment | `chargeId`, `amount`, `method` | `payerName`, `reference`, `gatewayName`, `idempotencyKey` | monto positivo; método permitido; UUID idempotente si viene. |

## 12. Reglas de Negocio Importantes

- Cada colegio tiene su propio espacio privado por `institution_id`.
- Los datos deben filtrarse por `institution_id` desde `ctx`, no desde el body.
- Un padre solo puede ver/operar estudiantes vinculados en `parent_students`.
- Un profesor solo puede gestionar clases donde `classes.teacher_id` coincide
  con su registro `teachers.id`.
- Un estudiante solo puede operar sobre su propio registro enlazado por
  `person_id`.
- Director/admin/coordinator/super_admin se consideran administrativos por
  `PermissionsService.isAdmin`.
- Super admin puede gestionar recursos globales del dashboard developer cuando
  se envía `global: true` o `institutionId: null`.
- Una tarea debe estar publicada para poder entregarse.
- Una tarea con `allow_late=false` rechaza entregas después de `due_at`.
- Una entrega se identifica por `(assignment_id, student_id)`.
- Una asistencia se identifica por `uuid` o por `(class_session_id, student_id)`.
- Un pago no puede exceder el saldo pendiente del cargo.
- Un cargo `paid` o `cancelled` no admite nuevos pagos.
- Una conversación solo puede ser usada por sus participantes.

## 13. Sincronización Offline

Estado actual:

- Implementación funcional acotada al caso de asistencia de profesores.
- Existen tablas `sync_queue` y `change_log`.
- El módulo de asistencia tiene diseño offline-first desde frontend y sincroniza
  hacia `attendance.upsertClassSession` y `attendance.upsertAttendance`.
- `attendances.uuid` permite reconciliar marcas creadas offline.
- `class_sessions.synced` existe y se marca `true` desde backend.
- Existe API Node `/api/sync/*` para cola offline de asistencia.
- Regla de producto: solo aplica para profesor tomando asistencia cuando no hay
  luz o internet. Los cambios se guardan localmente en el teléfono y se suben al
  recuperar conexión.
- No aplica a pagos, chat, tareas, calificaciones ni CRUD administrativo.

Endpoints:

| Método | Ruta | Descripción |
| --- | --- | --- |
| `GET` | `/api/sync/queue` | Lista operaciones offline de asistencia del profesor. |
| `POST` | `/api/sync/queue` | Encola asistencia offline para subir al recuperar conexión. |
| `POST` | `/api/sync/queue/:id/retry` | Marca operación para reintento. |
| `POST` | `/api/sync/queue/:id/failed` | Marca operación como fallida. |
| `GET` | `/api/sync/changes` | Lista cambios de asistencia desde `since`. |

Estados esperados mencionados por el requerimiento:

| Estado | Estado real |
| --- | --- |
| `queued` | Estado inicial en `sync_queue`. |
| `processing` | Reservado para worker/runner futuro. |
| `synced` | Estado final esperado cuando un runner aplique la operación. |
| `failed` | Implementado para errores reintentables. |

Cómo se evitan duplicados actualmente:

- Asistencia: `uuid` y unique `(class_session_id, student_id)`.

Pendiente:

- Alinear Flutter para guardar asistencia offline en el teléfono y llamar
  `/api/sync/queue` o los endpoints de asistencia al recuperar conexión.
- Runner/reintentos automáticos si se decide procesar `sync_queue` en servidor.
- Política de conflicto documentada: `teacher_attendance_upload_only`.

## 14. Archivos y Storage

Estado real:

- Tabla `files` guarda metadatos: `original_name`, `storage_path`, `url`,
  `size_bytes`, `mime_type`, `uploaded_by`, `deleted_at`.
- Relaciones:
  - `assignment_files(assignment_id, file_id)`
  - `submission_files(submission_id, file_id)`
  - `messages.file_id`
- Bucket Supabase Storage: `files`, privado.
- Convención de path: `{institution_id}/{folder}/{filename}`.
- RLS de Storage valida el primer segmento del path.

Subida de archivos:

- Se usa Supabase Storage directo con preparación controlada por Node.
- `POST /api/files/prepare-upload` valida `originalName`, `mimeType`,
  `sizeBytes`, carpeta opcional y devuelve una URL/token de subida firmado para
  el bucket `files`.
- `POST /api/files/metadata` registra metadatos en `files` después de subir.
- `GET /api/files` lista metadatos de la institución.

Tipos/tamaños permitidos:

- `FILE_UPLOAD_MAX_BYTES` define el tamaño máximo. Default: `10485760`.
- `FILE_ALLOWED_MIME_TYPES` define la allowlist de MIME.
- La ruta debe iniciar con `{institution_id}/`; si no coincide, el backend
  rechaza la operación.

Seguridad:

- Adjuntos se rechazan si `files.institution_id !== ctx.institutionId`.
- Storage bucket privado + políticas por carpeta de institución.

## 15. Notificaciones

Tablas:

- `notifications`
- `notification_deliveries`
- `devices`
- `catalog_notification_types`
- `catalog_notification_channels`
- `email_templates`

Implementado:

- `POST /api/notifications/web-push-device` guarda/actualiza suscripción Web
  Push en `devices`.
- Edge Function `supabase/functions/send-push` puede enviar Web Push desde una
  fila `notifications` a dispositivos activos.
- `events.create` crea notificaciones de negocio para la audiencia indicada.
- Si `INTERNAL_API_SECRET` está configurado, Node invoca `send-push` por cada
  notificación creada.

Pendiente real:

- Correo de recuperación ya está preparado con Resend; faltan invitaciones y
  avisos transaccionales.
- No hay Firebase/FCM; el README de `send-push` indica Web Push con VAPID.
- Falta ampliar reglas automáticas a tareas, calificaciones, pagos, chat y
  asistencia.

Invocación documentada de `send-push`:

```http
POST /functions/v1/send-push
Authorization: Bearer <INTERNAL_API_SECRET>
Content-Type: application/json
```

```json
{ "notificationId": 123 }
```

## 16. Reportes y Boletines

Estado real:

- Existen tablas `period_grades`, `report_cards`, `report_card_lines`.
- Existen endpoints Node para previsualizar y generar boletines académicos.
- El cálculo oficial MVP es promedio aritmético simple de
  `period_grades.final_score` para estudiante + periodo.
- `POST /api/reports/report-cards` persiste `report_cards` y
  `report_card_lines`.

Endpoints:

| Método | Ruta | Descripción |
| --- | --- | --- |
| `GET` | `/api/reports/report-cards/preview` | Previsualiza cálculo sin persistir. |
| `POST` | `/api/reports/report-cards` | Genera y persiste boletín. |
| `GET` | `/api/reports/report-cards/:id` | Consulta boletín generado. |

Pendiente:

- Generación binaria de PDF y plantilla oficial.
- Persistencia segura de PDF generado en Storage.
- Ranking académico y ponderaciones si se definen reglas más complejas.

## 17. Seguridad

Medidas aplicadas:

- JWT Supabase requerido para `/api/*`.
- Clientes Supabase por request con Bearer token del usuario.
- RLS en PostgreSQL para aislamiento multi-tenant.
- `helmet` para headers de seguridad.
- `cors` con allowlist configurable.
- Rechazo de `CORS_ORIGIN=*` en producción.
- `express-rate-limit` global y autenticado.
- `express.json` con límite configurable.
- `x-powered-by` deshabilitado.
- `cache-control: no-store`.
- Errores normalizados sin stack trace al cliente.
- `x-request-id` expuesto.
- Validadores de inputs en services.
- Soft-delete en recursos clave.

Hash de contraseñas:

- Gestionado por Supabase Auth.
- `seed_auth_users.sql` crea usuarios demo para entornos controlados.

Riesgos pendientes:

- No hay validación estructural con schemas formales tipo Zod/Joi.
- Algunos endpoints REST tienen middleware `requireRoles(["teacher"])` pero el
  service permite administrativos por `isAdmin`; documentar esta convención para
  evitar confusiones.
- `SUPABASE_SERVICE_ROLE_KEY`, si se configura, debe protegerse estrictamente.
- No hay endpoint propio de auditoría general fuera del dashboard developer.
- `send-push` depende de configurar secreto interno para enviar Web Push.

## 18. Códigos HTTP y Errores

| Código HTTP | Significado | Cuándo ocurre | Ejemplo |
| --- | --- | --- | --- |
| 200 | OK | Operación exitosa. | `{ "ok": true, "data": {} }` |
| 201 | Created | Creación en endpoints developer. | `{ "ok": true, "data": { "task": {} } }` |
| 400 | Bad Request | Validación de payload o error DB controlado. | `{ "ok": false, "error": { "code": "validation_error", "message": "Título es obligatorio." } }` |
| 401 | Unauthorized | Falta token o token inválido/expirado. | `{ "ok": false, "error": { "code": "unauthorized", "message": "Sesión requerida." } }` |
| 403 | Forbidden | Rol insuficiente o relación no autorizada. | `{ "ok": false, "error": { "code": "forbidden", "message": "No tienes permiso para realizar esta acción." } }` |
| 404 | Not Found | Ruta no encontrada o action no soportada. | `{ "ok": false, "error": { "code": "not_found", "message": "Acción no soportada: x" } }` |
| 429 | Too Many Requests | Rate limit global/autenticado. | `{ "ok": false, "error": { "code": "rate_limited", "message": "Demasiadas solicitudes." } }` |
| 500 | Internal Server Error | Error no controlado. | `{ "ok": false, "error": { "code": "internal_error", "message": "Error interno del backend." } }` |

## 19. Integraciones Externas

| Integración | Uso | Variables | Estado |
| --- | --- | --- | --- |
| Supabase Auth | Login, JWT, usuario autenticado. | `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Implementado. |
| Supabase Postgres | Base de datos relacional. | `SUPABASE_*`, `SUPABASE_DB_*` | Implementado. |
| Supabase Storage | Bucket privado `files`. | Supabase project config | Implementado con subida firmada preparada por Node y metadata en `files`. |
| Supabase Edge Function `business-api` | Legacy temporal. | Supabase env | Existe, pero Node replica `/functions/v1/business-api`. |
| Supabase Edge Function `send-push` | Web Push por VAPID. | `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `INTERNAL_API_SECRET`, `SEND_PUSH_URL` | Implementada; eventos ya invocan push si hay secreto interno. |
| Correo | Recuperación de contraseña y futuros correos transaccionales. | `EMAIL_PROVIDER`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL` | Preparado con Resend; dominio `nivramop.com` verificado y API key configurada por entorno. |
| Pasarela de pagos | Pagos escolares. | No documentadas | Pendiente; pagos registrados internamente. |
| Swagger/OpenAPI | Documentación formal API. | No aplica | `docs/openapi.json` generado desde `api-manifest`. |

## 20. Despliegue y Operación

Ambiente de desarrollo:

- `npm run dev` usa `tsx watch`.
- `CORS_ORIGIN=*` permitido solo fuera de producción.
- Supabase puede ser remoto o local si las variables apuntan correctamente.

Ambiente de producción:

- Ejecutar `npm run build` y `npm start`.
- Definir `NODE_ENV=production`.
- Configurar `TRUST_PROXY=true` si corre detrás de proxy/load balancer.
- Usar allowlist exacta en `CORS_ORIGIN`.
- Proteger `SUPABASE_SERVICE_ROLE_KEY` e `INTERNAL_API_SECRET`.

Build:

```bash
cd backend
npm run build
```

El `prebuild` ejecuta `npm run docs:apis`.

Migraciones en producción:

- Recomendado: ejecutar migraciones en ventana controlada.
- Usar `backend/scripts/db.mjs migrate` o Supabase CLI, según permisos.
- Validar con `node backend/scripts/db.mjs check`.

Docker:

- Existe `backend/Dockerfile` para build/runtime Node 22 Alpine.
- Build sugerido desde `backend/`:

```bash
docker build -t nivra-backend .
```

Backups:

- No hay scripts de backup en el repo.
- Deben configurarse desde Supabase/Postgres.

Logs:

- El servidor imprime inicio como JSON estructurado.
- `errorHandler` hace `console.error({ requestId, error })` para errores no
  controlados.
- No hay integración de observabilidad externa.

Monitoreo básico:

- `GET /health`.
- `developer_system_checks` puede representar checks manuales/http/script, pero
  no hay runner automático documentado.

## 21. Comandos Reales del Proyecto

| Acción | Comando |
| --- | --- |
| Instalar backend | `cd backend && npm install` |
| Desarrollo | `cd backend && npm run dev` |
| Build | `cd backend && npm run build` |
| Start producción | `cd backend && npm start` |
| Typecheck | `cd backend && npm run typecheck` |
| Test npm | `cd backend && npm test` |
| Generar APIs pendientes | `cd backend && npm run docs:apis` |
| Check DB | `cd backend/scripts && node db.mjs check` |
| Migrar DB | `cd backend/scripts && node db.mjs migrate` |
| Seeds | `cd backend/scripts && node db.mjs seed` |
| Aplicar SQL | `cd backend/scripts && node db.mjs apply <file.sql>` |
| Smoke Supabase/RLS | `cd backend/scripts && node e2e_smoke.mjs` |
| E2E business API | `cd backend/scripts && node business_api_e2e.mjs` |
| E2E developer API | `cd backend/scripts && node developer_api_e2e.mjs` |
| Deploy send-push | `supabase functions deploy send-push --use-api` |

Lint/formateo:

- No hay script `lint`.
- No hay script `format`.

## 22. Swagger / OpenAPI

Estado actual:

- Existe `backend/scripts/generate-openapi.ts`.
- `npm run docs:apis` genera también `docs/openapi.json`.
- No existe configuración `swagger-ui-express`, `tsoa`, `zod-to-openapi` o
  similar.

Alcance actual:

- OpenAPI se genera desde `backend/src/lib/api-manifest.ts`.
- Los schemas son amplios (`object` con propiedades adicionales) hasta que los
  DTOs se centralicen como schemas formales.
- `docs/openapi.json` sirve como contrato inicial para Flutter y QA.

Pendiente:

- Centralizar DTOs reutilizables.
- Generar schemas request/response precisos.
- Decidir si se sirve Swagger UI desde una ruta protegida.

## 23. Changelog Técnico del Estado Actual

Estado importante documentado:

- Backend Node/Express ya centraliza la API principal.
- `/api/business-api` replica el dispatcher legacy y conserva alias
  `/functions/v1/business-api`.
- Las rutas REST equivalentes existen para módulos nuevos, aunque Flutter usa
  principalmente business-api por compatibilidad.
- Developer dashboard tiene backend y tablas implementadas.
- `docs/APIS_PENDIENTES_POR_CONECTAR.md` se genera desde
  `backend/src/lib/api-manifest.ts`.
- Web Push tiene Edge Function `send-push`, pero falta wiring automático.
- Auth institucional, CRUD administrativo, archivos, reportes iniciales,
  sincronización offline inicial y OpenAPI generado ya tienen API Node.
- Web Push se invoca automáticamente desde eventos cuando
  `INTERNAL_API_SECRET` está configurado.

Regla obligatoria de mantenimiento:

Cada vez que se modifique el backend, antes de finalizar la tarea se debe revisar
si cambió algo de:

- Endpoints.
- Request/response.
- DTOs.
- Modelos.
- Tablas.
- Migraciones.
- Roles.
- Permisos.
- Variables de entorno.
- Servicios.
- Reglas de negocio.
- Flujos de autenticación.
- Integraciones externas.
- Sincronización offline acotada a asistencia de profesores.
- Reportes.
- Notificaciones.

Si algo cambió, actualizar inmediatamente este archivo
`BACKEND_DOCUMENTATION.md`.

Además, cuando cambien backend APIs, rutas, controladores, servicios,
repositorios o migraciones relacionadas con API:

1. Actualizar `backend/src/lib/api-manifest.ts`.
2. Ejecutar `cd backend && npm run docs:apis`.
3. No dejar `docs/APIS_PENDIENTES_POR_CONECTAR.md` stale.

Checklist para cambios backend:

- [ ] ¿Se creó o modificó algún endpoint?
- [ ] ¿Cambió algún request o response?
- [ ] ¿Cambió algún DTO?
- [ ] ¿Cambió algún modelo o entidad?
- [ ] ¿Cambió alguna tabla o migración?
- [ ] ¿Cambió algún permiso?
- [ ] ¿Cambió alguna variable de entorno?
- [ ] ¿Cambió alguna regla de negocio?
- [ ] ¿Cambió algún flujo de autenticación?
- [ ] ¿Cambió alguna integración externa?
- [ ] ¿Cambió sincronización offline?
- [ ] ¿Cambió reportes o notificaciones?
- [ ] ¿Se actualizó el changelog?
- [ ] ¿Se actualizó `backend/src/lib/api-manifest.ts` si aplica?
- [ ] ¿Se ejecutó `cd backend && npm run docs:apis` si aplica?
- [ ] ¿Se actualizó `BACKEND_DOCUMENTATION.md`?

## 24. Pendientes Reales Encontrados

Pendientes funcionales:

- PDF binario de boletines con plantilla oficial.
- Completar invitaciones/avisos sobre Resend.
- Integración real de pasarela de pagos.
- Conectar Flutter al flujo offline de asistencia de profesores.
- Runner automático de `developer_system_checks`.
- Schemas DTO/OpenAPI precisos.
- Observabilidad externa: métricas, trazas y alertas.

Riesgos técnicos:

- La documentación de endpoints debe mantenerse manualmente además del
  `api-manifest`.
- Los DTOs no están centralizados como schemas reutilizables.
- Algunas tablas existen antes que los módulos HTTP correspondientes.
- La service role, si se configura, ignora RLS y requiere controles estrictos.
- Los ejemplos E2E dependen de datos demo existentes.

Módulos esperados pero no implementados como API Node dedicada:

| Módulo esperado | Estado |
| --- | --- |
| Auth login propio | Implementado sobre Supabase Auth |
| Institutions CRUD | Implementado en `/api/admin/institutions` |
| Users CRUD | Implementado en `/api/admin/users` |
| Roles CRUD | Implementado en `/api/admin/roles` |
| Students CRUD | Implementado en `/api/admin/students` |
| Teachers CRUD | Implementado en `/api/admin/teachers` |
| Parents CRUD | Implementado en `/api/admin/parents` |
| Reports API | Implementado cálculo/persistencia; PDF pendiente |
| Files upload API | Implementado como subida firmada + metadata |
| Dashboard técnico | Implementado |
| Payments | Implementación interna parcial |
| Notifications | Parcial: eventos + Web Push; faltan más módulos/correo |
