# APIs Pendientes Por Conectar

> Archivo generado automaticamente. No editar a mano.
> Fuente: `backend/src/lib/api-manifest.ts`.
> Para actualizar: `cd backend && npm run docs:apis`.

Estas APIs ya estan preparadas en el backend, pero todavia no tienen interfaz Flutter conectada.

## Regla Para Futuras Modificaciones

Cuando se agregue, quite o cambie una API, actualiza `backend/src/lib/api-manifest.ts` y ejecuta `npm run docs:apis`. El comando `npm run build` tambien regenera este archivo antes de compilar.

## Resumen

- Total pendiente de conectar: 12
- Modulos con trabajo pendiente: 4

## Chat

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/chats/conversations` | Lista las conversaciones del usuario | usuario autenticado (participante de la conversacion) | sin parametros | { ok: true, data: { conversations: [{ id, kind, title, participants[], lastMessage, unreadCount, updatedAt }] } } | `backend/src/modules/chats/chats.routes.ts` | Panel web (la app las lee directo de Supabase). unreadCount = mensajes ajenos sin registro en message_reads. |
| `GET` | `/api/chats/conversations/:conversationId/messages` | Mensajes de una conversacion | usuario autenticado (participante de la conversacion) | query: limit? (100, max 300) | { ok: true, data: { messages: [{ id, uuid, conversationId, senderId, senderName, sentAt, content, attachment, read }] } } | `backend/src/modules/chats/chats.routes.ts` | Los ultimos N en orden cronologico. read = algun otro participante lo leyo. |
| `GET` | `/api/chats/contacts` | Personas con las que se puede iniciar una conversacion | usuario autenticado (participante de la conversacion) | query: q? (nombre o rol) | { ok: true, data: { contacts: [{ userId, name, email, role, avatarUrl }] } } | `backend/src/modules/chats/chats.routes.ts` | Usuarios activos de la institucion, maximo 40. |

## Grades

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/grades/periods` | Periodos del anio academico actual | admin con reports.view, maestro, padre y alumno | sin parametros; institucion de la sesion | { ok: true, data: { periods: [{ id, name, startDate, endDate, weight, closed }] } } | `backend/src/modules/grades/grades.routes.ts` | Lo usa el panel web para filtrar el libro de calificaciones. |
| `GET` | `/api/grades/gradebook` | Libro de calificaciones de una clase en un periodo (solo lectura) | admin con reports.view, maestro de la clase o colaborador con class.view | ?classId=&periodId= | { ok: true, data: { evaluations: [{ id, title, date, maxScore, weight, kind }], students: [{ studentId, name }], grades: { [studentId]: { [evaluationId]: number \| null } } } } | `backend/src/modules/grades/grades.routes.ts` | Notas crudas; el promedio ponderado y la etiqueta se calculan con la escala (GET /api/grades/scales/default). Las notas se registran con grades.setGrade (solo maestro). |

## Payments

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/payments/summary` | Resumen de recaudacion y mora | admin, coordinator, director, super_admin con payments.view | sin parametros | { ok: true, data: { currencyCode, collectedThisMonth, expectedThisMonth, overdueAmount, overdueCount, pendingAmount, chargesByStatus } } | `backend/src/modules/payments/payments.routes.ts` | Panel web. Mora = cargos abiertos con vencimiento anterior a hoy. |
| `GET` | `/api/payments/concepts` | Conceptos de cobro activos | admin, coordinator, director, super_admin con payments.view | sin parametros | { ok: true, data: { concepts: [{ id, name, description, baseAmount, recurring, currencyCode }] } } | `backend/src/modules/payments/payments.routes.ts` | Para crear cargos desde el panel web. |
| `GET` | `/api/payments/charges` | Lista cargos con alumno, pagado y saldo | admin, coordinator, director, super_admin con payments.view | query: status?, studentId?, groupId? | { ok: true, data: { charges: [{ id, studentId, studentName, conceptName, description, total, paid, balance, dueAt, status, storedStatus, currencyCode }] } } | `backend/src/modules/payments/payments.routes.ts` | status incluye overdue (derivado: abierto y vencido). |
| `GET` | `/api/payments/charges/:chargeId` | Detalle de un cargo con su historial de pagos | admin, coordinator, director, super_admin con payments.view | param chargeId | { ok: true, data: { charge, payments: [{ id, amount, method, receiptNumber, reference, paidAt }] } } | `backend/src/modules/payments/payments.routes.ts` | Solo pagos con estado paid. |
| `POST` | `/api/payments/charges` | Crea cargos para varios alumnos o un salon | admin con payments.create | { conceptId, studentIds?, groupId?, amount?, discount?, dueAt, description? } | { ok: true, data: { created, chargeIds } } | `backend/src/modules/payments/payments.routes.ts` | amount por defecto = monto base del concepto. total = amount - discount. Estado inicial pending. |
| `POST` | `/api/payments/charges/:chargeId/payments` | Registra un pago recibido por la administracion (p. ej. caja) | admin con payments.create | { method: cash\|transfer\|card\|wallet, amount, reference?, idempotencyKey? } | { ok: true, data: { payment } } | `backend/src/modules/payments/payments.routes.ts` | Misma logica que /register (padre): valida saldo, genera recibo y actualiza el estado del cargo. |

## Reports

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/reports/report-cards` | Lista boletines emitidos (el mas reciente por alumno y periodo) | admin con reports.view; padre y alumno solo de un hijo vinculado (studentId obligatorio) | query: academicPeriodId?, groupId?, studentId? | { ok: true, data: { reportCards: [{ id, studentId, studentName, academicPeriodId, periodName, overallAverage, status, generatedAt, generalNotes }] } } | `backend/src/modules/reports/reports.routes.ts` | Lo usa el panel web. groupId filtra por alumnos activos inscritos en el salon. |
