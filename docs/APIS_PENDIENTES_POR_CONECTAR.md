# APIs Pendientes Por Conectar

> Archivo generado automaticamente. No editar a mano.
> Fuente: `backend/src/lib/api-manifest.ts`.
> Para actualizar: `cd backend && npm run docs:apis`.

Estas APIs ya estan preparadas en el backend, pero todavia no tienen interfaz Flutter conectada.

## Regla Para Futuras Modificaciones

Cuando se agregue, quite o cambie una API, actualiza `backend/src/lib/api-manifest.ts` y ejecuta `npm run docs:apis`. El comando `npm run build` tambien regenera este archivo antes de compilar.

## Resumen

- Total pendiente de conectar: 24
- Modulos con trabajo pendiente: 1

## Developer

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/developer/summary` | Resumen operativo del dashboard tecnico | admin, coordinator, director, super_admin | query opcional vacio | { counts, pendingTasks, recentAuditEvents } | `backend/src/routes/developer.routes.ts` | Pendiente conectar a una pantalla principal del dashboard de desarrollador. |
| `GET` | `/api/developer/institutions` | Lista instituciones visibles por RLS | admin, coordinator, director, super_admin | sin body | Institution[] | `backend/src/routes/developer.routes.ts` |  |
| `GET` | `/api/developer/users` | Lista usuarios visibles por RLS | admin, coordinator, director, super_admin | sin body | User[] con roles | `backend/src/routes/developer.routes.ts` |  |
| `GET` | `/api/developer/audit-events` | Lista auditoria tecnica del dashboard | admin, coordinator, director, super_admin | sin body | DeveloperAuditEvent[] | `backend/src/routes/developer.routes.ts` |  |
| `GET` | `/api/developer/modules` | Lista modulos configurables del dashboard | admin, coordinator, director, super_admin | query opcional: moduleKey | DeveloperDashboardModule[] | `backend/src/routes/developer.routes.ts` |  |
| `POST` | `/api/developer/modules` | Crea modulo configurable del dashboard | admin, coordinator, director, super_admin | { moduleKey, title, description?, category?, icon?, frontendRoute?, enabled? } | { module } | `backend/src/routes/developer.routes.ts` |  |
| `PATCH` | `/api/developer/modules/:id` | Actualiza modulo configurable del dashboard | admin, coordinator, director, super_admin | campos parciales del modulo | { module } | `backend/src/routes/developer.routes.ts` |  |
| `DELETE` | `/api/developer/modules/:id` | Archiva modulo configurable del dashboard | admin, coordinator, director, super_admin | param id | { module } | `backend/src/routes/developer.routes.ts` | Soft-delete: marca deleted_at. |
| `GET` | `/api/developer/apis` | Lista APIs registradas para conectar | admin, coordinator, director, super_admin | query opcional: moduleKey, backendStatus, frontendStatus | DeveloperApiRegistry[] | `backend/src/routes/developer.routes.ts` |  |
| `POST` | `/api/developer/apis` | Crea registro en inventario de APIs | admin, coordinator, director, super_admin | { moduleKey, method, path, summary, action?, requestSchema?, responseSchema? } | { api } | `backend/src/routes/developer.routes.ts` |  |
| `PATCH` | `/api/developer/apis/:id` | Actualiza registro del inventario de APIs | admin, coordinator, director, super_admin | campos parciales del registro API | { api } | `backend/src/routes/developer.routes.ts` |  |
| `DELETE` | `/api/developer/apis/:id` | Archiva registro del inventario de APIs | admin, coordinator, director, super_admin | param id | { api } | `backend/src/routes/developer.routes.ts` | Soft-delete: marca deleted_at. |
| `GET` | `/api/developer/tasks` | Lista tareas tecnicas del dashboard | admin, coordinator, director, super_admin | query opcional: moduleKey, status | DeveloperTask[] | `backend/src/routes/developer.routes.ts` |  |
| `POST` | `/api/developer/tasks` | Crea tarea tecnica | admin, coordinator, director, super_admin | { title, moduleKey?, description?, priority?, owner? } | { task } | `backend/src/routes/developer.routes.ts` |  |
| `PATCH` | `/api/developer/tasks/:id` | Actualiza tarea tecnica | admin, coordinator, director, super_admin | campos parciales de la tarea | { task } | `backend/src/routes/developer.routes.ts` |  |
| `DELETE` | `/api/developer/tasks/:id` | Archiva tarea tecnica | admin, coordinator, director, super_admin | param id | { task } | `backend/src/routes/developer.routes.ts` | Soft-delete: marca deleted_at. |
| `GET` | `/api/developer/feature-flags` | Lista feature flags | admin, coordinator, director, super_admin | query opcional: enabled | DeveloperFeatureFlag[] | `backend/src/routes/developer.routes.ts` |  |
| `POST` | `/api/developer/feature-flags` | Crea feature flag | admin, coordinator, director, super_admin | { flagKey, title, description?, enabled?, rolloutPercent?, config? } | { featureFlag } | `backend/src/routes/developer.routes.ts` |  |
| `PATCH` | `/api/developer/feature-flags/:id` | Actualiza feature flag | admin, coordinator, director, super_admin | campos parciales del flag | { featureFlag } | `backend/src/routes/developer.routes.ts` |  |
| `DELETE` | `/api/developer/feature-flags/:id` | Archiva feature flag | admin, coordinator, director, super_admin | param id | { featureFlag } | `backend/src/routes/developer.routes.ts` | Soft-delete: marca deleted_at. |
| `GET` | `/api/developer/system-checks` | Lista checks de sistema | admin, coordinator, director, super_admin | query opcional: status, severity | DeveloperSystemCheck[] | `backend/src/routes/developer.routes.ts` |  |
| `POST` | `/api/developer/system-checks` | Crea check de sistema | admin, coordinator, director, super_admin | { checkKey, title, checkType?, target?, severity? } | { systemCheck } | `backend/src/routes/developer.routes.ts` |  |
| `PATCH` | `/api/developer/system-checks/:id` | Actualiza check de sistema | admin, coordinator, director, super_admin | campos parciales del check | { systemCheck } | `backend/src/routes/developer.routes.ts` |  |
| `DELETE` | `/api/developer/system-checks/:id` | Archiva check de sistema | admin, coordinator, director, super_admin | param id | { systemCheck } | `backend/src/routes/developer.routes.ts` | Soft-delete: marca deleted_at. |
