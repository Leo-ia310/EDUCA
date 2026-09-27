# Backend - Educa360

El backend principal de Educa360 vive ahora como una API Node.js + TypeScript en
`backend/src`. Supabase queda separado en la raiz del repo como infraestructura:
PostgreSQL, migraciones, RLS, Auth, Storage, RPC, Realtime y Edge Functions
especiales.

## Arquitectura

```text
backend/
├─ src/
│  ├─ routes/          URLs y wiring HTTP
│  ├─ controllers/     Entrada/salida HTTP
│  ├─ services/        Logica empresarial, permisos y casos de uso
│  ├─ repositories/    Acceso a Supabase/PostgreSQL
│  ├─ middleware/      Auth, permisos de ruta y errores
│  ├─ validators/      Validaciones de payload
│  ├─ lib/             Env, Supabase, errores y helpers compartidos
│  ├─ types/           Tipos transversales
│  ├─ app.ts
│  └─ server.ts
├─ scripts/            Migraciones, seed y smoke tests conectados
├─ package.json
├─ tsconfig.json
└─ .env.example

../supabase/
├─ config.toml
├─ migrations/
├─ seed.sql
├─ seed_auth_users.sql
└─ functions/
   ├─ business-api/    Edge Function legacy temporal
   └─ send-push/       Edge Function independiente para Web Push
```

Flujo de una escritura de negocio:

```text
Frontend -> Route -> Middleware -> Controller -> Service -> Repository -> Supabase
```

Los repositories son la unica capa que debe contener `.from()`, `.select()`,
`.insert()`, `.update()`, `.delete()` o `.rpc()`. Los services explican las
reglas de negocio: roles, pertenencia, estados, calculos y validaciones de
operaciones.

## Variables De Entorno

Copia `backend/.env.example` a `backend/.env` y completa los secretos reales.
No subas `.env` al repo.

| Variable | Uso |
| --- | --- |
| `PORT` | Puerto del backend Node. Default: `3000`. |
| `CORS_ORIGIN` | Origen permitido, `*` en desarrollo. |
| `TRUST_PROXY` | Activa `trust proxy` cuando corre detras de proxy/load balancer. |
| `JSON_BODY_LIMIT` | Limite del body JSON. Default actual: `512kb`. |
| `RATE_LIMIT_WINDOW_MS` / `RATE_LIMIT_MAX` | Ventana y maximo global de solicitudes por IP. |
| `AUTH_RATE_LIMIT_MAX` | Maximo para rutas autenticadas/API de negocio. |
| `FILE_UPLOAD_MAX_BYTES` | Tamano maximo permitido para subidas firmadas a Storage. |
| `FILE_ALLOWED_MIME_TYPES` | Allowlist de MIME para archivos separados por coma. |
| `PASSWORD_RESET_REDIRECT_URL` | Redirect opcional para recuperacion de contraseña Supabase Auth. |
| `SEND_PUSH_URL` | URL opcional de la Edge Function `send-push`; si falta se deriva de `SUPABASE_URL`. |
| `EMAIL_PROVIDER` | Proveedor de correo. Valor previsto: `resend`. |
| `RESEND_API_KEY` | API key de Resend. Nunca va al repo ni al cliente. |
| `RESEND_FROM_EMAIL` | Remitente transaccional. Default: `no-reply@nivramop.com`. |
| `BACKEND_API_BASE_URL` | Base publica que recibe Flutter, por ejemplo `http://localhost:3000/api`. |
| `SUPABASE_URL` | URL del proyecto Supabase. |
| `SUPABASE_ANON_KEY` | Clave publica para Flutter y smoke tests. |
| `SUPABASE_SERVICE_ROLE_KEY` | Clave secreta opcional para tareas server-side/admin. Nunca va al frontend. |
| `SUPABASE_DB_*` | Conexion directa para `backend/scripts`. |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | Web Push; la privada solo va en Supabase secrets. |
| `INTERNAL_API_SECRET` | Secreto servidor a servidor para funciones sensibles como `send-push`. |

La API Node centraliza Supabase en `src/lib/supabase.ts`. Cada request usa un
cliente Supabase con el JWT del usuario, por lo que RLS sigue aplicando. La
`service_role` queda opcional para tareas administrativas server-side; nunca se
expone al navegador.

En produccion no uses `CORS_ORIGIN=*`. Define la lista exacta de origenes del
frontend separada por comas y configura `INTERNAL_API_SECRET` tambien en
Supabase secrets para que `send-push` no quede invocable publicamente.

## Ejecutar

Backend Node:

```bash
cd backend
npm install
npm run dev
```

Build/validacion:

```bash
cd backend
npm run build
npm test
```

Supabase local o remoto:

```bash
supabase link --project-ref qwfkmijewogksfizdski
supabase db push
supabase db execute --file supabase/seed.sql
supabase db execute --file supabase/seed_auth_users.sql
```

Frontend conectado:

```bash
cd frontend
.\run_dev.ps1 -Device chrome
```

`frontend/run_dev.ps1` lee `backend/.env` y pasa `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `BACKEND_API_BASE_URL` y `VAPID_PUBLIC_KEY` via
`--dart-define`.

## Endpoint Compatible

Para no romper el frontend, el contrato migrado sigue siendo:

```http
POST /api/business-api
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "action": "assignments.upsert",
  "payload": {}
}
```

Respuesta exitosa:

```json
{ "ok": true, "data": {} }
```

Respuesta de error:

```json
{
  "ok": false,
  "error": {
    "code": "validation_error",
    "message": "Mensaje compatible"
  }
}
```

El servidor tambien acepta `/functions/v1/business-api` sobre el host Node para
facilitar proxies o despliegues transitorios. Las rutas por dominio existen bajo
`/api/auth`, `/api/admin`, `/api/assignments`, `/api/attendance`, `/api/chats`,
`/api/events`, `/api/files`, `/api/grades`, `/api/notifications`,
`/api/payments`, `/api/reports` y `/api/sync`.

## Auth Institucional

El login para Flutter se hace contra el backend:

```http
POST /api/auth/login
Content-Type: application/json

{
  "institutionCode": "EDU360",
  "username": "teacher",
  "password": "********"
}
```

El backend resuelve `institutions.code` + `users.username` y autentica la
contraseña contra Supabase Auth. Para ese lookup sin JWT se requiere
`SUPABASE_SERVICE_ROLE_KEY` solo en el backend. La respuesta incluye tokens
Supabase y contexto institucional.

Rutas complementarias:

- `POST /api/auth/refresh`
- `POST /api/auth/recover-password`
- `POST /api/auth/logout`

La recuperación de contraseña ya no usa el envío de correo de Supabase: Node
genera el link con Supabase Admin y lo envía por Resend desde
`no-reply@nivramop.com`. El dominio `nivramop.com` ya está verificado en Resend;
la API key debe configurarse solo en `RESEND_API_KEY`.

## APIs Administrativas Nuevas

Las rutas `/api/admin/*` solo aceptan `admin` y `super_admin`. `admin` opera
únicamente sobre su institución. `super_admin` representa al equipo desarrollador:
puede ver todos los colegios y usar `institutionId`, `search` y `active` como
filtros según la ruta.

Estas rutas usan `SUPABASE_SERVICE_ROLE_KEY` solo en backend para permitir que
`super_admin` cruce instituciones; nunca expongas esa key al cliente.

- `/api/admin/institutions`
- `/api/admin/users`
- `/api/admin/roles`
- `/api/admin/students`
- `/api/admin/teachers`
- `/api/admin/parents`

## Archivos, Reportes Y Sync

- `/api/files/prepare-upload` valida nombre, MIME, tamaño y entrega subida
  firmada a Supabase Storage con ruta `{institution_id}/...`.
- `/api/files/metadata` guarda metadatos en `files`.
- `/api/reports/report-cards/preview` calcula boletín desde `period_grades`.
- `/api/reports/report-cards` persiste `report_cards` y `report_card_lines`.
- `/api/sync/queue` registra y consulta asistencia offline del profesor.
- `/api/sync/changes` expone cambios de asistencia para reconciliación puntual.

PDF binario, pasarela real de pagos e invitaciones/avisos por correo quedan
documentados como pendientes fuera del MVP backend actual. Offline queda acotado
a profesores tomando asistencia sin conexión: se guarda en el teléfono y se sube
cuando vuelve internet.

## Inventario De Acciones Migradas

Todas usan `POST /api/business-api`, requieren `Authorization: Bearer <JWT>` y
envian `{ action, payload }`.

| Action | Modulo | Roles principales | Payload principal | Data |
| --- | --- | --- | --- | --- |
| `assignments.teacherClasses` | assignments | teacher/admin | `{}` | `ClassSessionBrief[]` |
| `assignments.upsert` | assignments | teacher/admin | `assignmentId?, classId, title, description?, instructions?, dueAt, maxScore, allowLate, published?, attachments[]` | `{ assignment }` |
| `assignments.delete` | assignments | teacher/admin | `id` | `{ ok: true }` |
| `assignments.publish` | assignments | teacher/admin | `id, published` | `{ ok: true }` |
| `assignments.submit` | assignments | student/admin | `assignmentId, studentId?, attachments[], notes?` | `{ submission }` |
| `assignments.gradeSubmission` | assignments | teacher/admin | `submissionId, score, feedback?` | `{ submission }` |
| `attendance.upsertClassSession` | attendance | teacher/admin | `classId, dateMs` | `{ id }` |
| `attendance.upsertAttendance` | attendance | teacher/admin | `uuid, classId, classSessionId, studentId, statusId, recordedAtMs, notes?` | `{ id }` |
| `chat.sendMessage` | chats | participante | `conversationId, content?, attachment?` | `{ message }` |
| `chat.markAsRead` | chats | participante | `conversationId` | `{ ok: true }` |
| `chat.ensureIndividual` | chats | usuario autenticado | `otherUserId` | `{ conversationId }` |
| `events.create` | events | teacher/admin | `title, description, date, audience` | `{ event }` |
| `grades.upsertScale` | grades | admin/coordinator/director | `id?, name, type, minValue, maxValue, passValue, decimals, ranges[]` | `{ scale }` |
| `grades.setDefaultScale` | grades | admin/coordinator/director | `id` | `{ ok: true }` |
| `grades.setGrade` | grades | teacher/admin | `evaluationId, studentId, rawScore, notes?` | `{ ok: true }` |
| `notifications.saveWebPushDevice` | notifications | usuario autenticado | `endpoint, pushToken` | `{ ok: true }` |
| `payments.register` | payments | parent/admin | `chargeId, amount, method, payerName?, reference?, gatewayName?` | `{ payment }` |
| `payments.cancelCharge` | payments | admin/coordinator/director | `chargeId` | `{ ok: true }` |

## Edge Functions Conservadas

`supabase/functions/business-api` se conserva temporalmente como respaldo hasta
confirmar que no hay frontend, webhook ni servicio externo llamandola.

`supabase/functions/send-push` se conserva como Edge Function real porque envia
Web Push de forma independiente a partir de `notifications`.

## Scripts

Los scripts Node existentes siguen en `backend/scripts/`, leen `backend/.env` y
apuntan a `../supabase`:

```bash
cd backend/scripts
npm install
node db.mjs check
node db.mjs migrate
node db.mjs seed
node e2e_smoke.mjs
node business_api_e2e.mjs
```

`business_api_e2e.mjs` arranca el backend Node en un puerto temporal, inicia
sesion como teacher/student/parent/admin y prueba acciones reales de
assignments, attendance, chat, events, grades, notifications y payments. Las
filas creadas por el test se marcan con `E2E-*` y se limpian al final.

`npm run docs:apis` genera `docs/APIS_PENDIENTES_POR_CONECTAR.md` y
`docs/openapi.json` desde `backend/src/lib/api-manifest.ts`.

## Docker

El backend incluye `backend/Dockerfile`:

```bash
cd backend
docker build -t nivra-backend .
docker run --env-file .env -p 3000:3000 nivra-backend
```
