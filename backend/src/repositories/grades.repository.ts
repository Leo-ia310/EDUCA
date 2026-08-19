import { assertNoDbError, expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class GradesRepository {
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

  async findScaleForHydration(scaleId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("grading_scales")
        .select(
          "id, name, scale_type, min_value, max_value, pass_value, decimals, active, grading_scale_ranges(label, range_min, range_max, description, passed, color)",
        )
        .eq("id", scaleId)
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
