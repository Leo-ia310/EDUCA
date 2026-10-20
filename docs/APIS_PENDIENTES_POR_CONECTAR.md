# APIs Pendientes Por Conectar

> Archivo generado automaticamente. No editar a mano.
> Fuente: `backend/src/lib/api-manifest.ts`.
> Para actualizar: `cd backend && npm run docs:apis`.

Estas APIs ya estan preparadas en el backend, pero todavia no tienen interfaz Flutter conectada.

## Regla Para Futuras Modificaciones

Cuando se agregue, quite o cambie una API, actualiza `backend/src/lib/api-manifest.ts` y ejecuta `npm run docs:apis`. El comando `npm run build` tambien regenera este archivo antes de compilar.

## Resumen

- Total pendiente de conectar: 7
- Modulos con trabajo pendiente: 3

## Grades

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/grades/periods` | Periodos del anio academico actual | admin con reports.view, maestro, padre y alumno | sin parametros; institucion de la sesion | { ok: true, data: { periods: [{ id, name, startDate, endDate, weight, closed }] } } | `backend/src/modules/grades/grades.routes.ts` | Lo usa el panel web para filtrar el libro de calificaciones. |

## Payments

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/payments/concepts` | Conceptos de cobro activos | admin, coordinator, director, super_admin con payments.view | sin parametros | { ok: true, data: { concepts: [{ id, name, description, baseAmount, recurring, currencyCode }] } } | `backend/src/modules/payments/payments.routes.ts` | Para crear cargos desde el panel web. |
| `GET` | `/api/payments/charges` | Lista cargos con alumno, pagado y saldo | admin, coordinator, director, super_admin con payments.view | query: status?, studentId?, groupId? | { ok: true, data: { charges: [{ id, studentId, studentName, conceptName, description, total, paid, balance, dueAt, status, storedStatus, currencyCode }] } } | `backend/src/modules/payments/payments.routes.ts` | status incluye overdue (derivado: abierto y vencido en la zona institucional). Cargos recorridos por páginas ordenadas; lo pagado se agrega en SQL por los cargos solicitados. |
| `GET` | `/api/payments/charges/:chargeId` | Detalle de un cargo con su historial de pagos | admin, coordinator, director, super_admin con payments.view | param chargeId | { ok: true, data: { charge, payments: [{ id, amount, method, receiptNumber, reference, paidAt }] } } | `backend/src/modules/payments/payments.routes.ts` | Solo pagos con estado paid. |
| `POST` | `/api/payments/charges` | Crea cargos para varios alumnos o un salon | admin con payments.create | { requestId?: UUID, conceptId, studentIds?, groupId?, amount?, discount?, dueAt, description? } | { ok: true, data: { created, chargeIds } } | `backend/src/modules/payments/payments.routes.ts` | 0049: alta masiva transaccional con validación SQL e IDs completos, incluso más de 1000. requestId UUID conserva los IDs en reintentos; no depende del límite de PostgREST. amount por defecto = monto base del concepto. total = amount - discount. Estado inicial pending. |
| `POST` | `/api/payments/charges/:chargeId/payments` | Registra un pago recibido por la administracion (p. ej. caja) | admin con payments.create | { method: cash\|transfer\|card\|wallet, amount, reference?, idempotencyKey? } | { ok: true, data: { payment } } | `backend/src/modules/payments/payments.routes.ts` | Misma logica que /register (padre): valida saldo, genera recibo y actualiza el estado del cargo. |

## Reports

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/reports/report-cards` | Lista boletines emitidos (el mas reciente por alumno y periodo) | admin con reports.view; padre y alumno solo de un hijo vinculado (studentId obligatorio) | query: academicPeriodId?, groupId?, studentId?, page?, pageSize? (50 por defecto, máximo 100) | { ok: true, data: { reportCards: [{ id, studentId, studentName, academicPeriodId, periodName, overallAverage, status, generatedAt, generalNotes }], pageInfo } } | `backend/src/modules/reports/reports.routes.ts` | RPC 0037: DISTINCT ON en SQL antes de paginar, sin descargar historial para deduplicar. groupId usa matrícula ACT y alumnos activos del año actual. Padre/alumno solo del propio alumno o hijo vinculado; se excluyen periodos con notas ocultas. academicPeriodId es null para un boletín anual. |
