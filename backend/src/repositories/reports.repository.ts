import { assertNoDbError, expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

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
