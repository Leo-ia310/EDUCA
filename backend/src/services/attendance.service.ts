import { assertNoDbError } from "../lib/db";
import { HttpError } from "../lib/errors";
import {
  dateOnly,
  optionalString,
  requiredDate,
  requiredId,
  requiredString,
} from "../validators/common.validators";
import {
  attendanceRepository,
  AttendanceRepository,
} from "../repositories/attendance.repository";
import type { AppContext } from "../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "./permissions.service";

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
    const cls = await this.permissions.assertTeacherCanUseClass(ctx, classId);
    const date = dateOnly(sessionDate);

    const existing = await this.repository.findClassSession(
      ctx.institutionId,
      classId,
      date,
      teacherId,
    );
    const row = existing == null
      ? await this.repository.insertClassSession({
        institution_id: ctx.institutionId,
        class_id: classId,
        group_id: cls.group_id,
        date,
        recorded_by: teacherId,
        synced: true,
      })
      : await this.repository.updateClassSession(existing.id, {
        group_id: cls.group_id,
        synced: true,
      });
    return { id: Number(row.id) };
  }

  async upsertAttendance(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const uuid = requiredString(payload.uuid, "UUID", 80);
    const classId = requiredId(payload.classId, "Clase");
    const studentId = requiredId(payload.studentId, "Estudiante");
    const statusId = requiredId(payload.statusId, "Estado de asistencia");
    const recordedAt = requiredDate(payload.recordedAtMs, "Fecha de marcado");
    const classSessionId = requiredId(payload.classSessionId, "Sesión de clase");
    await this.permissions.assertTeacherCanUseClass(ctx, classId);

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

    const existingByUuid = await this.repository.findAttendanceByUuid(uuid);
    const row = existingByUuid == null
      ? await this.repository.upsertAttendance(dbPayload)
      : await this.repository.updateAttendance(existingByUuid.id, dbPayload);
    return { id: Number(row.id) };
  }
}

export const attendanceService = new AttendanceService();
