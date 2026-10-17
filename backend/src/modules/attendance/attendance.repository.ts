import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class AttendanceRepository {
  async ensureClassSession(classId: number, date: string) {
    return expectSingle<number>(db.rpc("ensure_collaborative_class_session", { p_class_id: classId, p_date: date }), "No se pudo crear la sesión de clase.");
  }
  async findClassSession(
    institutionId: number,
    classId: number,
    date: string,
    teacherId: number,
  ) {
    const { data } = await db
      .from("class_sessions")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("class_id", classId)
      .eq("date", date)
      .eq("recorded_by", teacherId)
      .maybeSingle();
    return data;
  }

  async insertClassSession(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("class_sessions").insert(payload).select("id").single(),
      "No se pudo crear la sesión de clase.",
    );
  }

  async updateClassSession(
    institutionId: number,
    id: unknown,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("class_sessions")
        .update(payload)
        .eq("institution_id", institutionId)
        .eq("id", id)
        .select("id")
        .single(),
      "No se pudo actualizar la sesión de clase.",
    );
  }

  async findClassSessionById(
    institutionId: number,
    classId: number,
    classSessionId: number,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("class_sessions")
        .select("id, group_id")
        .eq("id", classSessionId)
        .eq("institution_id", institutionId)
        .eq("class_id", classId)
        .single(),
      "Sesión de clase no encontrada.",
    );
  }

  async attendanceStatusExists(statusId: number) {
    const { data } = await db
      .from("catalog_attendance_statuses")
      .select("id")
      .eq("id", statusId)
      .maybeSingle();
    return data != null;
  }

  async findAttendanceByUuid(institutionId: number, uuid: string) {
    const { data } = await db
      .from("attendances")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("uuid", uuid)
      .maybeSingle();
    return data;
  }

  async upsertAttendance(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("attendances")
        .upsert(payload, { onConflict: "class_session_id,student_id" })
        .select("id")
        .single(),
      "No se pudo registrar la asistencia.",
    );
  }

  async updateAttendance(
    institutionId: number,
    id: unknown,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("attendances")
        .update(payload)
        .eq("institution_id", institutionId)
        .eq("id", id)
        .select("id")
        .single(),
      "No se pudo actualizar la asistencia.",
    );
  }

  async findSessionOfClassDate(institutionId: number, classId: number, date: string) {
    const { data, error } = await db
      .from("class_sessions")
      .select("id, group_id")
      .eq("institution_id", institutionId)
      .eq("class_id", classId)
      .eq("date", date)
      .order("id")
      .limit(1);
    assertNoDbError(error);
    return ((data ?? [])[0] ?? null) as Record<string, unknown> | null;
  }

  async marksOfSession(institutionId: number, sessionId: number) {
    const { data, error } = await db
      .from("attendances")
      .select("uuid, student_id, attendance_status_id, notes")
      .eq("institution_id", institutionId)
      .eq("class_session_id", sessionId);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async upsertMarks(rows: Array<Record<string, unknown>>) {
    const { error } = await db.from("attendances").upsert(rows, { onConflict: "class_session_id,student_id" });
    assertNoDbError(error);
  }

  async classLabel(institutionId: number, classId: number) {
    const { data, error } = await db
      .from("classes")
      .select("id, group_id, subjects(name), groups(name)")
      .eq("institution_id", institutionId)
      .eq("id", classId)
      .maybeSingle();
    assertNoDbError(error);
    return data as Record<string, any> | null;
  }

  async statuses() {
    const { data, error } = await db
      .from("catalog_attendance_statuses")
      .select("id, name, code, counts_as_absent, color")
      .eq("active", true)
      .order("id");
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async sessionsInRange(institutionId: number, from: string, to: string, groupId?: number) {
    let query = db
      .from("class_sessions")
      .select("id, class_id, group_id, date, topic, classes(subjects(name))")
      .eq("institution_id", institutionId)
      .gte("date", from)
      .lte("date", to)
      .order("date", { ascending: false });
    if (groupId != null) query = query.eq("group_id", groupId);
    const { data, error } = await query;
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async marksOfSessions(institutionId: number, sessionIds: number[]) {
    const rows: Array<Record<string, unknown>> = [];
    for (let i = 0; i < sessionIds.length; i += 150) {
      const { data, error } = await db
        .from("attendances")
        .select("class_session_id, student_id, attendance_status_id")
        .eq("institution_id", institutionId)
        .in("class_session_id", sessionIds.slice(i, i + 150));
      assertNoDbError(error);
      rows.push(...((data ?? []) as Array<Record<string, unknown>>));
    }
    return rows;
  }

  async groupNames(institutionId: number, groupId?: number) {
    let query = db.from("groups").select("id, name").eq("institution_id", institutionId).eq("active", true);
    if (groupId != null) query = query.eq("id", groupId);
    const { data, error } = await query;
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async enrolledStudents(institutionId: number, groupId: number) {
    const { data, error } = await db
      .from("enrollments")
      .select("student_id, students!inner(id, active, persons(first_name, last_name))")
      .eq("institution_id", institutionId)
      .eq("group_id", groupId)
      .eq("students.active", true);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }
}

export const attendanceRepository = new AttendanceRepository();
