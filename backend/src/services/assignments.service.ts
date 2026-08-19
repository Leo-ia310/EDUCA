import { assertNoDbError } from "../lib/db";
import { HttpError } from "../lib/errors";
import { mapAttachment } from "../lib/files";
import {
  asList,
  asRecord,
  optionalId,
  optionalString,
  requiredDate,
  requiredId,
  requiredNumber,
  requiredString,
} from "../validators/common.validators";
import {
  assignmentsRepository,
  AssignmentsRepository,
} from "../repositories/assignments.repository";
import type { AppContext } from "../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "./permissions.service";

export class AssignmentsService {
  constructor(
    private readonly repository: AssignmentsRepository = assignmentsRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async teacherClasses(ctx: AppContext) {
    this.permissions.requireRole(ctx, ["teacher"]);
    let teacherId: number | null = null;
    if (!this.permissions.isAdmin(ctx)) {
      teacherId = await this.permissions.currentTeacherId(ctx);
      if (teacherId == null) return [];
    }

    const { data, error } = await this.repository.teacherClassRows(
      ctx.institutionId,
      teacherId,
    );
    if (error) throw new HttpError(400, error.message, "db_error");

    const rows = (data ?? []) as Array<Record<string, unknown>>;
    const groupIds = [
      ...new Set(
        rows.map((row) => Number(row.group_id)).filter(Number.isFinite),
      ),
    ];
    const studentCounts = new Map<number, number>();
    if (groupIds.length > 0) {
      const { data: enrollments } =
        await this.repository.enrollmentsByGroupIds(
          ctx.institutionId,
          groupIds,
        );
      for (const enrollment of enrollments ?? []) {
        const groupId = Number((enrollment as Record<string, unknown>).group_id);
        studentCounts.set(groupId, (studentCounts.get(groupId) ?? 0) + 1);
      }
    }

    return rows.map((row) => {
      const groupId = Number(row.group_id);
      return {
        classId: Number(row.id),
        groupId,
        subjectName: String(
          (row.subjects as Record<string, unknown> | null)?.name ?? "Materia",
        ),
        groupName: String(
          (row.groups as Record<string, unknown> | null)?.name ?? "Grupo",
        ),
        startTime: "",
        endTime: "",
        studentCount: studentCounts.get(groupId) ?? 0,
      };
    });
  }

  async upsertAssignment(ctx: AppContext, payload: Record<string, unknown>) {
    const classId = requiredId(payload.classId, "Clase");
    const title = requiredString(payload.title, "Título", 200);
    const dueAt = requiredDate(payload.dueAt, "Fecha de entrega");
    const maxScore = requiredNumber(payload.maxScore, "Puntaje máximo");
    if (maxScore <= 0) {
      throw new HttpError(
        400,
        "El puntaje máximo debe ser mayor que cero.",
        "validation_error",
      );
    }

    const classRow = await this.permissions.assertTeacherCanUseClass(
      ctx,
      classId,
    );
    const assignmentId = optionalId(payload.assignmentId);
    if (assignmentId != null) {
      await this.permissions.assertTeacherCanUseAssignment(ctx, assignmentId);
    }
    const teacherId = await this.permissions.currentTeacherId(ctx);
    const academicPeriodId = await this.repository.currentAcademicPeriodId(
      ctx.institutionId,
      dueAt,
    );
    const now = new Date().toISOString();
    const dbPayload = {
      institution_id: ctx.institutionId,
      class_id: Number(classRow.id),
      academic_period_id: academicPeriodId,
      title,
      description: optionalString(payload.description),
      instructions: optionalString(payload.instructions),
      due_at: dueAt.toISOString(),
      max_score: maxScore,
      allow_late: Boolean(payload.allowLate),
      published: payload.published == null ? true : Boolean(payload.published),
      assigned_at: now,
      created_by: teacherId,
      updated_at: now,
    };

    const row = assignmentId == null
      ? await this.repository.insertAssignment(dbPayload)
      : await this.repository.updateAssignment(
        assignmentId,
        ctx.institutionId,
        dbPayload,
      );

    await this.linkAttachments(ctx, {
      attachments: payload.attachments,
      assignmentId: Number(row.id),
    });
    return { assignment: await this.hydrateAssignment(Number(row.id)) };
  }

  async deleteAssignment(ctx: AppContext, payload: Record<string, unknown>) {
    const id = requiredId(payload.id, "Tarea");
    await this.permissions.assertTeacherCanUseAssignment(ctx, id);
    const { error } = await this.repository.softDeleteAssignment(
      id,
      ctx.institutionId,
      new Date().toISOString(),
    );
    assertNoDbError(error);
    return { ok: true };
  }

  async publishAssignment(ctx: AppContext, payload: Record<string, unknown>) {
    const id = requiredId(payload.id, "Tarea");
    await this.permissions.assertTeacherCanUseAssignment(ctx, id);
    const { error } = await this.repository.updateAssignmentPublished(
      id,
      ctx.institutionId,
      Boolean(payload.published),
      new Date().toISOString(),
    );
    assertNoDbError(error);
    return { ok: true };
  }

  async submitAssignment(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["student"]);
    const assignmentId = requiredId(payload.assignmentId, "Tarea");
    const studentId = await this.permissions.normalizeStudentId(
      ctx,
      payload.studentId,
    );
    const assignment = await this.repository.findAssignmentForSubmit(
      assignmentId,
      ctx.institutionId,
    );
    if (!Boolean(assignment.published)) {
      throw new HttpError(
        400,
        "La tarea aún no está publicada.",
        "validation_error",
      );
    }
    const groupId = Number(
      (assignment.classes as Record<string, unknown> | null)?.group_id,
    );
    await this.permissions.assertStudentEnrolledInClass(
      ctx.institutionId,
      studentId,
      Number(assignment.class_id),
      groupId,
    );

    const dueAt = assignment.due_at == null
      ? null
      : new Date(String(assignment.due_at));
    if (dueAt != null && !assignment.allow_late && Date.now() > dueAt.getTime()) {
      throw new HttpError(
        400,
        "Esta tarea ya venció y no permite entregas tarde.",
        "validation_error",
      );
    }

    const statusId = await this.repository.taskStatusId("ENTR");
    const now = new Date().toISOString();
    const row = await this.repository.upsertSubmission({
      institution_id: ctx.institutionId,
      assignment_id: assignmentId,
      student_id: studentId,
      submitted_at: now,
      student_notes: optionalString(payload.notes),
      task_status_id: statusId,
      updated_at: now,
    });
    await this.linkAttachments(ctx, {
      attachments: payload.attachments,
      submissionId: Number(row.id),
    });
    return { submission: await this.hydrateSubmission(Number(row.id)) };
  }

  async gradeSubmission(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const submissionId = requiredId(payload.submissionId, "Entrega");
    const score = requiredNumber(payload.score, "Nota");
    if (score < 0) {
      throw new HttpError(
        400,
        "La nota no puede ser negativa.",
        "validation_error",
      );
    }
    const submission = await this.repository.findSubmissionWithAssignment(
      submissionId,
      ctx.institutionId,
    );
    const classId = Number(
      (submission.assignments as Record<string, unknown> | null)?.class_id,
    );
    await this.permissions.assertTeacherCanUseClass(ctx, classId);
    const { error } = await this.repository.gradeSubmissionRpc(
      submissionId,
      score,
      optionalString(payload.feedback),
    );
    assertNoDbError(error);
    return { submission: await this.hydrateSubmission(submissionId) };
  }

  private async linkAttachments(
    ctx: AppContext,
    options: {
      attachments: unknown;
      assignmentId?: number;
      submissionId?: number;
    },
  ) {
    const attachments = asList(options.attachments);
    for (const item of attachments) {
      const raw = asRecord(item);
      const fileId = optionalId(raw.id);
      if (fileId == null) continue;

      const file = await this.repository.findInstitutionFile(
        ctx.institutionId,
        fileId,
      );
      if (!file) {
        throw new HttpError(
          400,
          "Uno de los adjuntos no pertenece a esta institución.",
          "validation_error",
        );
      }

      if (options.assignmentId != null) {
        const result = await this.repository.linkAssignmentFile(
          options.assignmentId,
          fileId,
        );
        assertNoDbError(result.error);
      }
      if (options.submissionId != null) {
        const result = await this.repository.linkSubmissionFile(
          options.submissionId,
          fileId,
        );
        assertNoDbError(result.error);
      }
    }
  }

  private async attachmentRows(
    table: "assignment_files" | "submission_files",
    column: string,
    id: number,
  ) {
    const { data, error } = await this.repository.attachmentRows(
      table,
      column,
      id,
    );
    if (error) throw new HttpError(400, error.message, "db_error");
    return (data ?? [])
      .map((row: Record<string, unknown>) =>
        row.files as Record<string, unknown> | null
      )
      .filter((file: Record<string, unknown> | null): file is Record<string, unknown> =>
        file != null
      )
      .map(mapAttachment);
  }

  private async hydrateAssignment(id: number) {
    const row = await this.repository.findAssignmentForHydration(id);
    const cls = row.classes as Record<string, unknown> | null;
    const subject =
      (cls?.subjects as Record<string, unknown> | null)?.name ?? "Materia";
    const group =
      (cls?.groups as Record<string, unknown> | null)?.name ?? "Grupo";
    const teacherPerson =
      ((cls?.teachers as Record<string, unknown> | null)?.persons ??
        null) as Record<string, unknown> | null;
    const teacherName = teacherPerson == null
      ? null
      : `${teacherPerson.first_name ?? ""} ${teacherPerson.last_name ?? ""}`
        .trim();
    const groupId = cls?.group_id == null ? null : Number(cls.group_id);

    const attachments = await this.attachmentRows(
      "assignment_files",
      "assignment_id",
      id,
    );
    const { data: enrollmentRows } = groupId == null
      ? { data: [] as unknown[] }
      : await this.repository.enrollmentsByGroupId(groupId);
    const { data: submissionRows } =
      await this.repository.submissionsByAssignmentId(id);
    const cali = await this.repository.taskStatusId("CALI").catch(() => null);
    const submissions = (submissionRows ?? []) as Array<Record<string, unknown>>;
    const gradedCount = cali == null
      ? 0
      : submissions.filter((item) => Number(item.task_status_id) === cali)
        .length;

    return {
      id: String(row.id),
      classId: Number(row.class_id),
      subjectName: String(subject),
      groupName: String(group),
      title: String(row.title ?? ""),
      description: row.description ?? null,
      instructions: row.instructions ?? null,
      assignedAt: String(
        row.assigned_at ?? row.created_at ?? new Date().toISOString(),
      ),
      dueAt: String(row.due_at ?? new Date().toISOString()),
      kind: "homework",
      maxScore: Number(row.max_score ?? 100),
      allowLate: Boolean(row.allow_late),
      published: row.published == null ? true : Boolean(row.published),
      attachments,
      teacherName: teacherName && teacherName.length > 0 ? teacherName : null,
      totalStudents: enrollmentRows?.length ?? 0,
      submittedCount: submissions.length,
      gradedCount,
    };
  }

  private async hydrateSubmission(id: number) {
    const row = await this.repository.findSubmissionForHydration(id);
    const cali = await this.repository.taskStatusId("CALI").catch(() => null);
    const isGraded = cali != null && Number(row.task_status_id) === cali;
    const isLate = Boolean(row.is_late);
    const person = ((row.students as Record<string, unknown> | null)?.persons ??
      null) as Record<string, unknown> | null;
    const studentName =
      `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim() ||
      "Estudiante";
    const attachments = await this.attachmentRows(
      "submission_files",
      "submission_id",
      id,
    );

    let score: number | null = null;
    let feedback: string | null = null;
    if (isGraded) {
      const evaluation = await this.repository.findEvaluationByAssignmentId(
        row.assignment_id,
      );
      if (evaluation) {
        const grade = await this.repository.findGrade(
          evaluation.id,
          row.student_id,
        );
        score = grade?.score == null ? null : Number(grade.score);
        feedback = grade?.notes ?? null;
      }
    }

    return {
      id: String(row.id),
      assignmentId: String(row.assignment_id),
      studentId: Number(row.student_id),
      studentName,
      status: isGraded ? "graded" : isLate ? "late" : "submitted",
      submittedAt: row.submitted_at ?? null,
      studentNotes: row.student_notes ?? null,
      attachments,
      score,
      feedback,
    };
  }
}

export const assignmentsService = new AssignmentsService();
