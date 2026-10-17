/**
 * Esquemas JSON (tipados) de las respuestas de las APIs que consume el panel web.
 *
 * `scripts/generate-openapi.ts` los incluye en `docs/openapi.json` (bajo `ok: true, data: <esquema>`) y el
 * repo de la web genera de ahí sus tipos TypeScript (`npm run types`): si cambia un campo aquí, el compilador
 * de la web marca dónde se usa. La clave es «MÉTODO ruta» tal cual está en `api-manifest.ts`.
 * Los endpoints sin esquema siguen documentados con el texto libre del manifiesto.
 */
type Schema = Record<string, unknown>;

const str: Schema = { type: "string" };
const num: Schema = { type: "number" };
const int: Schema = { type: "integer" };
const bool: Schema = { type: "boolean" };
/** Los ids llegan como texto o número según el endpoint heredado. */
const idish: Schema = { anyOf: [{ type: "string" }, { type: "number" }] };
const nullable = (s: Schema): Schema => ({ anyOf: [s, { type: "null" }] });
const arr = (items: Schema): Schema => ({ type: "array", items });
const enumOf = (...values: string[]): Schema => ({ type: "string", enum: values });
const rec = (values: Schema): Schema => ({ type: "object", additionalProperties: values });
/** Objeto cerrado: todas las propiedades son obligatorias salvo las de `optional`. */
const obj = (props: Record<string, Schema>, optional: string[] = []): Schema => ({
  type: "object",
  properties: props,
  required: Object.keys(props).filter((key) => !optional.includes(key)),
  additionalProperties: false,
});
/** Copia de un objeto cerrado con propiedades obligatorias adicionales. */
const extend = (base: Schema, props: Record<string, Schema>): Schema => {
  const b = base as { properties: Record<string, Schema>; required: string[] };
  return { ...b, properties: { ...b.properties, ...props }, required: [...b.required, ...Object.keys(props)] };
};
/** Fila de base de datos devuelta tal cual (columnas en snake_case, sin esquema fino). */
const row: Schema = { type: "object", additionalProperties: true };

const byStatus = rec(int);
const attendanceStatus = obj({ id: str, name: str, code: str, countsAsAbsent: bool, color: str });
const rate = nullable(num);
const attachment = obj({ id: str, name: str, url: str, sizeBytes: nullable(num), mimeType: nullable(str) });
const pageInfo = obj({ page: int, pageSize: int, total: int, totalPages: int, hasNextPage: bool, hasPreviousPage: bool });
const paged = (item: Schema) => obj({ items: arr(item), pageInfo });

const task = obj({
  id: str, classId: str, subjectName: str, groupName: str, title: str,
  description: nullable(str), instructions: nullable(str), assignedAt: str, dueAt: str,
  maxScore: num, allowLate: bool, published: bool, totalStudents: int, submittedCount: int, gradedCount: int,
});

const charge = obj({
  id: str, studentId: str, studentName: str, conceptId: nullable(str), conceptName: str, description: str,
  amount: num, discount: num, lateFee: num, total: num, paid: num, balance: num, dueAt: nullable(str),
  status: enumOf("pending", "partial", "overdue", "paid", "cancelled"), storedStatus: str, currencyCode: str,
});

export const responseSchemas: Record<string, Schema> = {
  "GET /api/attendance/summary": obj({
    from: str, to: str, statuses: arr(attendanceStatus),
    groups: arr(obj({ groupId: str, name: str, sessions: int, marks: int, absent: int, rate, byStatus })),
    total: obj({ sessions: int, marks: int, absent: int, rate, byStatus }),
  }),
  "GET /api/attendance/groups/:groupId": obj({
    from: str, to: str, group: obj({ id: str, name: str }), statuses: arr(attendanceStatus),
    sessions: arr(obj({ id: str, date: str, classId: str, subject: str, topic: nullable(str), marks: int, absent: int, rate, byStatus })),
    students: arr(obj({ studentId: str, name: str, marks: int, absent: int, rate, byStatus })),
  }),
  "GET /api/attendance/class/:classId": obj({
    class: obj({ id: str, subject: str, group: str }), date: str, sessionId: nullable(str), statuses: arr(attendanceStatus),
    students: arr(obj({ studentId: str, name: str, statusId: nullable(str), notes: str })),
  }),
  "POST /api/attendance/class/:classId": obj({ sessionId: str, saved: int }),

  "GET /api/assignments/teacher": obj({ assignments: arr(task) }),
  "GET /api/assignments/:id/submissions": obj({
    assignment: extend(task, { attachments: arr(attachment) }),
    students: arr(obj({
      studentId: str, name: str, submissionId: nullable(str), status: enumOf("pending", "submitted", "late", "graded"),
      submittedAt: nullable(str), notes: nullable(str), attachments: arr(attachment), score: nullable(num), feedback: nullable(str),
    })),
  }),
  "DELETE /api/assignments/:id/attachments/:fileId": obj({ ok: bool, attachments: arr(attachment) }),

  "GET /api/family/children": obj({ children: arr(obj({ studentId: str, name: str, groupId: nullable(str), groupName: nullable(str) })) }),
  "GET /api/family/attendance": obj({
    studentId: str, from: str, to: str, statuses: arr(attendanceStatus),
    records: arr(obj({ id: str, date: str, subject: str, statusId: str, notes: nullable(str) })),
    summary: obj({ marks: int, absent: int, rate, byStatus }),
  }),
  "GET /api/family/assignments": obj({
    studentId: str,
    assignments: arr(obj({
      id: str, title: str, description: nullable(str), instructions: nullable(str), subjectName: str, dueAt: str,
      maxScore: num, allowLate: bool, status: enumOf("pending", "overdue", "submitted", "late", "graded"),
      submittedAt: nullable(str), attachments: arr(attachment), submissionAttachments: arr(attachment),
      score: nullable(num), feedback: nullable(str),
    })),
  }),
  "GET /api/payments/mine": obj({ charges: arr(charge) }),

  "GET /api/files/:id/download-url": obj({ url: str, name: str, mimeType: nullable(str), expiresInSeconds: int }),

  "GET /api/collaborations": obj({
    classes: arr(obj({ classId: idish, groupId: idish, subjectName: str, groupName: str, isOwner: bool, permissions: arr(str) }, [])),
    invitations: arr(row),
    teachers: arr(obj({ userId: idish, name: str })),
  }),

  "GET /api/developer/summary": obj({
    counts: obj({ institutions: int, users: int, modules: int, pendingApis: int, openTasks: int, featureFlags: int, failingChecks: int }),
    pendingTasks: arr(row),
    recentAuditEvents: arr(row),
  }),
  "GET /api/developer/institutions": paged(row),
  "GET /api/developer/users": paged(row),
  "GET /api/developer/audit-events": paged(row),
  "GET /api/developer/modules": paged(row),
  "GET /api/developer/apis": paged(row),
  "GET /api/developer/tasks": paged(row),
  "GET /api/developer/feature-flags": paged(row),
  "GET /api/developer/system-checks": paged(row),
};
