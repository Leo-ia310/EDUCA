import { HttpError } from "../lib/errors";
import type { AppContext } from "../types/app-context";
import { requiredId, optionalString } from "../validators/common.validators";
import {
  permissionsService,
  PermissionsService,
} from "./permissions.service";
import {
  reportsRepository,
  ReportsRepository,
} from "../repositories/reports.repository";

export class ReportsService {
  constructor(
    private readonly repository: ReportsRepository = reportsRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async previewReportCard(ctx: AppContext, query: Record<string, unknown>) {
    const studentId = await this.permissions.normalizeStudentId(
      ctx,
      query.studentId ?? query.student_id,
      "estudiante",
    );
    const academicPeriodId = requiredId(
      query.academicPeriodId ?? query.academic_period_id,
      "Periodo académico",
    );
    return this.buildReport(ctx, studentId, academicPeriodId);
  }

  async generateReportCard(ctx: AppContext, payload: Record<string, unknown>) {
    if (!this.permissions.isAdmin(ctx) && !ctx.roles.has("teacher")) {
      throw new HttpError(403, "No puedes generar boletines.", "forbidden");
    }
    const studentId = requiredId(payload.studentId ?? payload.student_id, "Estudiante");
    const academicPeriodId = requiredId(
      payload.academicPeriodId ?? payload.academic_period_id,
      "Periodo académico",
    );
    const report = await this.buildReport(ctx, studentId, academicPeriodId);
    const card = await this.repository.createReportCard({
      institution_id: ctx.institutionId,
      student_id: studentId,
      academic_period_id: academicPeriodId,
      overall_average: report.overallAverage,
      general_notes: optionalString(payload.generalNotes ?? payload.general_notes, 2000),
      status: "generated",
      generated_at: new Date().toISOString(),
    });
    const lines = await this.repository.insertReportCardLines(
      report.lines.map((line: ReportLine) => ({
        report_card_id: card.id,
        subject_id: line.subjectId,
        final_score: line.finalScore,
        qualitative_label: line.qualitativeLabel,
        passed: line.passed,
        notes: line.notes,
        teacher_id: line.teacherId,
      })),
    );
    return {
      reportCard: {
        ...card,
        lines,
        pdfStatus: "not_generated",
        pdfScope:
          "La generación binaria de PDF queda fuera del MVP backend actual; el cálculo oficial y persistencia del boletín ya están centralizados.",
      },
    };
  }

  async getReportCard(ctx: AppContext, idValue: unknown) {
    const id = requiredId(idValue, "Boletín");
    const card = await this.repository.findReportCard(ctx.institutionId, id);
    await this.permissions.normalizeStudentId(ctx, card.student_id, "estudiante");
    return { reportCard: card };
  }

  private async buildReport(
    ctx: AppContext,
    studentId: number,
    academicPeriodId: number,
  ) {
    const [student, grades] = await Promise.all([
      this.repository.findStudent(ctx.institutionId, studentId),
      this.repository.listPeriodGrades(ctx.institutionId, studentId, academicPeriodId),
    ]);
    const lines: ReportLine[] = grades.map((row: Record<string, unknown>) => ({
      subjectId: row.subject_id == null ? null : Number(row.subject_id),
      classId: row.class_id == null ? null : Number(row.class_id),
      teacherId: this.teacherId(row),
      subjectName: this.subjectName(row),
      finalScore: row.final_score == null ? null : Number(row.final_score),
      qualitativeLabel: row.qualitative_label ?? null,
      passed: row.passed ?? null,
      notes: row.notes ?? null,
    }));
    const scored = lines
      .map((line: ReportLine) => line.finalScore)
      .filter((score: number | null): score is number => typeof score === "number" && Number.isFinite(score));
    const overallAverage = scored.length === 0
      ? null
      : Math.round((scored.reduce((sum: number, score: number) => sum + score, 0) / scored.length) * 100) / 100;
    const person = student.persons as Record<string, unknown> | null;
    return {
      student: {
        id: String(student.id),
        name: `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim(),
      },
      academicPeriodId: String(academicPeriodId),
      calculation: "promedio_aritmetico_simple_period_grades",
      overallAverage,
      lines,
      pdfStatus: "not_generated",
    };
  }

  private subjectName(row: Record<string, unknown>) {
    const subject = row.subjects as Record<string, unknown> | null;
    const cls = row.classes as Record<string, unknown> | null;
    const classSubject = cls?.subjects as Record<string, unknown> | null;
    return String(subject?.name ?? classSubject?.name ?? "Materia");
  }

  private teacherId(row: Record<string, unknown>) {
    const cls = row.classes as Record<string, unknown> | null;
    const teacher = cls?.teachers as Record<string, unknown> | null;
    return teacher?.id == null ? null : Number(teacher.id);
  }
}

export const reportsService = new ReportsService();

type ReportLine = {
  subjectId: number | null;
  classId: number | null;
  teacherId: number | null;
  subjectName: string;
  finalScore: number | null;
  qualitativeLabel: unknown;
  passed: unknown;
  notes: unknown;
};
