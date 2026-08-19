import { expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class AttendanceRepository {
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

  async updateClassSession(id: unknown, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("class_sessions")
        .update(payload)
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

  async findAttendanceByUuid(uuid: string) {
    const { data } = await db
      .from("attendances")
      .select("id")
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

  async updateAttendance(id: unknown, payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("attendances")
        .update(payload)
        .eq("id", id)
        .select("id")
        .single(),
      "No se pudo actualizar la asistencia.",
    );
  }
}

export const attendanceRepository = new AttendanceRepository();
