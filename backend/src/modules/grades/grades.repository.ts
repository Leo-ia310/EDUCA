import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class GradesRepository {
  constructor(private readonly client: any = db) {}

  async findActiveScales(institutionId: number) {
    const { data, error } = await this.client
      .from("grading_scales")
      .select("id, name, scale_type, min_value, max_value, pass_value, decimals, active, grading_scale_ranges(label, range_min, range_max, description, passed, color)")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .order("id");
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async findDefaultScaleSetting(institutionId: number) {
    const { data, error } = await this.client
      .from("institution_settings")
      .select("value")
      .eq("institution_id", institutionId)
      .eq("key", "default_grading_scale_id")
      .maybeSingle();
    assertNoDbError(error);
    return data?.value == null ? null : String(data.value);
  }

  async insertScale(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("grading_scales").insert(payload).select("id").single(),
      "No se pudo crear la escala.",
    );
  }

  async updateScale(
    id: number,
    institutionId: number,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("grading_scales")
        .update(payload)
        .eq("id", id)
        .eq("institution_id", institutionId)
        .select("id")
        .single(),
      "No se pudo actualizar la escala.",
    );
  }

  async deleteScaleRanges(scaleId: number) {
    const { error } = await db
      .from("grading_scale_ranges")
      .delete()
      .eq("scale_id", scaleId);
    assertNoDbError(error);
  }

  async insertScaleRanges(rows: Array<Record<string, unknown>>) {
    const { error } = await db.from("grading_scale_ranges").insert(rows);
    assertNoDbError(error);
  }

  async findScaleForHydration(institutionId: number, scaleId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("grading_scales")
        .select(
          "id, name, scale_type, min_value, max_value, pass_value, decimals, active, grading_scale_ranges(label, range_min, range_max, description, passed, color)",
        )
        .eq("id", scaleId)
        .eq("institution_id", institutionId)
        .single(),
      "Escala no encontrada.",
    );
  }

  async findInstitutionScale(institutionId: number, scaleId: number) {
    return expectSingle(
      db
        .from("grading_scales")
        .select("id")
        .eq("id", scaleId)
        .eq("institution_id", institutionId)
        .single(),
      "Escala no encontrada.",
    );
  }

  async upsertDefaultScaleSetting(institutionId: number, scaleId: number) {
    const { error } = await db
      .from("institution_settings")
      .upsert({
        institution_id: institutionId,
        key: "default_grading_scale_id",
        value: String(scaleId),
        data_type: "string",
        updated_at: new Date().toISOString(),
      }, { onConflict: "institution_id,key" });
    assertNoDbError(error);
  }

  async currentPeriods(institutionId: number) {
    const year = await this.client
      .from("academic_years")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("is_current", true)
      .maybeSingle();
    assertNoDbError(year.error);
    if (year.data == null) return [] as Array<Record<string, unknown>>;
    const { data, error } = await this.client
      .from("academic_periods")
      .select("id, name, start_date, end_date, weight, closed")
      .eq("institution_id", institutionId)
      .eq("academic_year_id", year.data.id)
      .order("display_order");
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async gradebookEvaluations(institutionId: number, classId: number, periodId: number) {
    const { data, error } = await this.client
      .from("evaluations")
      .select("id, title, date, max_score, weight, catalog_evaluation_types(code)")
      .eq("institution_id", institutionId)
      .eq("class_id", classId)
      .eq("academic_period_id", periodId)
      .order("date");
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async enrolledStudents(institutionId: number, groupId: number) {
    const { data, error } = await this.client
      .from("enrollments")
      .select("student_id, students!inner(id, active, persons(first_name, last_name))")
      .eq("institution_id", institutionId)
      .eq("group_id", groupId)
      .eq("students.active", true);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async gradesOfEvaluations(institutionId: number, evaluationIds: number[]) {
    if (evaluationIds.length === 0) return [] as Array<Record<string, unknown>>;
    const { data, error } = await this.client
      .from("grades")
      .select("evaluation_id, student_id, score")
      .eq("institution_id", institutionId)
      .in("evaluation_id", evaluationIds);
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async findEvaluationForGrade(institutionId: number, evaluationId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("evaluations")
        .select("id, class_id")
        .eq("id", evaluationId)
        .eq("institution_id", institutionId)
        .single(),
      "Evaluación no encontrada.",
    );
  }

  async upsertGrade(payload: Record<string, unknown>) {
    const { error } = await db
      .from("grades")
      .upsert(payload, { onConflict: "evaluation_id,student_id" });
    assertNoDbError(error);
  }
}

export const gradesRepository = new GradesRepository();

