import {
  AppContext,
  assertStudentEnrolledInClass,
  assertTeacherCanUseClass,
  isAdmin,
  requireRole,
} from "../shared/auth.ts";
import { expectSingle } from "../shared/db.ts";
import { HttpError } from "../shared/http.ts";
import { db } from "../shared/supabase.ts";
import {
  asList,
  asRecord,
  optionalId,
  optionalString,
  requiredId,
  requiredNumber,
  requiredString,
} from "../shared/validators.ts";

function normalizeScaleRange(
  value: unknown,
  minValue: number,
  maxValue: number,
) {
  const range = asRecord(value);
  const label = requiredString(range.label, "Etiqueta de rango", 30);
  const rangeMin = requiredNumber(
    range.rangeMin ?? range.range_min,
    "Mínimo del rango",
  );
  const rangeMax = requiredNumber(
    range.rangeMax ?? range.range_max,
    "Máximo del rango",
  );
  if (rangeMin > rangeMax || rangeMin < minValue || rangeMax > maxValue) {
    throw new HttpError(
      400,
      "Los rangos de escala deben estar ordenados y dentro del mínimo/máximo.",
      "validation_error",
    );
  }
  const color = optionalString(range.color, 7);
  if (color != null && !/^#[0-9a-fA-F]{6}$/.test(color)) {
    throw new HttpError(400, "Color de rango inválido.", "validation_error");
  }
  return {
    label,
    range_min: rangeMin,
    range_max: rangeMax,
    description: optionalString(range.description, 150),
    passed: range.passed == null ? true : Boolean(range.passed),
    color,
  };
}

export async function upsertScale(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  if (!isAdmin(ctx)) {
    throw new HttpError(
      403,
      "Solo administración puede configurar escalas.",
      "forbidden",
    );
  }
  const id = optionalId(payload.id);
  const name = requiredString(payload.name, "Nombre de escala", 80);
  const type = requiredString(
    payload.type ?? payload.scale_type,
    "Tipo de escala",
    20,
  );
  if (!["numeric", "qualitative", "letters"].includes(type)) {
    throw new HttpError(400, "Tipo de escala inválido.", "validation_error");
  }
  const minValue = requiredNumber(
    payload.minValue ?? payload.min_value,
    "Valor mínimo",
  );
  const maxValue = requiredNumber(
    payload.maxValue ?? payload.max_value,
    "Valor máximo",
  );
  const passValue = requiredNumber(
    payload.passValue ?? payload.pass_value,
    "Valor de aprobación",
  );
  const decimals = Math.trunc(
    requiredNumber(payload.decimals ?? 0, "Decimales"),
  );
  if (
    minValue >= maxValue || passValue < minValue || passValue > maxValue ||
    decimals < 0 || decimals > 4
  ) {
    throw new HttpError(
      400,
      "Configuración de escala inválida.",
      "validation_error",
    );
  }

  const row = id == null
    ? await expectSingle<Record<string, unknown>>(
      db
        .from("grading_scales")
        .insert({
          institution_id: ctx.institutionId,
          name,
          scale_type: type,
          min_value: minValue,
          max_value: maxValue,
          pass_value: passValue,
          decimals,
          active: true,
        })
        .select("id")
        .single(),
      "No se pudo crear la escala.",
    )
    : await expectSingle<Record<string, unknown>>(
      db
        .from("grading_scales")
        .update({
          name,
          scale_type: type,
          min_value: minValue,
          max_value: maxValue,
          pass_value: passValue,
          decimals,
          active: true,
        })
        .eq("id", id)
        .eq("institution_id", ctx.institutionId)
        .select("id")
        .single(),
      "No se pudo actualizar la escala.",
    );
  const scaleId = Number(row.id);

  const ranges = asList(payload.ranges).map((range) => ({
    scale_id: scaleId,
    ...normalizeScaleRange(range, minValue, maxValue),
  }));
  const deleteResult = await db.from("grading_scale_ranges").delete().eq(
    "scale_id",
    scaleId,
  );
  if (deleteResult.error) {
    throw new HttpError(400, deleteResult.error.message, "db_error");
  }
  if (ranges.length > 0) {
    const insertResult = await db.from("grading_scale_ranges").insert(ranges);
    if (insertResult.error) {
      throw new HttpError(400, insertResult.error.message, "db_error");
    }
  }

  const scale = await expectSingle<Record<string, unknown>>(
    db
      .from("grading_scales")
      .select(
        "id, name, scale_type, min_value, max_value, pass_value, decimals, active, grading_scale_ranges(label, range_min, range_max, description, passed, color)",
      )
      .eq("id", scaleId)
      .single(),
    "Escala no encontrada.",
  );
  return { scale };
}

export async function setDefaultScale(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  if (!isAdmin(ctx)) {
    throw new HttpError(
      403,
      "Solo administración puede configurar escalas.",
      "forbidden",
    );
  }
  const id = requiredId(payload.id, "Escala");
  await expectSingle(
    db
      .from("grading_scales")
      .select("id")
      .eq("id", id)
      .eq("institution_id", ctx.institutionId)
      .single(),
    "Escala no encontrada.",
  );
  const { error } = await db
    .from("institution_settings")
    .upsert({
      institution_id: ctx.institutionId,
      key: "default_grading_scale_id",
      value: String(id),
      data_type: "string",
      updated_at: new Date().toISOString(),
    }, { onConflict: "institution_id,key" });
  if (error) throw new HttpError(400, error.message, "db_error");
  return { ok: true };
}

export async function setGrade(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  requireRole(ctx, ["teacher"]);
  const evaluationId = requiredId(payload.evaluationId, "Evaluación");
  const studentId = requiredId(payload.studentId, "Estudiante");
  const rawScore = requiredNumber(payload.rawScore, "Nota");
  if (rawScore < 0) {
    throw new HttpError(
      400,
      "La nota no puede ser negativa.",
      "validation_error",
    );
  }
  const evaluation = await expectSingle<Record<string, unknown>>(
    db
      .from("evaluations")
      .select("id, class_id")
      .eq("id", evaluationId)
      .eq("institution_id", ctx.institutionId)
      .single(),
    "Evaluación no encontrada.",
  );
  const cls = await assertTeacherCanUseClass(ctx, Number(evaluation.class_id));
  await assertStudentEnrolledInClass(
    ctx.institutionId,
    studentId,
    Number(evaluation.class_id),
    Number(cls.group_id),
  );

  const { error } = await db
    .from("grades")
    .upsert({
      institution_id: ctx.institutionId,
      evaluation_id: evaluationId,
      student_id: studentId,
      score: rawScore,
      notes: optionalString(payload.notes, 500),
      recorded_by: ctx.userId,
      updated_at: new Date().toISOString(),
    }, { onConflict: "evaluation_id,student_id" });
  if (error) throw new HttpError(400, error.message, "db_error");
  return { ok: true };
}
