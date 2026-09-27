# APIs Pendientes Por Conectar

> Archivo generado automaticamente. No editar a mano.
> Fuente: `backend/src/lib/api-manifest.ts`.
> Para actualizar: `cd backend && npm run docs:apis`.

Estas APIs ya estan preparadas en el backend, pero todavia no tienen interfaz Flutter conectada.

## Regla Para Futuras Modificaciones

Cuando se agregue, quite o cambie una API, actualiza `backend/src/lib/api-manifest.ts` y ejecuta `npm run docs:apis`. El comando `npm run build` tambien regenera este archivo antes de compilar.

## Resumen

- Total pendiente de conectar: 39
- Modulos con trabajo pendiente: 5

## Admin

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/admin/institutions` | Lista instituciones disponibles para administracion | admin, super_admin | query opcional: search, active | Institution[] | `backend/src/routes/admin.routes.ts` | Super admin ve todas y puede filtrar por search/active; admin institucional solo ve su institucion. |
| `POST` | `/api/admin/institutions` | Crea institucion | super_admin | { code, name, commercialName?, subdomain?, email?, phone?, timezone?, active? } | { institution } | `backend/src/routes/admin.routes.ts` |  |
| `PATCH` | `/api/admin/institutions/:id` | Actualiza institucion | admin de la institucion o super_admin | campos parciales de institucion | { institution } | `backend/src/routes/admin.routes.ts` |  |
| `DELETE` | `/api/admin/institutions/:id` | Archiva institucion | super_admin | param id | { institution } | `backend/src/routes/admin.routes.ts` |  |
| `GET` | `/api/admin/users` | Lista usuarios institucionales con roles | admin, super_admin | query opcional: institutionId, search, active | User[] | `backend/src/routes/admin.routes.ts` |  |
| `POST` | `/api/admin/users` | Crea usuario de aplicacion y asigna roles | admin, super_admin | { institutionId? solo super_admin, email, fullName, username?, personId?, authUserId?, roleCodes? } | { user } | `backend/src/routes/admin.routes.ts` | No crea contraseña; invitacion/credencial Supabase queda en flujo de correo/Auth. |
| `PATCH` | `/api/admin/users/:id` | Actualiza usuario institucional y roles | admin, super_admin | campos parciales de usuario; institutionId? solo super_admin; roleCodes? reemplaza roles | { user } | `backend/src/routes/admin.routes.ts` |  |
| `DELETE` | `/api/admin/users/:id` | Archiva usuario institucional | admin, super_admin | param id; query opcional: institutionId solo super_admin | { user } | `backend/src/routes/admin.routes.ts` |  |
| `GET` | `/api/admin/roles` | Lista roles globales e institucionales | admin, super_admin | query opcional: institutionId solo super_admin | Role[] | `backend/src/routes/admin.routes.ts` |  |
| `POST` | `/api/admin/roles` | Crea rol institucional | admin, super_admin | { institutionId? solo super_admin, name, code, description?, active? } | { role } | `backend/src/routes/admin.routes.ts` |  |
| `PATCH` | `/api/admin/roles/:id` | Actualiza rol institucional no sistemico | admin, super_admin | campos parciales de rol; institutionId? solo super_admin | { role } | `backend/src/routes/admin.routes.ts` |  |
| `DELETE` | `/api/admin/roles/:id` | Desactiva rol institucional no sistemico | admin, super_admin | param id; query opcional: institutionId solo super_admin | { role } | `backend/src/routes/admin.routes.ts` |  |
| `GET` | `/api/admin/students` | Lista estudiantes institucionales | admin, super_admin | query opcional: institutionId solo super_admin, search, active | Student[] con persons | `backend/src/routes/admin.routes.ts` |  |
| `POST` | `/api/admin/students` | Crea estudiante y persona | admin, super_admin | { institutionId? solo super_admin, firstName, lastName, studentCode, ... } | { student } | `backend/src/routes/admin.routes.ts` |  |
| `PATCH` | `/api/admin/students/:id` | Actualiza estudiante y persona | admin, super_admin | campos parciales; institutionId? solo super_admin | { student } | `backend/src/routes/admin.routes.ts` |  |
| `DELETE` | `/api/admin/students/:id` | Archiva estudiante | admin, super_admin | param id; query opcional: institutionId solo super_admin | { ok: true } | `backend/src/routes/admin.routes.ts` |  |
| `GET` | `/api/admin/teachers` | Lista docentes institucionales | admin, super_admin | query opcional: institutionId solo super_admin, search, active | Teacher[] con persons | `backend/src/routes/admin.routes.ts` |  |
| `POST` | `/api/admin/teachers` | Crea docente y persona | admin, super_admin | { institutionId? solo super_admin, firstName, lastName, teacherCode, ... } | { teacher } | `backend/src/routes/admin.routes.ts` |  |
| `PATCH` | `/api/admin/teachers/:id` | Actualiza docente y persona | admin, super_admin | campos parciales; institutionId? solo super_admin | { teacher } | `backend/src/routes/admin.routes.ts` |  |
| `DELETE` | `/api/admin/teachers/:id` | Archiva docente | admin, super_admin | param id; query opcional: institutionId solo super_admin | { ok: true } | `backend/src/routes/admin.routes.ts` |  |
| `GET` | `/api/admin/parents` | Lista padres/acudientes institucionales | admin, super_admin | query opcional: institutionId solo super_admin, search | Parent[] con persons | `backend/src/routes/admin.routes.ts` |  |
| `POST` | `/api/admin/parents` | Crea padre/acudiente y persona | admin, super_admin | { institutionId? solo super_admin, firstName, lastName, occupation?, ... } | { parent } | `backend/src/routes/admin.routes.ts` |  |
| `PATCH` | `/api/admin/parents/:id` | Actualiza padre/acudiente y persona | admin, super_admin | campos parciales; institutionId? solo super_admin | { parent } | `backend/src/routes/admin.routes.ts` |  |
| `DELETE` | `/api/admin/parents/:id` | Archiva padre/acudiente | admin, super_admin | param id; query opcional: institutionId solo super_admin | { ok: true } | `backend/src/routes/admin.routes.ts` |  |

## Auth

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `POST` | `/api/auth/login` | Login institucional por codigo de colegio, usuario y contraseña | publico | { institutionCode, username, password } | { session, authUser, user, institution } | `backend/src/routes/auth.routes.ts` | Resuelve institutions.code + users.username y autentica contra Supabase Auth; Node no almacena contraseñas. |
| `POST` | `/api/auth/refresh` | Renueva sesion Supabase usando refresh token | publico | { refreshToken } | { session, authUser } | `backend/src/routes/auth.routes.ts` |  |
| `POST` | `/api/auth/recover-password` | Solicita recuperación de contraseña por colegio y usuario | publico | { institutionCode, username } | { ok, message } | `backend/src/routes/auth.routes.ts` | Genera link con Supabase Admin y envia correo via Resend; PASSWORD_RESET_REDIRECT_URL es opcional. |
| `POST` | `/api/auth/logout` | Cierra sesion Supabase desde el backend | usuario autenticado | sin body | { ok: true } | `backend/src/routes/auth.routes.ts` |  |

## Files

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/files` | Lista metadatos de archivos de la institucion | usuario autenticado | sin body | File[] | `backend/src/routes/files.routes.ts` |  |
| `POST` | `/api/files/prepare-upload` | Prepara subida firmada a Supabase Storage | usuario autenticado | { originalName, mimeType, sizeBytes, folder? } | { bucket, storagePath, signedUpload, maxBytes, allowedMimeTypes } | `backend/src/routes/files.routes.ts` | Valida MIME/tamaño y fuerza ruta {institution_id}/... |
| `POST` | `/api/files/metadata` | Registra metadatos de archivo subido | usuario autenticado | { originalName, storagePath, mimeType, sizeBytes, url? } | { file } | `backend/src/routes/files.routes.ts` |  |

## Reports

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/reports/report-cards/preview` | Previsualiza boletin calculado desde period_grades | admin/teacher o estudiante/padre propio | query: studentId, academicPeriodId | { student, academicPeriodId, calculation, overallAverage, lines } | `backend/src/routes/reports.routes.ts` | Calculo oficial MVP: promedio aritmetico simple de period_grades.final_score. |
| `POST` | `/api/reports/report-cards` | Genera y persiste boletin academico | teacher, admin, coordinator, director, super_admin | { studentId, academicPeriodId, generalNotes? } | { reportCard } | `backend/src/routes/reports.routes.ts` | PDF binario queda fuera del MVP hasta definir plantilla/proveedor; devuelve pdfStatus. |
| `GET` | `/api/reports/report-cards/:id` | Obtiene boletin generado | admin/teacher o estudiante/padre propio | param id | { reportCard } | `backend/src/routes/reports.routes.ts` |  |

## Sync

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/sync/queue` | Lista operaciones offline de asistencia del profesor | teacher | query opcional: status | sync_queue[] | `backend/src/routes/sync.routes.ts` | Offline sync queda limitado a profesores tomando asistencia sin internet/luz. |
| `POST` | `/api/sync/queue` | Encola asistencia offline para subir al recuperar conexion | teacher | { tableName: attendances\|class_sessions, operation: insert\|update\|upsert, recordUuid?, payload, clientTimestamp? } | { item } | `backend/src/routes/sync.routes.ts` | Solo para profesor tomando asistencia; el registro se guarda localmente en el telefono y se sube cuando vuelva la conexion. |
| `POST` | `/api/sync/queue/:id/retry` | Marca asistencia offline para reintento | teacher | param id | { item } | `backend/src/routes/sync.routes.ts` |  |
| `POST` | `/api/sync/queue/:id/failed` | Marca asistencia offline como fallida | teacher | { error? } | { item } | `backend/src/routes/sync.routes.ts` |  |
| `GET` | `/api/sync/changes` | Lista cambios de asistencia desde una fecha | teacher | query opcional: since | { serverTime, changes, conflictPolicy, scope } | `backend/src/routes/sync.routes.ts` | Politica: teacher_attendance_upload_only. No se usa para pagos, chat, tareas o calificaciones. |
