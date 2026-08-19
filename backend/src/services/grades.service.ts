import { HttpError } from "../lib/errors";
import {
  asList,
  asRecord,
  optionalId,
  optionalString,
  requiredId,
  requiredNumber,
  requiredString,
} from "../validators/common.validators";
import {
  gradesRepository,
  GradesRepository,
} from "../repositories/grades.repository";
import type { AppContext } from "../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "./permissions.service";

export class GradesService {
  constructor(
    private readonly repository: GradesRepository = gradesRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async upsertScale(ctx: AppContext, payload: Record<string, unknown>) {
    if (!this.permissions.isAdmin(ctx)) {
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
      ? await this.repository.insertScale({
        institution_id: ctx.institutionId,
        name,
        scale_type: type,
        min_value: minValue,
        max_value: maxValue,
        pass_value: passValue,
        decimals,
        active: true,
      })
      : await this.repository.updateScale(id, ctx.institutionId, {
        name,
        scale_type: type,
        min_value: minValue,
        max_value: maxValue,
        pass_value: passValue,
        decimals,
        active: true,
      });
    const scaleId = Number(row.id);

    const ranges = asList(payload.ranges).map((range) => ({
      scale_id: scaleId,
      ...this.normalizeScaleRange(range, minValue, maxValue),
    }));
    await this.repository.deleteScaleRanges(scaleId);
    if (ranges.length > 0) {
      await this.repository.insertScaleRanges(ranges);
    }

    const scale = await this.repository.findScaleForHydration(scaleId);
    return { scale };
  }

  async setDefaultScale(ctx: AppContext, payload: Record<string, unknown>) {
    if (!this.permissions.isAdmin(ctx)) {
      throw new HttpError(
        403,
        "Solo administración puede configurar escalas.",
        "forbidden",
      );
    }
    const id = requiredId(payload.id, "Escala");
    await this.repository.findInstitutionScale(ctx.institutionId, id);
    await this.repository.upsertDefaultScaleSetting(ctx.institutionId, id);
    return { ok: true };
  }

  async setGrade(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
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
    const evaluation = await this.repository.findEvaluationForGrade(
      ctx.institutionId,
      evaluationId,
    );
    const cls = await this.permissions.assertTeacherCanUseClass(
      ctx,
      Number(evaluation.class_id),
    );
    await this.permissions.assertStudentEnrolledInClass(
      ctx.institutionId,
      studentId,
      Number(evaluation.class_id),
      Number(cls.group_id),
    );

    await this.repository.upsertGrade({
      institution_id: ctx.institutionId,
      evaluation_id: evaluationId,
      student_id: studentId,
      score: rawScore,
      notes: optionalString(payload.notes, 500),
      recorded_by: ctx.userId,
      updated_at: new Date().toISOString(),
    });
    return { ok: true };
  }

  private normalizeScaleRange(
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
}

export const gradesService = new GradesService();
