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
| `BACKEND_API_BASE_URL` | Base publica que recibe Flutter, por ejemplo `http://localhost:3000/api`. |
| `SUPABASE_URL` | URL del proyecto Supabase. |
| `SUPABASE_ANON_KEY` | Clave publica para Flutter y smoke tests. |
| `SUPABASE_SERVICE_ROLE_KEY` | Clave secreta opcional para tareas server-side/admin. Nunca va al frontend. |
| `SUPABASE_DB_*` | Conexion directa para `backend/scripts`. |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | Web Push; la privada solo va en Supabase secrets. |

La API Node centraliza Supabase en `src/lib/supabase.ts`. Cada request usa un
cliente Supabase con el JWT del usuario, por lo que RLS sigue aplicando. La
`service_role` queda opcional para tareas administrativas server-side; nunca se
expone al navegador.

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
`/api/assignments`, `/api/attendance`, `/api/chats`, `/api/events`,
`/api/grades`, `/api/notifications` y `/api/payments`.

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
