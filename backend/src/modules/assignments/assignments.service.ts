import { randomUUID } from 'node:crypto';
import { decodeAssignmentCursor, encodeAssignmentCursor, AssignmentCursor } from "./assignment-cursor";
import { collaborationService } from "../collaborations/collaborations.service";
import { assertNoDbError } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { mapAttachment } from "../../lib/files";
import {
  asList,
  asRecord,
  optionalId,
  optionalString,
  requiredDate,
  requiredId,
  requiredNumber,
  requiredString,
} from "../../validators/common.validators";
import {
  assignmentsRepository,
  AssignmentsRepository,
} from "./assignments.repository";
import type { AppContext } from "../../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "../../services/permissions.service";

export class AssignmentsService {
  constructor(
    private readonly repository: AssignmentsRepository = assignmentsRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async teacherClasses(ctx: AppContext) {
    this.permissions.requireRole(ctx, ["teacher"]);
    if (!this.permissions.isAdmin(ctx) && await this.permissions.currentTeacherId(ctx) == null) return [];

    const [workspace, result] = await Promise.all([
      collaborationService.workspace(ctx), this.repository.teacherClassRows(ctx.institutionId),
    ]);
    const access = new Map<number, any>((workspace.classes ?? []).map((item: any) => [Number(item.classId), item]));
    assertNoDbError(result.error);
    const rows = result.data;
    const studentCounts = await this.repository.classEnrollmentCounts(rows.map(row => Number(row.id)));

    return rows.map((row) => {
      const groupId = Number(row.group_id);
      return {
        classId: Number(row.id),
        isOwner: access.get(Number(row.id))?.isOwner ?? false,
        permissions: access.get(Number(row.id))?.permissions ?? [],
        groupId,
        subjectName: String(
          (row.subjects as Record<string, unknown> | null)?.name ?? "Materia",
        ),
        groupName: String(
          (row.groups as Record<string, unknown> | null)?.name ?? "Grupo",
        ),
        startTime: "",
        endTime: "",
        studentCount: studentCounts.get(Number(row.id)) ?? 0,
      };
    });
  }

  async studentAssignments(ctx: AppContext, query: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["parent", "student"]);
    const studentId = await this.permissions.normalizeStudentId(ctx, query.studentId ?? query.student_id);
    return this.feed(query, studentId);
  }

  private async feed(query: Record<string, unknown>, studentId: number | null) {
    const limit = query.limit == null ? 50 : requiredId(query.limit, "Límite");
    if (limit > 100) throw new HttpError(400, "Máximo 100 tareas por página.", "validation_error");
    const cursor = decodeAssignmentCursor(query.cursor);
    const onlyOpen = query.onlyOpen ?? false;
    if (![true, false, "true", "false"].includes(onlyOpen as boolean)) {
      throw new HttpError(400, "Filtro de tareas inválido.", "validation_error");
    }
    const kinds = optionalString(query.kinds, 100)?.split(",").filter(Boolean) ?? null;
    if (kinds?.some(kind => !["homework", "exam", "project", "quiz", "presentation"].includes(kind))) {
      throw new HttpError(400, "Tipo de tarea inválido.", "validation_error");
    }
    const data = await this.repository.feed({
      p_student_id: studentId, p_class_id: optionalId(query.classId ?? query.class_id),
      p_search: optionalString(query.search, 150), p_subject: optionalString(query.subject, 100),
      p_only_open: onlyOpen === true || onlyOpen === "true", p_kinds: kinds,
      p_after_due_at: cursor?.dueAt ?? null, p_after_id: cursor?.id ?? null, p_limit: limit,
    });
    return { assignments: data.assignments, nextCursor: encodeAssignmentCursor(data.nextCursor as AssignmentCursor | null) };
  }

  /** Tareas visibles para el maestro (RLS limita a sus clases y colaboraciones), con conteos de entregas. */
  async listAssignments(ctx: AppContext, query: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    return this.feed(query, null);
  }

  /** Alumnos del salón con el estado de su entrega, nota y comentarios (permiso `assignments.review`). */
  async assignmentSubmissions(ctx: AppContext, idRaw: unknown) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const id = requiredId(idRaw, "Tarea");
    await this.permissions.assertTeacherCanUseAssignment(ctx, id, "assignments.review");
    const row: any = await this.repository.findAssignmentForHydration(id, ctx.institutionId);
    const groupId = Number(row.classes?.group_id);
    const [students, allSubs, graded, evaluation] = await Promise.all([
      this.repository.activeStudentsOfGroup(ctx.institutionId, groupId, row.classes?.academic_year_id == null ? null : Number(row.classes.academic_year_id)),
      this.repository.submissionsOfAssignment(ctx.institutionId, id),
      this.repository.taskStatusId("CALI").catch(() => null),
      this.repository.findEvaluationByAssignmentId(ctx.institutionId, id),
    ]);
    const roster = new Set(students.map(student => Number(student.student_id)));
    const subs = allSubs.filter(submission => roster.has(Number(submission.student_id)));
    const grades = evaluation ? await this.repository.gradesOfEvaluation(ctx.institutionId, evaluation.id) : [];
    const gradeOf = new Map(grades.map((g) => [Number(g.student_id), g]));
    const files = await this.repository.submissionAttachments(subs.map((s) => Number(s.id)));
    const filesOf = new Map<number, ReturnType<typeof mapAttachment>[]>();
    for (const f of files) {
      if (!f.files) continue;
      const list = filesOf.get(Number(f.submission_id)) ?? [];
      list.push(mapAttachment(f.files as Record<string, unknown>));
      filesOf.set(Number(f.submission_id), list);
    }
    const subOf = new Map(subs.map((s) => [Number(s.student_id), s]));
    const counts = new Map([[id, {
      submitted: subs.length,
      graded: graded == null ? 0 : subs.filter((s) => Number(s.task_status_id) === graded).length,
    }]]);
    const assignmentFiles = await this.attachmentRows("assignment_files", "assignment_id", id);
    return {
      assignment: { ...mapListed(row, new Map([[groupId, students.length]]), counts), attachments: assignmentFiles },
      students: students
        .map((e: any) => {
          const person = e.students?.persons;
          const name = `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim() || "Estudiante";
          const sub: any = subOf.get(Number(e.student_id));
          const isGraded = !!sub && graded != null && Number(sub.task_status_id) === graded;
          const grade = isGraded ? gradeOf.get(Number(e.student_id)) : undefined;
          return {
            studentId: String(e.student_id),
            name,
            submissionId: sub ? String(sub.id) : null,
            status: !sub || sub.catalog_task_statuses?.code === "PEND" ? "pending" : isGraded ? "graded" : sub.is_late ? "late" : "submitted",
            submittedAt: sub?.submitted_at ?? null,
            notes: sub?.student_notes ?? null,
            attachments: sub ? (filesOf.get(Number(sub.id)) ?? []) : [],
            score: grade?.score == null ? null : Number(grade.score),
            feedback: grade?.notes ?? null,
          };
        })
        .sort((a, b) => a.name.localeCompare(b.name, "es")),
    };
  }

  async upsertAssignment(ctx: AppContext, payload: Record<string, unknown>) {
    const classId = requiredId(payload.classId, "Clase");
    const title = requiredString(payload.title, "Título", 200);
    const dueAt = requiredDate(payload.dueAt, "Fecha de entrega");
    const maxScore = requiredNumber(payload.maxScore, "Puntaje máximo");
    const kind = optionalString(payload.kind, 20);
    if (kind != null && !["homework", "exam", "project", "quiz", "presentation"].includes(kind)) {
      throw new HttpError(400, "Tipo de tarea inválido.", "validation_error");
    }
    if (maxScore <= 0) {
      throw new HttpError(
        400,
        "El puntaje máximo debe ser mayor que cero.",
        "validation_error",
      );
    }

    this.permissions.requireRole(ctx, ['teacher']);
    const assignmentId = optionalId(payload.assignmentId);
    const key = optionalString(payload.idempotencyKey);
    if (key != null && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(key)) {
      throw new HttpError(400, 'Clave de operación inválida.', 'validation_error');
    }
    if (payload.attachments != null && (!Array.isArray(payload.attachments) || payload.attachments.length > 100)) {
      throw new HttpError(400, 'Adjuntos inválidos; máximo 100 archivos.', 'validation_error');
    }
    const fileIds = payload.attachments == null ? null : [...new Set(asList(payload.attachments)
      .map(item => requiredId(asRecord(item).id, 'Archivo')))].sort((a, b) => a - b);
    const dbPayload = {
      class_id: classId,
      title,
      ...(kind == null ? {} : { kind }),
      description: optionalString(payload.description),
      instructions: optionalString(payload.instructions),
      due_at: dueAt.toISOString(),
      max_score: maxScore,
      allow_late: Boolean(payload.allowLate),
      published: payload.published == null ? true : Boolean(payload.published),
    };
    return { assignment: await this.repository.writeAssignment(assignmentId, dbPayload, fileIds, key ?? randomUUID()) };
  }

  /** Quita un adjunto de la tarea (solo el vínculo; el archivo queda en el almacenamiento). */
  async removeAttachment(ctx: AppContext, assignmentIdRaw: unknown, fileIdRaw: unknown) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const assignmentId = requiredId(assignmentIdRaw, "Tarea");
    const fileId = requiredId(fileIdRaw, "Archivo");
    await this.permissions.assertTeacherCanUseAssignment(ctx, assignmentId, "assignments.create");
    await this.repository.unlinkAssignmentFile(assignmentId, fileId);
    return { ok: true, attachments: await this.attachmentRows("assignment_files", "assignment_id", assignmentId) };
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

    // Una entrega ya calificada es definitiva: reentregar la devolvería a «entregada» y ocultaría su nota.
    const previous = await this.repository.findSubmissionOf(ctx.institutionId, assignmentId, studentId);
    const gradedStatusId = await this.repository.taskStatusId("CALI").catch(() => null);
    if (previous != null && gradedStatusId != null && Number(previous.task_status_id) === gradedStatusId) {
      throw new HttpError(409, "Esta tarea ya fue calificada: no se puede volver a entregar.", "already_graded");
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
    return { submission: await this.hydrateSubmission(ctx, Number(row.id)) };
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
    await this.permissions.assertTeacherCanUseClass(ctx, classId, "assignments.grade");
    const { error } = await this.repository.gradeSubmissionRpc(
      submissionId,
      score,
      optionalString(payload.feedback),
    );
    assertNoDbError(error);
    return { submission: await this.hydrateSubmission(ctx, submissionId) };
  }

  private async linkAttachments(
    ctx: AppContext,
    options: {
      attachments: unknown;
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

  private async hydrateSubmission(ctx: AppContext, id: number) {
    const row = await this.repository.findSubmissionForHydration(
      id,
      ctx.institutionId,
    );
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
        ctx.institutionId,
        row.assignment_id,
      );
      if (evaluation) {
        const grade = await this.repository.findGrade(
          ctx.institutionId,
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

function mapListed(
  r: any,
  studentsByGroup: Map<number, number>,
  counts: Map<number, { submitted: number; graded: number }>,
) {
  const c = counts.get(Number(r.id)) ?? { submitted: 0, graded: 0 };
  return {
    id: String(r.id),
    classId: String(r.class_id),
    subjectName: String(r.classes?.subjects?.name ?? "Materia"),
    groupName: String(r.classes?.groups?.name ?? "Grupo"),
    title: String(r.title ?? ""),
    description: r.description ?? null,
    instructions: r.instructions ?? null,
    assignedAt: String(r.assigned_at ?? r.created_at ?? ""),
    dueAt: String(r.due_at ?? ""),
    maxScore: Number(r.max_score ?? 100),
    allowLate: Boolean(r.allow_late),
    published: r.published == null ? true : Boolean(r.published),
    totalStudents: studentsByGroup.get(Number(r.classes?.group_id)) ?? 0,
    submittedCount: c.submitted,
    gradedCount: c.graded,
  };
}

