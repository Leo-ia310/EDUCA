# APIs Pendientes Por Conectar

> Archivo generado automaticamente. No editar a mano.
> Fuente: `backend/src/lib/api-manifest.ts`.
> Para actualizar: `cd backend && npm run docs:apis`.

Estas APIs ya estan preparadas en el backend, pero todavia no tienen interfaz Flutter conectada.

## Regla Para Futuras Modificaciones

Cuando se agregue, quite o cambie una API, actualiza `backend/src/lib/api-manifest.ts` y ejecuta `npm run docs:apis`. El comando `npm run build` tambien regenera este archivo antes de compilar.

## Resumen

- Total pendiente de conectar: 3
- Modulos con trabajo pendiente: 2

## Grades

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/grades/periods` | Periodos del anio academico actual | admin con reports.view, maestro | sin parametros; institucion de la sesion | { ok: true, data: { periods: [{ id, name, startDate, endDate, weight, closed }] } } | `backend/src/modules/grades/grades.routes.ts` | Lo usa el panel web para filtrar el libro de calificaciones. |
| `GET` | `/api/grades/gradebook` | Libro de calificaciones de una clase en un periodo (solo lectura) | admin con reports.view, maestro de la clase o colaborador con class.view | ?classId=&periodId= | { ok: true, data: { evaluations: [{ id, title, date, maxScore, weight, kind }], students: [{ studentId, name }], grades: { [studentId]: { [evaluationId]: number \| null } } } } | `backend/src/modules/grades/grades.routes.ts` | Notas crudas; el promedio ponderado y la etiqueta se calculan con la escala (GET /api/grades/scales/default). Las notas se registran con grades.setGrade (solo maestro). |

## Reports

| Metodo | Ruta | Resumen | Auth | Request | Response | Fuente | Notas |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `GET` | `/api/reports/report-cards` | Lista boletines emitidos (el mas reciente por alumno y periodo) | admin, coordinator, director, super_admin con reports.view | query: academicPeriodId?, groupId?, studentId? | { ok: true, data: { reportCards: [{ id, studentId, studentName, academicPeriodId, periodName, overallAverage, status, generatedAt, generalNotes }] } } | `backend/src/modules/reports/reports.routes.ts` | Lo usa el panel web. groupId filtra por alumnos activos inscritos en el salon. |
