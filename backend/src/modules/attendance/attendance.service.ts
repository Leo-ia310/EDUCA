import { randomUUID } from "node:crypto";
import { assertNoDbError } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import {
  asRecord,
  dateOnly,
  optionalString,
  requiredDate,
  requiredId,
  requiredString,
} from "../../validators/common.validators";
import {
  attendanceRepository,
  AttendanceRepository,
} from "./attendance.repository";
import type { AppContext } from "../../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "../../services/permissions.service";

export class AttendanceService {
  constructor(
    private readonly repository: AttendanceRepository = attendanceRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async upsertClassSession(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const classId = requiredId(payload.classId, "Clase");
    const sessionDate = requiredDate(payload.dateMs, "Fecha de sesión");
    const teacherId = await this.permissions.currentTeacherId(ctx);
    if (teacherId == null) {
      throw new HttpError(
        403,
        "Tu usuario no está enlazado a un docente.",
        "forbidden",
      );
    }
    await this.permissions.assertTeacherCanUseClass(ctx, classId, "attendance.write");
    const date = dateOnly(sessionDate);

    const id = await this.repository.ensureClassSession(classId, date);
    return { id: Number(id) };
  }

  async upsertAttendance(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const uuid = requiredString(payload.uuid, "UUID", 80);
    const classId = requiredId(payload.classId, "Clase");
    const studentId = requiredId(payload.studentId, "Estudiante");
    const statusId = requiredId(payload.statusId, "Estado de asistencia");
    const recordedAt = requiredDate(payload.recordedAtMs, "Fecha de marcado");
    const classSessionId = requiredId(payload.classSessionId, "Sesión de clase");
    await this.permissions.assertTeacherCanUseClass(ctx, classId, "attendance.write");

    const session = await this.repository.findClassSessionById(
      ctx.institutionId,
      classId,
      classSessionId,
    );
    await this.permissions.assertStudentEnrolledInClass(
      ctx.institutionId,
      studentId,
      classId,
      Number(session.group_id),
    );

    const statusExists = await this.repository.attendanceStatusExists(statusId);
    if (!statusExists) {
      throw new HttpError(
        400,
        "Estado de asistencia inválido.",
        "validation_error",
      );
    }

    const dbPayload = {
      uuid,
      institution_id: ctx.institutionId,
      class_session_id: classSessionId,
      student_id: studentId,
      attendance_status_id: statusId,
      recorded_at: recordedAt.toISOString(),
      notes: optionalString(payload.notes, 500),
      recorded_by: ctx.userId,
      source: "app",
      updated_at: new Date().toISOString(),
    };

    const existingByUuid = await this.repository.findAttendanceByUuid(ctx.institutionId, uuid);
    const row = existingByUuid == null
      ? await this.repository.upsertAttendance(dbPayload)
      : await this.repository.updateAttendance(ctx.institutionId, existingByUuid.id, dbPayload);
    return { id: Number(row.id) };
  }

  /** Lista de la clase para una fecha: alumnos activos del salón con la marca ya guardada (si la hay). */
  async classRoster(ctx: AppContext, classIdRaw: unknown, query: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const classId = requiredId(classIdRaw, "Clase");
    const date = singleDate(query.date);
    await this.permissions.assertTeacherCanUseClass(ctx, classId, "attendance.write");
    const cls = await this.repository.classLabel(ctx.institutionId, classId);
    if (!cls) throw new HttpError(404, "Clase no encontrada.", "not_found");

    const [statuses, enrollments, session] = await Promise.all([
      this.repository.statuses(),
      this.repository.enrolledStudents(ctx.institutionId, Number(cls.group_id)),
      this.repository.findSessionOfClassDate(ctx.institutionId, classId, date),
    ]);
    const marks = session ? await this.repository.marksOfSession(ctx.institutionId, Number(session.id)) : [];
    const byStudent = new Map(marks.map((m) => [Number(m.student_id), m]));
    return {
      class: { id: String(classId), subject: String(cls.subjects?.name ?? "Clase"), group: String(cls.groups?.name ?? "Salón") },
      date,
      sessionId: session ? String(session.id) : null,
      statuses: statuses.map(mapStatus),
      students: enrollments
        .map((e: any) => {
          const person = e.students?.persons;
          const name = `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim();
          const mark = byStudent.get(Number(e.student_id));
          return {
            studentId: String(e.student_id),
            name: name || "Estudiante",
            statusId: mark ? String(mark.attendance_status_id) : null,
            notes: mark?.notes ? String(mark.notes) : "",
          };
        })
        .sort((a, b) => a.name.localeCompare(b.name, "es")),
    };
  }

  /** Guarda de una vez la lista de asistencia de la clase en una fecha (crea la sesión si no existe). */
  async saveClassAttendance(ctx: AppContext, classIdRaw: unknown, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const classId = requiredId(classIdRaw, "Clase");
    const date = singleDate(payload.date);
    const marks = Array.isArray(payload.marks) ? payload.marks : [];
    if (marks.length === 0) throw new HttpError(400, "No hay marcas que guardar.", "validation_error");
    if (marks.length > 300) throw new HttpError(400, "Demasiadas marcas en una sola solicitud.", "validation_error");
    if (date > dateOnly(new Date(Date.now() + 86_400_000))) {
      throw new HttpError(400, "No se puede registrar asistencia de una fecha futura.", "validation_error");
    }
    await this.permissions.assertTeacherCanUseClass(ctx, classId, "attendance.write");
    const cls = await this.repository.classLabel(ctx.institutionId, classId);
    if (!cls) throw new HttpError(404, "Clase no encontrada.", "not_found");

    const [statuses, enrollments] = await Promise.all([
      this.repository.statuses(),
      this.repository.enrolledStudents(ctx.institutionId, Number(cls.group_id)),
    ]);
    const validStatus = new Set(statuses.map((s) => Number(s.id)));
    const enrolled = new Set(enrollments.map((e: any) => Number(e.student_id)));

    const clean = new Map<number, { statusId: number; notes: string | null }>();
    for (const raw of marks) {
      const m = asRecord(raw);
      const studentId = requiredId(m.studentId, "Estudiante");
      const statusId = requiredId(m.statusId, "Estado de asistencia");
      if (!validStatus.has(statusId)) throw new HttpError(400, "Estado de asistencia inválido.", "validation_error");
      if (!enrolled.has(studentId)) throw new HttpError(403, "El estudiante no pertenece a esta clase.", "forbidden");
      clean.set(studentId, { statusId, notes: optionalString(m.notes, 500) ?? null });
    }

    const sessionId = Number(await this.repository.ensureClassSession(classId, date));
    const existing = new Map((await this.repository.marksOfSession(ctx.institutionId, sessionId)).map((m) => [Number(m.student_id), m]));
    const now = new Date().toISOString();
    await this.repository.upsertMarks(
      [...clean].map(([studentId, m]) => ({
        uuid: existing.get(studentId)?.uuid ?? randomUUID(),
        institution_id: ctx.institutionId,
        class_session_id: sessionId,
        student_id: studentId,
        attendance_status_id: m.statusId,
        recorded_at: now,
        notes: m.notes,
        recorded_by: ctx.userId,
        source: "web",
        updated_at: now,
      })),
    );
    return { sessionId: String(sessionId), saved: clean.size };
  }

  /** Resumen de asistencia por salón en un rango de fechas (administración con `reports.view`). */
  async summary(ctx: AppContext, query: Record<string, unknown>) {
    this.requireAdminView(ctx);
    const { from, to } = dateRange(query);
    const [statuses, groups, sessions] = await Promise.all([
      this.repository.statuses(),
      this.repository.groupNames(ctx.institutionId),
      this.repository.sessionsInRange(ctx.institutionId, from, to),
    ]);
    const marks = await this.repository.marksOfSessions(ctx.institutionId, sessions.map((s) => Number(s.id)));
    const groupOfSession = new Map(sessions.map((s) => [Number(s.id), Number(s.group_id)]));
    const rows = new Map<number, Tally>();
    for (const s of sessions) {
      const row = rows.get(Number(s.group_id)) ?? { sessions: 0, byStatus: {} };
      row.sessions += 1;
      rows.set(Number(s.group_id), row);
    }
    for (const m of marks) {
      const row = rows.get(groupOfSession.get(Number(m.class_session_id)) ?? -1);
      if (!row) continue;
      const key = String(m.attendance_status_id);
      row.byStatus[key] = (row.byStatus[key] ?? 0) + 1;
    }
    const absentIds = new Set(statuses.filter((s) => s.counts_as_absent).map((s) => String(s.id)));
    const total: Tally = { sessions: 0, byStatus: {} };
    const out = groups
      .map((g) => {
        const r = rows.get(Number(g.id)) ?? { sessions: 0, byStatus: {} };
        total.sessions += r.sessions;
        for (const [k, v] of Object.entries(r.byStatus)) total.byStatus[k] = (total.byStatus[k] ?? 0) + v;
        return { groupId: String(g.id), name: String(g.name ?? "Salón"), sessions: r.sessions, ...stats(r.byStatus, absentIds) };
      })
      .sort((a, b) => a.name.localeCompare(b.name, "es"));
    return { from, to, statuses: statuses.map(mapStatus), groups: out, total: { sessions: total.sessions, ...stats(total.byStatus, absentIds) } };
  }

  /** Detalle de un salón: sesiones del rango y porcentaje de asistencia por alumno. */
  async groupDetail(ctx: AppContext, groupIdRaw: unknown, query: Record<string, unknown>) {
    this.requireAdminView(ctx);
    const groupId = requiredId(groupIdRaw, "Salón");
    const { from, to } = dateRange(query);
    const [statuses, groups, sessions, enrollments] = await Promise.all([
      this.repository.statuses(),
      this.repository.groupNames(ctx.institutionId, groupId),
      this.repository.sessionsInRange(ctx.institutionId, from, to, groupId),
      this.repository.enrolledStudents(ctx.institutionId, groupId),
    ]);
    if (groups.length === 0) throw new HttpError(404, "Salón no encontrado.", "not_found");
    const marks = await this.repository.marksOfSessions(ctx.institutionId, sessions.map((s) => Number(s.id)));
    const absentIds = new Set(statuses.filter((s) => s.counts_as_absent).map((s) => String(s.id)));

    const bySession = new Map<number, Record<string, number>>();
    const byStudent = new Map<number, Record<string, number>>();
    const bump = (map: Map<number, Record<string, number>>, id: number, key: string) => {
      const entry = map.get(id) ?? {};
      entry[key] = (entry[key] ?? 0) + 1;
      map.set(id, entry);
    };
    for (const m of marks) {
      const key = String(m.attendance_status_id);
      bump(bySession, Number(m.class_session_id), key);
      bump(byStudent, Number(m.student_id), key);
    }
    return {
      from,
      to,
      group: { id: String(groupId), name: String(groups[0].name ?? "Salón") },
      statuses: statuses.map(mapStatus),
      sessions: sessions.map((s: any) => ({
        id: String(s.id),
        date: String(s.date).slice(0, 10),
        classId: String(s.class_id),
        subject: String(s.classes?.subjects?.name ?? "Clase"),
        topic: s.topic ?? null,
        ...stats(bySession.get(Number(s.id)) ?? {}, absentIds),
      })),
      students: enrollments
        .map((e: any) => {
          const person = e.students?.persons;
          const name = `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim();
          return { studentId: String(e.student_id), name: name || "Estudiante", ...stats(byStudent.get(Number(e.student_id)) ?? {}, absentIds) };
        })
        .sort((a, b) => a.name.localeCompare(b.name, "es")),
    };
  }

  private requireAdminView(ctx: AppContext) {
    if (!this.permissions.isAdmin(ctx)) {
      throw new HttpError(403, "Solo administración puede consultar la asistencia general.", "forbidden");
    }
    this.permissions.requireAdminPermission(ctx, "reports.view");
  }
}

export const attendanceService = new AttendanceService();

type Tally = { sessions: number; byStatus: Record<string, number> };

function stats(byStatus: Record<string, number>, absentIds: Set<string>) {
  const marks = Object.values(byStatus).reduce((a, b) => a + b, 0);
  const absent = Object.entries(byStatus).filter(([k]) => absentIds.has(k)).reduce((a, [, v]) => a + v, 0);
  return { marks, absent, rate: marks ? (marks - absent) / marks : null, byStatus };
}

function mapStatus(s: Record<string, unknown>) {
  return { id: String(s.id), name: String(s.name), code: String(s.code ?? ""), countsAsAbsent: Boolean(s.counts_as_absent), color: String(s.color ?? "#999999") };
}

/** Una fecha AAAA-MM-DD; por defecto hoy. */
function singleDate(value: unknown) {
  if (value == null || value === "") return dateOnly(new Date());
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(new Date(value).getTime())) {
    throw new HttpError(400, "Fecha inválida (usa AAAA-MM-DD).", "validation_error");
  }
  return value;
}

/** Rango `from`/`to` (AAAA-MM-DD); por defecto los últimos 30 días. */
function dateRange(query: Record<string, unknown>) {
  const parse = (value: unknown, label: string) => {
    if (value == null || value === "") return null;
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(new Date(value).getTime())) {
      throw new HttpError(400, `${label} inválida (usa AAAA-MM-DD).`, "validation_error");
    }
    return value;
  };
  const to = parse(query.to, "Fecha final") ?? dateOnly(new Date());
  const from = parse(query.from, "Fecha inicial") ?? dateOnly(new Date(new Date(to).getTime() - 29 * 86_400_000));
  if (from > to) throw new HttpError(400, "La fecha inicial no puede ser posterior a la final.", "validation_error");
  return { from, to };
}

