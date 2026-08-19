import {
  AppContext,
  assertStudentEnrolledInClass,
  assertTeacherCanUseClass,
  currentTeacherId,
  requireRole,
} from "../shared/auth.ts";
import { expectSingle } from "../shared/db.ts";
import { HttpError } from "../shared/http.ts";
import { db } from "../shared/supabase.ts";
import {
  dateOnly,
  optionalString,
  requiredDate,
  requiredId,
  requiredString,
} from "../shared/validators.ts";

export async function upsertClassSession(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  requireRole(ctx, ["teacher"]);
  const classId = requiredId(payload.classId, "Clase");
  const sessionDate = requiredDate(payload.dateMs, "Fecha de sesión");
  const teacherId = await currentTeacherId(ctx);
  if (teacherId == null) {
    throw new HttpError(
      403,
      "Tu usuario no está enlazado a un docente.",
      "forbidden",
    );
  }
  const cls = await assertTeacherCanUseClass(ctx, classId);
  const date = dateOnly(sessionDate);

  const { data: existing } = await db
    .from("class_sessions")
    .select("id")
    .eq("institution_id", ctx.institutionId)
    .eq("class_id", classId)
    .eq("date", date)
    .eq("recorded_by", teacherId)
    .maybeSingle();

  const row = existing == null
    ? await expectSingle<Record<string, unknown>>(
      db
        .from("class_sessions")
        .insert({
          institution_id: ctx.institutionId,
          class_id: classId,
          group_id: cls.group_id,
          date,
          recorded_by: teacherId,
          synced: true,
        })
        .select("id")
        .single(),
      "No se pudo crear la sesión de clase.",
    )
    : await expectSingle<Record<string, unknown>>(
      db
        .from("class_sessions")
        .update({ group_id: cls.group_id, synced: true })
        .eq("id", existing.id)
        .select("id")
        .single(),
      "No se pudo actualizar la sesión de clase.",
    );
  return { id: Number(row.id) };
}

export async function upsertAttendance(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  requireRole(ctx, ["teacher"]);
  const uuid = requiredString(payload.uuid, "UUID", 80);
  const classId = requiredId(payload.classId, "Clase");
  const studentId = requiredId(payload.studentId, "Estudiante");
  const statusId = requiredId(payload.statusId, "Estado de asistencia");
  const recordedAt = requiredDate(payload.recordedAtMs, "Fecha de marcado");
  const classSessionId = requiredId(payload.classSessionId, "Sesión de clase");
  await assertTeacherCanUseClass(ctx, classId);

  const session = await expectSingle<Record<string, unknown>>(
    db
      .from("class_sessions")
      .select("id, group_id")
      .eq("id", classSessionId)
      .eq("institution_id", ctx.institutionId)
      .eq("class_id", classId)
      .single(),
    "Sesión de clase no encontrada.",
  );
  await assertStudentEnrolledInClass(
    ctx.institutionId,
    studentId,
    classId,
    Number(session.group_id),
  );

  const { data: status } = await db
    .from("catalog_attendance_statuses")
    .select("id")
    .eq("id", statusId)
    .maybeSingle();
  if (!status) {
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

  const { data: existingByUuid } = await db
    .from("attendances")
    .select("id")
    .eq("uuid", uuid)
    .maybeSingle();
  const row = existingByUuid == null
    ? await expectSingle<Record<string, unknown>>(
      db
        .from("attendances")
        .upsert(dbPayload, { onConflict: "class_session_id,student_id" })
        .select("id")
        .single(),
      "No se pudo registrar la asistencia.",
    )
    : await expectSingle<Record<string, unknown>>(
      db
        .from("attendances")
        .update(dbPayload)
        .eq("id", existingByUuid.id)
        .select("id")
        .single(),
      "No se pudo actualizar la asistencia.",
    );
  return { id: Number(row.id) };
}
