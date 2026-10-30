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
/** Objeto abierto: las propiedades listadas están tipadas y puede traer más (filas de BD con columnas extra). */
const open = (props: Record<string, Schema>, optional: string[] = []): Schema => ({ ...obj(props, optional), additionalProperties: true });
/** Copia de un objeto cerrado con propiedades obligatorias adicionales. */
const extend = (base: Schema, props: Record<string, Schema>): Schema => {
  const b = base as { properties: Record<string, Schema>; required: string[] };
  return { ...b, properties: { ...b.properties, ...props }, required: [...new Set([...b.required, ...Object.keys(props)])] };
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
const feedTask = extend(task, {
  dueAt: nullable(str),
  kind: enumOf("homework", "exam", "project", "quiz", "presentation"),
  teacherName: nullable(str), attachments: arr(attachment),
  progress: nullable(obj({ status: nullable(enumOf("submitted", "late", "graded")), score: nullable(num) })),
});
const paymentSummary = obj({ currencyCode: str, collectedThisMonth: num, expectedThisMonth: num,
  overdueAmount: num, overdueCount: int, pendingAmount: num, chargesByStatus: byStatus });

const charge = obj({
  id: str, studentId: str, studentName: str, conceptId: nullable(str), conceptName: str, description: str,
  amount: num, discount: num, lateFee: num, total: num, paid: num, balance: num, dueAt: nullable(str),
  status: enumOf("pending", "partial", "overdue", "paid", "cancelled"), storedStatus: str, currencyCode: str,
});

const schedule = obj({
  id: str, kind: enumOf("class", "break"), weekdayId: int, weekdayIndex: int, startTime: str, endTime: str,
  classId: nullable(str), subject: str, groupId: nullable(str), groupName: nullable(str),
  teacher: nullable(str), teacherId: nullable(str), room: nullable(str), shift: nullable(str),
});

const submissionView = obj({
  id: str, assignmentId: str, studentId: int, studentName: str, status: enumOf("submitted", "late", "graded"),
  submittedAt: nullable(str), studentNotes: nullable(str), attachments: arr(attachment), score: nullable(num), feedback: nullable(str),
});
const okOnly = obj({ ok: bool });
const fileRef = obj({ id: idish });

export const responseSchemas: Record<string, Schema> = {
  'GET /api/assignments/submissions/:submissionId/originality': obj({
    documents: arr(obj({
      id: int, state: enumOf('queued','processing','completed','failed','insufficient_text','unsupported_format'),
      name: str, submittedAt: str, processedAt: nullable(str), algorithmVersion: str, errorCode: nullable(str),
      preliminary: bool, compared: bool,
      topMatch: nullable(obj({ coverage: num, sourceId: int, sourceName: str, sourceStudent: str, sourceSubmittedAt: str,
        binaryIdentical: bool, textIdentical: bool, fragments: nullable(arr(obj({text:str,start:int,end:int}))), sourceFragments: nullable(arr(obj({text:str,start:int,end:int}))) })),
    })), notice: str,
  }),
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
    students: arr(obj({ studentId: str, name: str, statusId: nullable(str), notes: str, attendanceId:nullable(str),uuid:nullable(str),version:int,recordedAt:nullable(str) })),
  }),
  "POST /api/attendance/class/:classId": obj({ sessionId:nullable(str), saved:int,conflicts:int,records:arr(row) }),
  "POST /api/sync/attendance/batch": obj({sessions:arr(obj({classId:str,date:str,id:str})),records:arr(row)}),
  "GET /api/sync/changes": obj({serverTime:str,changes:obj({items:arr(row),hasMore:bool,nextCursor:str}),conflictPolicy:str,scope:str}),

  "GET /api/assignments/teacher": obj({ assignments: arr(feedTask), nextCursor: nullable(str) }),
  "GET /api/assignments/student": obj({ assignments: arr(feedTask), nextCursor: nullable(str) }),
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

  // ───────── Notas ─────────
  "GET /api/grades/periods": obj({
    periods: arr(obj({ id: str, name: str, startDate: nullable(str), endDate: nullable(str), weight: num, closed: bool })),
  }),
  "GET /api/grades/scales/default": obj({
    scale: nullable(open({
      id: idish, name: str, scale_type: str, min_value: num, max_value: num, pass_value: num, decimals: int,
      grading_scale_ranges: arr(open({ label: str, range_min: num, range_max: num, passed: bool, color: nullable(str) })),
    }, ["grading_scale_ranges"])),
    status: str,
  }),
  "GET /api/grades/gradebook": obj({
    evaluations: arr(obj({ id: str, classId: str, periodId: str, subjectName: str, title: str, date: nullable(str), maxScore: num, weight: num, kind: str })),
    students: arr(obj({ studentId: str, name: str })),
    grades: rec(rec(nullable(num))),
  }),

  // ───────── Pagos (administración) ─────────
  "GET /api/payments/summary": extend(paymentSummary, { byCurrency: rec(paymentSummary) }),
  "GET /api/payments/concepts": obj({
    concepts: arr(obj({ id: str, name: str, description: nullable(str), baseAmount: num, recurring: bool, currencyCode: str })),
  }),
  "GET /api/payments/charges": obj({ charges: arr(charge) }),
  "GET /api/payments/charges/:chargeId": obj({
    charge,
    payments: arr(obj({ id: str, amount: num, method: str, receiptNumber: str, reference: nullable(str), paidAt: nullable(str) })),
  }),
  "POST /api/payments/charges": obj({ created: int, chargeIds: arr(str) }),

  // ───────── Chat ─────────
  "GET /api/chats/conversations": obj({
    conversations: arr(obj({
      id: str, kind: str, title: str, unreadCount: int, updatedAt: nullable(str),
      participants: arr(obj({ userId: str, name: str, role: str, avatarUrl: nullable(str), isMe: bool })),
      lastMessage: nullable(obj({ id: str, senderId: str, senderName: str, content: nullable(str), hasAttachment: bool, sentAt: str, attachment: nullable(attachment) })),
    })),
    totalUnread: int,
    nextCursor: nullable(obj({ updatedAt: str, id: str })),
  }),
  "GET /api/chats/conversations/:conversationId/messages": obj({
    messages: arr(obj({
      id: str, uuid: str, conversationId: str, senderId: str, senderName: str, sentAt: str, content: nullable(str),
      attachment: nullable(attachment), read: bool,
    })),
    hasMore: bool, nextBeforeId: nullable(str), nextAfterId: nullable(str),
  }),
  "GET /api/chats/contacts": obj({
    contacts: arr(obj({ userId: str, name: str, email: str, role: str, avatarUrl: nullable(str) })),
  }),

  // ───────── Anuncios, alertas y horarios ─────────
  "GET /api/events/announcements": obj({
    announcements: arr(obj({
      id: str, requestId: nullable(str), title: str, content: str, description: str, audience: str, date: str,
      publishedAt: nullable(str), createdBy: nullable(str), groupId: nullable(str),
      delivery: nullable(obj({
        status: enumOf("queued", "processing", "completed", "completed_with_errors", "failed"), phase: nullable(str),
        total: int, processed: int, notified: int, emailed: int, emailFailed: int, emailReview: int, emailSkipped: int, pushFailed: int,
        error: nullable(str), completedAt: nullable(str), updatedAt: nullable(str),
      })),
    })),
    hasMore: bool, nextBeforeId: nullable(str),
  }),
  "GET /api/events/announcements/status": obj({deliveries:arr(obj({announcementId:str,delivery:row}))}),
  "GET /api/notifications": arr(obj({
    id: str, channel: str, title: str, body: str, read: bool, receivedAt: str,
    data: open({ module: str, deepLink: str }, ["module", "deepLink"]),
  })),
  "GET /api/notifications/preferences": obj({ emailEnabled: bool }),
  "GET /api/schedules": obj({ schedules: arr(schedule), pageInfo }),
  "GET /api/schedules/mine": obj({ schedules: arr(schedule) }),

  // ───────── Boletines ─────────
  "GET /api/reports/report-cards": obj({
    pageInfo,
    reportCards: arr(obj({
      id: str, studentId: str, studentName: str, academicPeriodId: nullable(str), periodName: nullable(str), overallAverage: nullable(num),
      status: str, generatedAt: nullable(str), generalNotes: nullable(str),
    })),
  }),
  "GET /api/reports/report-cards/preview": obj({
    student: obj({ id: str, name: str }), academicPeriodId: str, calculation: str, overallAverage: nullable(num), pdfStatus: str,
    lines: arr(obj({
      subjectId: nullable(int), classId: nullable(int), teacherId: nullable(int), subjectName: str, finalScore: nullable(num),
      qualitativeLabel: nullable(str), passed: nullable(bool), notes: nullable(str),
    })),
  }),
  "GET /api/reports/report-cards/:id": obj({ reportCard: open({ id: idish, student_id: idish, academic_period_id: nullable(idish), overall_average: nullable(num), status: str }, []) }),
  "GET /api/portal-access/grades": obj({ grades: arr(row), studentId: int, periodId: nullable(int) }),

  // ───────── Administración (listas) ─────────
  "GET /api/admin/directory": obj({
    pageInfo,
    people: arr(open({
      id: int, institution_id: int, person_id: int, role: str, group_id: nullable(int), class_ids: arr(str), child_ids: arr(str),
      persons: open({ id: int, first_name: str, last_name: str, email: nullable(str), phone: nullable(str) }),
      student_code: str, teacher_code: str, active: bool, is_emergency_contact: bool,
    }, ["student_code", "teacher_code", "active", "is_emergency_contact"])),
    groups: arr(open({ id: int, name: str, max_capacity: nullable(int), active: bool, classroom_id: nullable(int), guide_teacher_id: nullable(int), classrooms: nullable(row) })),
    classes: arr(open({
      id: int, group_id: int, teacher_id: nullable(int), active: bool,
      subjects: open({ name: str }), groups: open({ name: str, classrooms: nullable(row) }),
    })),
  }),
  "GET /api/admin/profiles": obj({
    pageInfo,
    profiles: arr(obj({
      id: str, fullName: str, email: str, phone: nullable(str), username: nullable(str), active: bool, roleCode: str,
      customized: bool, permissions: arr(str),
    })),
  }),
  "GET /api/admin/permissions/catalog": obj({
    modules: arr(obj({ key: str, label: str, actions: arr(str) })), roles: arr(str), mine: arr(str),
  }),
  "GET /api/admin/institutions": paged(open({ id: int, code: str, name: str, commercial_name: nullable(str), subdomain: nullable(str), email: nullable(str), phone: nullable(str), timezone: nullable(str), active: bool })),
  "GET /api/admin/roles": paged(open({ id: int, institution_id: nullable(int), name: str, code: str, description: nullable(str), is_system: bool, active: bool })),
  "GET /api/admin/users": paged(open({
    id: int, institution_id: int, email: str, full_name: str, active: bool, last_sign_in: nullable(str),
    user_roles: arr(open({ roles: open({ id: int, code: str, name: str }) })),
  })),
  "GET /api/admin/directory/options": obj({items: arr(obj({id: str, label: str, subtitle: nullable(str), groupId: nullable(str), teacherId: nullable(str), room: nullable(str)})), selected: arr(obj({id: str, label: str})), pageInfo}),
  "GET /api/admin/directory/people": paged(open({id: int,role: str,active: bool,group_id: nullable(int),group_name: nullable(str),class_ids: arr(str),child_ids: arr(str),classes: arr(row),children: arr(row),persons:open({id:int,first_name:str,last_name:str,email:nullable(str),phone:nullable(str)})})),
  "GET /api/admin/directory/counts": obj({counts: rec(int)}),
  "GET /api/admin/students": paged(open({ id: int, person_id: int, student_code: nullable(str), active: bool, persons: open({ first_name: str, last_name: str, email: nullable(str), phone: nullable(str) }) })),
  "GET /api/admin/teachers": paged(open({ id: int, person_id: int, teacher_code: nullable(str), specialty: nullable(str), active: bool, persons: open({ first_name: str, last_name: str, email: nullable(str), phone: nullable(str) }) })),
  "GET /api/admin/parents": paged(open({ id: int, person_id: int, is_emergency_contact: bool, persons: open({ first_name: str, last_name: str, email: nullable(str), phone: nullable(str) }) })),
  "GET /api/files": paged(attachment),

  // ───────── Cuenta y accesos del portal ─────────
  "GET /api/auth/2fa/status": obj({
    enabled: bool, required: bool, method: str, hasAuthenticator: bool, recoveryCodesRemaining: int,
    verifiedAt: nullable(str), emailHint: nullable(str), availableMethods: arr(str),
  }),
  "GET /api/portal-access/me": obj({ staff: bool, students: arr(row), permissions: rec(bool) }),
  "GET /api/portal-access/users/:id/permissions": obj({ userId: int, permissions: rec(bool), overrides: rec(bool) }),
  "GET /api/portal-access/config": obj({
    users: arr(obj({ id: int, name: str, roles: arr(str) })),
    groups: arr(obj({ id: int, name: str })),
    periods: arr(obj({ id: int, name: str })),
    students: arr(obj({ id: int, name: str })),
    permissionRules: arr(row),
    visibilityRules: arr(row),
  }),
  // ───────── Escrituras (respuestas que la web lee) ─────────
  "POST /api/assignments/upsert": obj({
    assignment: obj({
      id: str, classId: int, subjectName: str, groupName: str, title: str, description: nullable(str), instructions: nullable(str),
      assignedAt: str, dueAt: str, kind: str, maxScore: num, allowLate: bool, published: bool, attachments: arr(attachment),
      teacherName: nullable(str), totalStudents: int, submittedCount: int, gradedCount: int,
    }),
  }),
  "DELETE /api/assignments/:id": okOnly,
  "PATCH /api/assignments/:id/publish": okOnly,
  "PATCH /api/assignments/submissions/:submissionId/grade": obj({ submission: submissionView }),
  "POST /api/assignments/submit": obj({ submission: submissionView }),
  "POST /api/grades/set-grade": okOnly,
  "POST /api/chats/individual": obj({ conversationId: str }),
  "PATCH /api/chats/conversations/:conversationId/read": obj({ ok: bool, conversationId: str, readAt: str }),

};

/**
 * Esquemas de los CUERPOS de petición de las escrituras que usa la web (misma clave «MÉTODO ruta»).
 * Son estrictos con los nombres de campo (para atrapar errores de escritura) pero aceptan ids como texto o número.
 */
responseSchemas['POST /api/assignments/submissions/:submissionId/originality/retry'] =
  responseSchemas['GET /api/assignments/submissions/:submissionId/originality'];

export const requestSchemas: Record<string, Schema> = {
  'POST /api/assignments/submissions/:submissionId/originality/retry': obj({}),
  "POST /api/assignments/upsert": obj({
    assignmentId: idish, classId: idish, title: str, description: str, instructions: str, dueAt: str, maxScore: num,
    kind: enumOf("homework", "exam", "project", "quiz", "presentation"),
    allowLate: bool, published: bool, attachments: arr(fileRef), idempotencyKey: str,
  }, ["assignmentId", "description", "instructions", "allowLate", "published", "attachments", "kind", "idempotencyKey"]),
  "PATCH /api/assignments/:id/publish": obj({ published: bool }),
  "PATCH /api/assignments/submissions/:submissionId/grade": obj({ score: num, feedback: str }, ["feedback"]),
  "POST /api/assignments/submit": obj({ assignmentId: idish, studentId: idish, notes: { ...str, maxLength: 50000 }, attachments: { ...arr(fileRef), maxItems: 20 } }, ["studentId", "notes", "attachments"]),
  "POST /api/grades/set-grade": obj({ evaluationId: idish, studentId: idish, rawScore: num, notes: str }, ["notes"]),
  "POST /api/attendance/class/:classId": obj({
    date: str, marks: arr(obj({operationId:str,uuid:str,expectedVersion:int, studentId: idish, statusId: idish, notes: str,recordedAt:str }, ["notes"])),
  }, ["date"]),
  "POST /api/events": obj({ title: str, description: str, date: str, audience: str, requestId: str }, ["requestId"]),
  "POST /api/reports/report-cards": obj({ requestId:str,studentId: idish, academicPeriodId: idish, generalNotes: str }, ["requestId","generalNotes"]),
  "POST /api/payments/charges": obj({
    requestId:str,conceptId: idish, studentIds: arr(idish), groupId: idish, amount: num, discount: num, dueAt: str, description: str,
  }, ["requestId","studentIds", "groupId", "amount", "discount", "description"]),
  "POST /api/payments/charges/:chargeId/payments": obj({
    method: enumOf("cash", "transfer", "card", "wallet"), amount: num, reference: str, idempotencyKey: str,
  }, ["reference", "idempotencyKey"]),
  "POST /api/chats/messages": obj({ requestId:{type:"string",format:"uuid"},conversationId: idish, content: str, attachment: fileRef }, ["content", "attachment"]),
  "POST /api/chats/individual": obj({ otherUserId: idish }),
  "PATCH /api/notifications/preferences": obj({ emailEnabled: bool }, ["emailEnabled"]),
  "POST /api/schedules": obj({
    kind: enumOf("class", "break"), classId: idish, groupId: idish, label: str, room: str, weekdayIds: arr(int),
    startTime: str, endTime: str, shift: str,
  }, ["classId", "groupId", "label", "room", "shift"]),
  "PATCH /api/schedules/:id": obj({
    kind: enumOf("class", "break"), classId: idish, groupId: idish, label: str, room: str, weekdayId: int,
    startTime: str, endTime: str, shift: str,
  }, ["kind", "classId", "groupId", "label", "room", "weekdayId", "startTime", "endTime", "shift"]),
  "POST /api/files/prepare-upload": obj({ originalName: str, mimeType: str, sizeBytes: num, folder: str }, ["folder"]),
  "POST /api/files/metadata": obj({ originalName: str, storagePath: str, mimeType: str, sizeBytes: num, url: nullable(str) }, ["url"]),
  "POST /api/admin/groups": obj({ name: str, room: str, maxCapacity: num, guideTeacherId: nullable(idish) }, ["room", "maxCapacity", "guideTeacherId"]),
  "PATCH /api/admin/groups/:id": obj({ name: str, room: str, maxCapacity: num, guideTeacherId: nullable(idish) }, ["name", "room", "maxCapacity", "guideTeacherId"]),
  "POST /api/admin/classes": obj({ subject: str, groupId: idish, teacherId: nullable(idish), room: str }, ["teacherId", "room"]),
  "PATCH /api/admin/classes/:id": obj({ subject: str, groupId: idish, teacherId: nullable(idish), room: str }, ["subject", "groupId", "teacherId", "room"]),
  "POST /api/admin/profiles": obj({
    requestId: {type:"string",format:"uuid"},
    fullName: str, email: str, password: str, roleCode: enumOf("admin", "coordinator", "director"), permissions: arr(str),
    phone: str, username: str, active: bool,
  }, ["phone", "username", "active"]),
  "PATCH /api/admin/profiles/:id": obj({
    roleCode: enumOf("admin", "coordinator", "director"), permissions: arr(str), fullName: str, phone: str, active: bool,
  }, ["roleCode", "permissions", "fullName", "phone", "active"]),
  "POST /api/admin/teachers": obj({
    requestId: {type:"string",format:"uuid"},
    firstName: str, lastName: str, phone: str, active: bool, email: str, password: str, username: str, teacherCode: str, classIds: arr(idish),
  }, ["phone", "active", "username", "teacherCode", "classIds"]),
  "PATCH /api/admin/teachers/:id": obj({ firstName: str, lastName: str, phone: str, active: bool, classIds: arr(idish) }, ["firstName", "lastName", "phone", "active", "classIds"]),
  "POST /api/admin/students": obj({
    requestId: {type:"string",format:"uuid"},
    firstName: str, lastName: str, phone: str, active: bool, email: str, password: str, username: str, studentCode: str, groupId: nullable(idish), classIds: arr(idish),
  }, ["phone", "active", "username", "studentCode", "groupId", "classIds"]),
  "PATCH /api/admin/students/:id": obj({ firstName: str, lastName: str, phone: str, active: bool, groupId: nullable(idish), classIds: arr(idish) }, ["firstName", "lastName", "phone", "active", "groupId", "classIds"]),
  "POST /api/admin/parents": obj({
    requestId: {type:"string",format:"uuid"},
    firstName: str, lastName: str, phone: str, active: bool, email: str, password: str, username: str, childIds: arr(idish), isEmergencyContact: bool,
  }, ["phone", "active", "username", "childIds", "isEmergencyContact"]),
  "PATCH /api/admin/parents/:id": obj({ firstName: str, lastName: str, phone: str, active: bool, childIds: arr(idish) }, ["firstName", "lastName", "phone", "active", "childIds"]),
  "POST /api/auth/change-password": obj({ currentPassword: str, newPassword: str }),
  "POST /api/auth/2fa/setup": obj({ method: enumOf("totp", "email") }),
  "POST /api/auth/2fa/enable": obj({ code: str, challengeId: str }, ["challengeId"]),
  "POST /api/auth/2fa/disable": obj({ code: str, recoveryCode: str, challengeId: str }, ["code", "recoveryCode", "challengeId"]),
};
