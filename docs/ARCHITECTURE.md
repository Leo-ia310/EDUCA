# Arquitectura Oficial del Repositorio - Nivra

Este documento define las reglas oficiales de arquitectura para el repositorio de Nivra. Su objetivo es mantener el backend y el frontend ordenados, seguros, escalables y fáciles de mantener mientras la plataforma crece como SaaS escolar multi-institución.

Este documento no cambia código, rutas, contratos API, migraciones, RLS, funciones de Supabase ni comportamiento de la aplicación. Sirve como guía obligatoria para cambios futuros.

---

## 1. Arquitectura Actual

El backend actualmente está en una arquitectura híbrida en transición. Los dominios principales ya viven dentro de `backend/src/modules`, mientras `middleware`, `lib`, `types`, `validators` y servicios compartidos permanecen como infraestructura común:

```text
backend/src/
  services/
    permissions.service.ts
  modules/
    admin/
    assignments/
    attendance/
    auth/
    business-api/
    chats/
    developer/
    events/
    files/
    grades/
    notifications/
    payments/
    reports/
    sync/
  middleware/
  lib/
  types/
  validators/
```

La separación actual ya tiene una base útil:

- Cada carpeta de `modules` agrupa sus `routes`, `controller`, `service` y `repository`.
- Los `routes` de cada módulo definen rutas Express y middlewares.
- Los `controllers` de cada módulo reciben requests y llaman services.
- Los `services` de cada módulo contienen reglas de negocio.
- Los `repositories` de cada módulo concentran el acceso a Supabase/base de datos.
- `services/permissions.service.ts` queda como servicio compartido de autorización de dominio.
- `middleware` maneja autenticación, permisos, errores, seguridad y request id.
- `lib` contiene utilidades de infraestructura como Supabase, paginación, errores y documentación API.
- `validators` contiene validadores comunes reutilizables.

Los módulos actuales de backend son:

```text
auth
admin
assignments
attendance
business-api
chats
developer
events
files
grades
notifications
payments
reports
sync
```

El frontend actualmente está organizado por `core`, `features` y `shared`:

```text
frontend/lib/
  core/
  features/
  shared/
```

Las features actuales son:

```text
admin
assignments
attendance
auth
chat
dashboard
developer
events
grades
notifications
payments
profile
reports
schedule
support
teams
```

La arquitectura actual es funcional, pero todavía no está completamente modularizada por dominio en backend. `developer`, `files`, `reports` y `sync` pueden servir como primer patrón de módulos. Áreas como administración, personas, estructura académica, usuarios, grupos, clases y relaciones familiares siguen demasiado concentradas en archivos grandes.

---

## 2. Arquitectura Objetivo

La arquitectura objetivo debe ser una Clean Architecture pragmática, organizada por dominio, sin sobre-ingeniería.

El objetivo no es mover todo de una vez. El objetivo es que cada cambio nuevo respete límites claros y que los módulos grandes se separen por fases pequeñas.

La dirección recomendada para backend es:

```text
backend/src/
  core/
    config/
    database/
    errors/
    http/
    logging/
    pagination/
    security/
    tenancy/
    validation/

  shared/
    dto/
    mappers/
    types/
    utils/
    testing/

  modules/
    auth/
    identity/
    institutions/
    people/
    academic/
    enrollments/
    attendance/
    assignments/
    grades/
    notifications/
    payments/
    chat/
    files/
    reports/
    sync/
    developer/

  app.ts
  server.ts
```

La dirección recomendada para frontend es mantener `features`, pero estandarizar la organización interna:

```text
frontend/lib/
  core/
  shared/
  features/
    auth/
      domain/
      data/
      application/
      presentation/
    admin/
      domain/
      data/
      application/
      presentation/
    attendance/
    assignments/
    grades/
    notifications/
    payments/
    chat/
    reports/
```

La arquitectura objetivo debe separar:

- Infraestructura común.
- Reglas de negocio.
- Acceso a datos.
- Validación de entrada.
- Contratos API.
- Permisos.
- Presentación/UI.
- Datos demo.

---

## 3. Regla `route → controller → service → repository → database`

Toda API nueva o modificada debe respetar este flujo:

```text
route → controller → service → repository → database
```

### Route

Responsabilidades:

- Definir método HTTP y path.
- Aplicar middlewares de autenticación, permisos generales, rate limit o seguridad.
- Llamar al controller correspondiente.

No debe contener:

- Lógica de negocio.
- Validación compleja de payload.
- Consultas de base de datos.
- Transformaciones de dominio.

### Controller

Responsabilidades:

- Leer `req.params`, `req.query` y `req.body`.
- Validar o delegar validación a DTO/schema.
- Obtener el contexto autenticado cuando aplique.
- Llamar al service.
- Responder HTTP.

No debe contener:

- Reglas de negocio.
- Consultas a base de datos.
- Decisiones de permisos complejas.
- Lógica multi-tenant manual repetida.

### Service

Responsabilidades:

- Contener reglas de negocio.
- Orquestar casos de uso.
- Aplicar reglas de roles, permisos e institución.
- Validar relaciones de dominio.
- Llamar repositories.
- Decidir errores de negocio.

No debe contener:

- SQL crudo o consultas Supabase directas, salvo excepción temporal justificada.
- Lógica de presentación.
- Datos demo.

### Repository

Responsabilidades:

- Ser la única capa que habla con base de datos o Supabase para datos persistentes.
- Aplicar filtros de consulta.
- Encapsular selects, inserts, updates, deletes, upserts y RPCs.
- Devolver datos crudos o estructuras mínimas para que el service las transforme.

No debe contener:

- Reglas de negocio complejas.
- Decisiones de UI.
- Lectura directa de request HTTP.
- Lógica de roles que pertenezca al service o policy.

### Database

Responsabilidades:

- Persistencia.
- Constraints.
- Índices.
- RLS cuando aplique.
- Integridad referencial.

La base de datos debe reforzar seguridad, pero el backend también debe validar permisos e `institution_id`. No se debe depender de una sola capa para seguridad multi-tenant.

---

## 4. Reglas para DTO/Schema

Todo endpoint nuevo debe tener DTO/schema formal.

La meta es que cada endpoint tenga un contrato claro para:

- Params.
- Query string.
- Body.
- Response, cuando aplique.

Reglas:

1. No crear endpoints nuevos usando solo `asRecord(req.body)` sin schema dedicado.
2. No validar payloads complejos directamente en controllers.
3. Los schemas deben vivir cerca del módulo o en una carpeta clara de schemas.
4. Los nombres deben ser explícitos.
5. Un schema debe validar tipos, requeridos, límites, enums y formatos.
6. Los services pueden conservar validaciones de negocio, pero no deben reemplazar la validación estructural del request.
7. Los errores de validación deben ser consistentes.
8. Los DTO/schema deben reflejarse en la documentación API.
9. Si un endpoint acepta camelCase y snake_case por compatibilidad, debe documentarlo explícitamente.
10. No cambiar contratos existentes sin aprobación.

Ejemplo de estructura futura:

```text
backend/src/modules/files/
  files.routes.ts
  files.controller.ts
  files.service.ts
  files.repository.ts
  files.schemas.ts
  files.types.ts
```

Los módulos migrados deben mantener sus schemas dentro de su carpeta de módulo. Mientras convivan módulos migrados y módulos legacy por capas, no se deben crear nuevos schemas compartidos sin una razón clara de reutilización.

---

## 5. Reglas de `institution_id` y Multi-Tenant

Nivra es una plataforma SaaS multi-institución. La separación por institución es una regla crítica de seguridad.

Reglas obligatorias:

1. Todo dato escolar debe pertenecer a una institución cuando el modelo lo requiera.
2. Toda query sobre datos institucionales debe filtrar por `institution_id` o validar alcance equivalente.
3. El `institution_id` confiable debe salir del contexto autenticado del backend, no de un valor enviado por el cliente sin validar.
4. Solo `super_admin` puede operar sobre otra institución, y debe hacerlo de forma explícita y auditada.
5. Un admin institucional no puede leer, crear, actualizar ni archivar datos de otra institución.
6. Si una tabla pivote no tiene `institution_id`, el repository o service debe validar pertenencia mediante joins o consultas relacionadas.
7. Las relaciones padre-estudiante deben validar que ambos pertenecen a la misma institución.
8. Las relaciones estudiante-grupo/clase deben validar que estudiante, grupo, clase y año académico pertenecen a la misma institución.
9. Las consultas de archivos deben validar que el archivo pertenece a la institución antes de adjuntarlo o mostrarlo.
10. Las operaciones de chat deben validar institución y participación.
11. Las operaciones de pagos deben validar institución en cargo, pago y estudiante.
12. Las operaciones de reportes deben validar institución y acceso al estudiante.
13. Las operaciones offline/sync deben estar limitadas por institución y usuario.

No se debe confiar únicamente en que una operación previa ya validó la institución si luego se hace una consulta por `id`. Las consultas sensibles deben recibir `institutionId` siempre que sea posible.

Patrón recomendado:

```text
service recibe ctx.institutionId
service valida permiso de negocio
repository recibe institutionId
repository filtra por institution_id
```

---

## 6. Reglas de Roles y Permisos

Los roles y permisos deben ser explícitos, consistentes y fáciles de auditar.

Roles actuales observados:

```text
super_admin
admin
coordinator
director
teacher
student
parent
```

Reglas:

1. Toda ruta privada debe usar autenticación.
2. Toda ruta sensible debe validar rol o permiso.
3. No basta con validar que el usuario está autenticado.
4. Los permisos de negocio deben vivir en services o policies, no en la UI.
5. El frontend puede ocultar pantallas, pero el backend debe proteger la acción real.
6. `super_admin` debe ser tratado distinto de `admin` institucional.
7. `admin`, `coordinator` y `director` deben tener permisos documentados por módulo.
8. `teacher` solo debe modificar clases, tareas, asistencias o notas que le correspondan, salvo permiso administrativo explícito.
9. `student` solo debe operar sobre su propio perfil, entregas, asistencia, calificaciones y datos permitidos.
10. `parent` solo debe operar sobre estudiantes vinculados mediante relación padre-estudiante.
11. Los endpoints de developer deben revisarse con cuidado porque pueden exponer información técnica.
12. Los archivos deben validarse por institución y por acceso contextual cuando aplique.
13. Los reportes deben validar acceso al estudiante y al periodo.
14. Los pagos deben validar acceso al cargo y al estudiante.

Si una función de permisos permite que admin herede permisos de teacher/student/parent, debe estar documentado y testeado. No debe ser un efecto accidental.

---

## 7. Reglas para Mocks y Demo

Los mocks son permitidos, pero deben estar claramente separados del flujo real.

Reglas:

1. Los datos demo solo deben usarse en modo demo.
2. El modo demo debe estar controlado por configuración explícita, por ejemplo `DEMO=true` o falta de credenciales durante desarrollo.
3. En modo conectado, si backend o sesión fallan, la app debe mostrar error real. No debe caer silenciosamente a mocks.
4. Los mocks no deben enviarse al backend.
5. Los mocks no deben mezclarse con repositories reales.
6. Los datos demo deben vivir en archivos claramente marcados como `mock`, `demo`, `fixture` o `seed`.
7. Las pantallas no deben decidir por su cuenta si usan mock o real; esa decisión debe estar centralizada en providers/repositories.
8. Los tests pueden usar fixtures, pero esos fixtures deben estar separados de datos productivos.
9. Los nombres, emails y datos demo no deben confundirse con datos reales.
10. Los mocks no deben ocultar errores de integración.

Áreas que deben mantenerse bajo control:

```text
frontend/lib/features/*/data/mock_*
frontend/lib/features/*/data/*demo*
frontend/lib/features/dashboard/data/mock_dashboard_data.dart
frontend/lib/features/admin/data/school_directory.dart
frontend/lib/features/notifications/data/demo_push_service.dart
```

No se deben eliminar mocks todavía sin aprobación.

---

## 8. Reglas de Compatibilidad con `business-api`

`business-api` es una API legacy de compatibilidad basada en acciones. Su ruta pública se conserva, pero su implementación interna vive como módulo para aislar el contrato y facilitar la migración gradual.

Rutas actuales que deben mantenerse:

```text
POST /api/business-api
POST /functions/v1/business-api
```

Reglas:

1. No eliminar `business-api` todavía.
2. No cambiar su contrato sin aprobación.
3. No cambiar nombres de acciones sin plan de migración.
4. No romper llamadas actuales del frontend que usan `api.call(action, payload)`.
5. No eliminar la Edge Function de Supabase todavía.
6. No mover lógica usada por acciones legacy sin pruebas de compatibilidad.
7. Cualquier endpoint REST nuevo debe poder convivir con `business-api` hasta que el frontend migre.
8. Si se crea una ruta REST equivalente, la acción legacy debe seguir funcionando durante la transición.
9. La deprecación de acciones debe documentarse acción por acción.
10. Antes de eliminar una acción legacy, debe confirmarse que no hay frontend, webhook ni servicio externo usándola.

Patrón recomendado para migración futura:

```text
/api/business-api action actual
  → registry interno de handlers
  → service del módulo nuevo
  → repository del módulo nuevo
```

Así se puede mantener compatibilidad pública mientras la lógica interna se ordena.

---

## 9. Checklist para Crear Endpoints Nuevos

Antes de crear un endpoint nuevo, confirmar:

- [ ] ¿Existe una ruta pública similar que deba mantenerse compatible?
- [ ] ¿El endpoint pertenece a un módulo claro?
- [ ] ¿El nombre de la ruta es consistente con las rutas actuales?
- [ ] ¿Tiene DTO/schema para params, query y body?
- [ ] ¿Tiene response documentado?
- [ ] ¿Requiere autenticación?
- [ ] ¿Requiere rol específico?
- [ ] ¿Requiere permiso de negocio?
- [ ] ¿Requiere validar `institution_id`?
- [ ] ¿El `institution_id` sale del contexto autenticado?
- [ ] ¿El controller se limita a request/response?
- [ ] ¿La lógica de negocio vive en service?
- [ ] ¿El acceso a DB vive en repository?
- [ ] ¿Las listas grandes tienen paginación?
- [ ] ¿Los filtros están documentados?
- [ ] ¿Los errores son consistentes?
- [ ] ¿El endpoint afecta `business-api`?
- [ ] ¿Hay impacto en frontend?
- [ ] ¿Hay impacto en documentación API?
- [ ] ¿Se actualizó `backend/src/lib/api-manifest.ts` si aplica?
- [ ] ¿Se ejecutó `npm run docs:apis` si aplica?
- [ ] ¿Se ejecutó typecheck/test/lint disponible?

---

## 10. Checklist Antes de Tocar Código Sensible

Código sensible incluye:

```text
auth
admin
roles
permissions
institution_id
business-api
Supabase migrations
RLS
payments
grades
reports
files
chat
sync
Android/iOS/builds
```

Antes de tocar código sensible, confirmar:

- [ ] ¿El cambio fue aprobado explícitamente?
- [ ] ¿Está claro qué archivos exactos se modificarán?
- [ ] ¿Está claro qué rutas públicas se mantienen?
- [ ] ¿Está claro si cambia comportamiento o solo organización?
- [ ] ¿Hay plan de rollback?
- [ ] ¿Hay pruebas o comandos de validación definidos?
- [ ] ¿Se revisó impacto multi-tenant?
- [ ] ¿Se revisó impacto de roles/permisos?
- [ ] ¿Se revisó impacto en frontend?
- [ ] ¿Se revisó impacto en documentación?
- [ ] ¿Se revisó impacto en `business-api`?
- [ ] ¿Se evitó tocar migraciones/RLS si no era parte de la aprobación?
- [ ] ¿Se evitó eliminar mocks si no era parte de la aprobación?
- [ ] ¿Se evitó modificar builds móviles si no era parte de la aprobación?

Si cualquiera de estas respuestas es incierta, primero se debe hacer una auditoría escrita antes de cambiar código.

---

## 11. Módulos que No Deben Tocarse Todavía

Hasta nueva aprobación, no deben tocarse estas áreas:

```text
backend/src/modules/business-api/business-api.routes.ts
backend/src/modules/business-api/business-api.controller.ts
backend/src/modules/business-api/business-api.service.ts
backend/src/modules/business-api/business-api.handlers.ts
supabase/functions/business-api/
supabase/migrations/
supabase/schema_all.sql
frontend/android/
frontend/ios/
frontend/windows/
frontend/macos/
frontend/linux/
builds/
```

Tampoco deben tocarse todavía de forma estructural:

```text
frontend/lib/features/admin/
frontend/lib/core/routing/app_router.dart
```

Estas áreas de frontend son importantes, pero tienen alto riesgo de romper flujos existentes. Deben refactorizarse después de tener reglas, schemas, pruebas y migraciones pequeñas ya comprobadas.

---

## 12. Plan Recomendado para Fase 2B

La Fase 2B ya dejó un primer patrón aplicable en un módulo pequeño y de bajo riesgo.

Módulo usado como referencia:

```text
files
```

Razones:

- Tiene pocas rutas.
- Ya está separado en route, controller, service y repository.
- Ya aplica `institution_id` en operaciones importantes.
- No depende de admin, personas, clases, pagos o calificaciones.
- Permite mantener un patrón repetible sin tocar módulos críticos.

Rutas involucradas:

```text
GET /api/files/
POST /api/files/prepare-upload
POST /api/files/metadata
```

Archivos del patrón actual:

```text
backend/src/modules/files/files.routes.ts
backend/src/modules/files/files.controller.ts
backend/src/modules/files/files.service.ts
backend/src/modules/files/files.repository.ts
backend/src/modules/files/files.schemas.ts
backend/src/lib/api-manifest.ts
docs/openapi.json
```

El siguiente paso recomendado debe tomar este patrón y aplicarlo a módulos de bajo riesgo, sin cambiar contratos de `business-api`, migraciones, RLS ni módulos centrales de autenticación.

Reglas para la próxima fase:

1. No cambiar rutas.
2. No cambiar payloads públicos.
3. No cambiar responses públicas.
4. No cambiar rutas, acciones ni payloads de `business-api`.
5. No tocar migraciones.
6. No tocar frontend.
7. No tocar Android/iOS/builds.
8. Mover módulos solo cuando todos sus imports queden resueltos y sus rutas públicas sigan iguales.
9. Mantener validaciones de negocio en service.
10. Actualizar `api-manifest.ts` y regenerar docs cuando cambien rutas, controllers, services, repositories o documentación API.

Comandos de validación recomendados:

```powershell
cd backend
npm run typecheck
npm test
npm run docs:apis
```

Toda migración debe cerrarse con búsqueda de imports obsoletos y revisión explícita de áreas protegidas.
