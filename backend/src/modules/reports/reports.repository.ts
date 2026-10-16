import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class ReportsRepository {
  async findStudent(institutionId: number, studentId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("students")
        .select("id, person_id, institution_id, persons(first_name, last_name)")
        .eq("institution_id", institutionId)
        .eq("id", studentId)
        .single(),
      "Estudiante no encontrado.",
    );
  }

  async listPeriodGrades(
    institutionId: number,
    studentId: number,
    academicPeriodId: number,
  ) {
    const { data, error } = await db
      .from("period_grades")
      .select("*, subjects(name), classes(id, subjects(name), teachers(id, persons(first_name, last_name)))")
      .eq("institution_id", institutionId)
      .eq("student_id", studentId)
      .eq("academic_period_id", academicPeriodId)
      .order("subject_id");
    assertNoDbError(error);
    return data ?? [];
  }

  async createReportCard(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("report_cards").insert(payload).select("*").single(),
      "No se pudo generar el boletín.",
    );
  }

  async insertReportCardLines(lines: Record<string, unknown>[]) {
    if (lines.length === 0) return [];
    const { data, error } = await db
      .from("report_card_lines")
      .insert(lines)
      .select("*");
    assertNoDbError(error);
    return data ?? [];
  }

  /** Boletines de la institución, del más reciente al más antiguo; filtra por periodo y/o alumnos. */
  async listReportCards(
    institutionId: number,
    filters: { academicPeriodId?: number | null; studentIds?: number[] | null },
  ) {
    if (filters.studentIds != null && filters.studentIds.length === 0) return [];
    let query = db
      .from("report_cards")
      .select("id, student_id, academic_period_id, overall_average, general_notes, status, generated_at, students(persons(first_name, last_name)), academic_periods(name)")
      .eq("institution_id", institutionId)
      .order("generated_at", { ascending: false })
      .order("id", { ascending: false });
    if (filters.academicPeriodId != null) query = query.eq("academic_period_id", filters.academicPeriodId);
    if (filters.studentIds != null) query = query.in("student_id", filters.studentIds);
    const { data, error } = await query;
    assertNoDbError(error);
    return (data ?? []) as Record<string, unknown>[];
  }

  /** Alumnos activos inscritos en un salón. */
  async activeStudentIdsOfGroup(institutionId: number, groupId: number) {
    const { data, error } = await db
      .from("enrollments")
      .select("student_id, students!inner(active)")
      .eq("institution_id", institutionId)
      .eq("group_id", groupId)
      .eq("students.active", true);
    assertNoDbError(error);
    return ((data ?? []) as Record<string, unknown>[]).map((row) => Number(row.student_id));
  }

  async findReportCard(institutionId: number, id: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("report_cards")
        .select("*, report_card_lines(*, subjects(name))")
        .eq("institution_id", institutionId)
        .eq("id", id)
        .single(),
      "Boletín no encontrado.",
    );
  }
}

export const reportsRepository = new ReportsRepository();
