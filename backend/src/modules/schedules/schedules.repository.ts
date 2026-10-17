import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const SCHEDULE_SELECT =
  "id, institution_id, class_id, kind, label, shift, group_id, weekday_id, start_time, end_time, classroom_id, " +
  "classrooms(name), groups(name), " +
  "classes(id, group_id, teacher_id, subjects(name), groups(name), teachers(persons(first_name, last_name)))";

export type ScheduleRow = Record<string, any>;

export class SchedulesRepository {
  constructor(private readonly db: any = supabaseAdmin) {}

  /** Scope in SQL: never load another group's timetable for a student. */
  async listForClasses(institutionId: number, classIds: number[], groupIds: number[]): Promise<ScheduleRow[]> {
    if (classIds.length === 0) return [];
    const { data: classes, error: classError } = await this.db
      .from("schedules")
      .select(SCHEDULE_SELECT)
      .eq("institution_id", institutionId)
      .in("class_id", classIds)
      .order("weekday_id")
      .order("start_time");
    assertNoDbError(classError);
    // A general break alone is not an assigned timetable.
    if (!classes?.length) return [];
    const { data: breaks, error: breakError } = await this.db
      .from("schedules")
      .select(SCHEDULE_SELECT)
      .eq("institution_id", institutionId)
      .eq("kind", "break")
      .or(groupIds.length ? `group_id.is.null,group_id.in.(${groupIds.join(",")})` : "group_id.is.null");
    assertNoDbError(breakError);
    return [...classes, ...(breaks ?? [])].sort((a, b) =>
      Number(a.weekday_id) - Number(b.weekday_id) || String(a.start_time).localeCompare(String(b.start_time)),
    );
  }

  async listByInstitution(institutionId: number): Promise<ScheduleRow[]> {
    const { data, error } = await this.db
      .from("schedules")
      .select(SCHEDULE_SELECT)
      .eq("institution_id", institutionId)
      .order("weekday_id")
      .order("start_time");
    assertNoDbError(error);
    return (data ?? []) as ScheduleRow[];
  }

  async findById(institutionId: number, id: number): Promise<ScheduleRow> {
    return expectSingle<ScheduleRow>(
      this.db
        .from("schedules")
        .select(SCHEDULE_SELECT)
        .eq("institution_id", institutionId)
        .eq("id", id)
        .single(),
      "Horario no encontrado.",
    );
  }

  async insertMany(rows: Record<string, unknown>[]): Promise<number[]> {
    const { data, error } = await this.db.from("schedules").insert(rows).select("id");
    assertNoDbError(error);
    return ((data ?? []) as { id: number }[]).map((row) => Number(row.id));
  }

  async update(institutionId: number, id: number, payload: Record<string, unknown>) {
    const { error } = await this.db
      .from("schedules")
      .update(payload)
      .eq("institution_id", institutionId)
      .eq("id", id);
    assertNoDbError(error);
  }

  async delete(institutionId: number, id: number) {
    const { error } = await this.db
      .from("schedules")
      .delete()
      .eq("institution_id", institutionId)
      .eq("id", id);
    assertNoDbError(error);
  }

  async findClass(institutionId: number, classId: number) {
    const { data, error } = await this.db
      .from("classes")
      .select("id, group_id, teacher_id")
      .eq("institution_id", institutionId)
      .eq("id", classId)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(error);
    return data as { id: number; group_id: number; teacher_id: number | null } | null;
  }

  async findGroup(institutionId: number, groupId: number) {
    const { data, error } = await this.db
      .from("groups")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("id", groupId)
      .maybeSingle();
    assertNoDbError(error);
    return data as { id: number } | null;
  }

  /** Busca un aula por nombre en la institución; la crea si no existe. */
  async ensureClassroom(institutionId: number, name: string): Promise<number> {
    const { data, error } = await this.db
      .from("classrooms")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("name", name)
      .limit(1);
    assertNoDbError(error);
    if (Array.isArray(data) && data.length > 0) return Number(data[0].id);
    const created = await expectSingle<{ id: number }>(
      this.db
        .from("classrooms")
        .insert({ institution_id: institutionId, name, active: true })
        .select("id")
        .single(),
      "No se pudo crear el aula.",
    );
    return Number(created.id);
  }

  async groupIdsOfStudent(institutionId: number, studentId: number) {
    const { data, error } = await this.db
      .from("enrollments")
      .select("group_id")
      .eq("institution_id", institutionId)
      .eq("student_id", studentId);
    assertNoDbError(error);
    return [
      ...new Set(
        ((data ?? []) as { group_id: number | null }[])
          .map((row) => row.group_id)
          .filter((id): id is number => id != null)
          .map(Number),
      ),
    ];
  }

  async classesOfTeacher(institutionId: number, teacherId: number) {
    const { data, error } = await this.db
      .from("classes")
      .select("id, group_id")
      .eq("institution_id", institutionId)
      .eq("teacher_id", teacherId)
      .eq("active", true);
    assertNoDbError(error);
    return (data ?? []) as { id: number; group_id: number }[];
  }

  async classesOfGroups(institutionId: number, groupIds: number[]) {
    if (groupIds.length === 0) return [];
    const { data, error } = await this.db
      .from("classes")
      .select("id, group_id")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .in("group_id", groupIds);
    assertNoDbError(error);
    return (data ?? []) as { id: number; group_id: number }[];
  }
}

export const schedulesRepository = new SchedulesRepository();
