import {
  AppContext,
  assertStudentEnrolledInClass,
  assertTeacherCanUseAssignment,
  assertTeacherCanUseClass,
  currentTeacherId,
  isAdmin,
  normalizeStudentId,
  requireRole,
} from "../shared/auth.ts";
import { expectSingle } from "../shared/db.ts";
import { mapAttachment } from "../shared/files.ts";
import { HttpError } from "../shared/http.ts";
import { db } from "../shared/supabase.ts";
import {
  asList,
  asRecord,
  dateOnly,
  optionalId,
  optionalString,
  requiredDate,
  requiredId,
  requiredNumber,
  requiredString,
} from "../shared/validators.ts";

async function currentAcademicPeriodId(institutionId: number, dueAt: Date) {
  const target = dateOnly(dueAt);
  const { data } = await db
    .from("academic_periods")
    .select("id")
    .eq("institution_id", institutionId)
    .lte("start_date", target)
    .gte("end_date", target)
    .order("display_order")
    .limit(1)
    .maybeSingle();
  return data == null ? null : Number(data.id);
}

async function taskStatusId(code: string) {
  const row = await expectSingle<Record<string, unknown>>(
    db.from("catalog_task_statuses").select("id").eq("code", code).single(),
    `Estado de tarea ${code} no configurado.`,
  );
  return Number(row.id);
}

async function attachmentRows(
  table: "assignment_files" | "submission_files",
  column: string,
  id: number,
) {
  const { data, error } = await db
    .from(table)
    .select("files(id, original_name, url, size_bytes, mime_type)")
    .eq(column, id);
  if (error) throw new HttpError(400, error.message, "db_error");
  return (data ?? [])
    .map((row) =>
      (row as Record<string, unknown>).files as Record<string, unknown> | null
    )
    .filter((file): file is Record<string, unknown> => file != null)
    .map(mapAttachment);
}

async function linkAttachments(
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

    const { data: file } = await db
      .from("files")
      .select("id")
      .eq("id", fileId)
      .eq("institution_id", ctx.institutionId)
      .is("deleted_at", null)
      .maybeSingle();
    if (!file) {
      throw new HttpError(
        400,
        "Uno de los adjuntos no pertenece a esta institución.",
        "validation_error",
      );
    }

    if (options.assignmentId != null) {
      const result = await db
        .from("assignment_files")
        .upsert({ assignment_id: options.assignmentId, file_id: fileId }, {
          onConflict: "assignment_id,file_id",
          ignoreDuplicates: true,
        });
      if (result.error) {
        throw new HttpError(400, result.error.message, "db_error");
      }
    }
    if (options.submissionId != null) {
      const result = await db
        .from("submission_files")
        .upsert({ submission_id: options.submissionId, file_id: fileId }, {
          onConflict: "submission_id,file_id",
          ignoreDuplicates: true,
        });
      if (result.error) {
        throw new HttpError(400, result.error.message, "db_error");
      }
    }
  }
}

async function hydrateAssignment(id: number) {
  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("assignments")
      .select(
        "id, class_id, title, description, instructions, assigned_at, due_at, max_score, allow_late, published, created_at, " +
          "classes(id, group_id, subjects(name), groups(name), teachers(persons(first_name, last_name)))",
      )
      .eq("id", id)
      .single(),
    "Tarea no encontrada.",
  );

  const cls = row.classes as Record<string, unknown> | null;
  const subject = (cls?.subjects as Record<string, unknown> | null)?.name ??
    "Materia";
  const group = (cls?.groups as Record<string, unknown> | null)?.name ??
    "Grupo";
  const teacherPerson =
    ((cls?.teachers as Record<string, unknown> | null)?.persons ??
      null) as Record<string, unknown> | null;
  const teacherName = teacherPerson == null
    ? null
    : `${teacherPerson.first_name ?? ""} ${teacherPerson.last_name ?? ""}`
      .trim();
  const groupId = cls?.group_id == null ? null : Number(cls.group_id);

  const attachments = await attachmentRows(
    "assignment_files",
    "assignment_id",
    id,
  );
  const { data: enrollmentRows } = groupId == null
    ? { data: [] as unknown[] }
    : await db.from("enrollments").select("id").eq("group_id", groupId);
  const { data: submissionRows } = await db
    .from("submissions")
    .select("id, task_status_id")
    .eq("assignment_id", id);
  const cali = await taskStatusId("CALI").catch(() => null);
  const submissions = submissionRows ?? [];
  const gradedCount = cali == null
    ? 0
    : submissions.filter((item) =>
      Number((item as Record<string, unknown>).task_status_id) === cali
    ).length;

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

async function hydrateSubmission(id: number) {
  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("submissions")
      .select(
        "id, assignment_id, student_id, submitted_at, student_notes, is_late, task_status_id, students(persons(first_name, last_name))",
      )
      .eq("id", id)
      .single(),
    "Entrega no encontrada.",
  );
  const cali = await taskStatusId("CALI").catch(() => null);
  const isGraded = cali != null && Number(row.task_status_id) === cali;
  const isLate = Boolean(row.is_late);
  const person = ((row.students as Record<string, unknown> | null)?.persons ??
    null) as Record<string, unknown> | null;
  const studentName =
    `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim() ||
    "Estudiante";
  const attachments = await attachmentRows(
    "submission_files",
    "submission_id",
    id,
  );

  let score: number | null = null;
  let feedback: string | null = null;
  if (isGraded) {
    const { data: evaluation } = await db
      .from("evaluations")
      .select("id")
      .eq("assignment_id", row.assignment_id)
      .limit(1)
      .maybeSingle();
    if (evaluation) {
      const { data: grade } = await db
        .from("grades")
        .select("score, notes")
        .eq("evaluation_id", evaluation.id)
        .eq("student_id", row.student_id)
        .maybeSingle();
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

export async function teacherClasses(ctx: AppContext) {
  requireRole(ctx, ["teacher"]);
  let query = db
    .from("classes")
    .select("id, group_id, subjects(name), groups(name)")
    .eq("institution_id", ctx.institutionId)
    .eq("active", true);
  if (!isAdmin(ctx)) {
    const teacherId = await currentTeacherId(ctx);
    if (teacherId == null) return [];
    query = query.eq("teacher_id", teacherId);
  }

  const { data, error } = await query.order("id");
  if (error) throw new HttpError(400, error.message, "db_error");
  const rows = data ?? [];
  const groupIds = [
    ...new Set(
      rows.map((row) => Number((row as Record<string, unknown>).group_id))
        .filter(Number.isFinite),
    ),
  ];
  const studentCounts = new Map<number, number>();
  if (groupIds.length > 0) {
    const { data: enrollments } = await db
      .from("enrollments")
      .select("group_id")
      .in("group_id", groupIds)
      .eq("institution_id", ctx.institutionId);
    for (const enrollment of enrollments ?? []) {
      const groupId = Number((enrollment as Record<string, unknown>).group_id);
      studentCounts.set(groupId, (studentCounts.get(groupId) ?? 0) + 1);
    }
  }

  return rows.map((item) => {
    const row = item as Record<string, unknown>;
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

export async function upsertAssignment(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
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

  const classRow = await assertTeacherCanUseClass(ctx, classId);
  const assignmentId = optionalId(payload.assignmentId);
  if (assignmentId != null) {
    await assertTeacherCanUseAssignment(ctx, assignmentId);
  }
  const teacherId = await currentTeacherId(ctx);
  const academicPeriodId = await currentAcademicPeriodId(
    ctx.institutionId,
    dueAt,
  );
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
    assigned_at: new Date().toISOString(),
    created_by: teacherId,
    updated_at: new Date().toISOString(),
  };

  const row = assignmentId == null
    ? await expectSingle<Record<string, unknown>>(
      db.from("assignments").insert(dbPayload).select("id").single(),
      "No se pudo crear la tarea.",
    )
    : await expectSingle<Record<string, unknown>>(
      db
        .from("assignments")
        .update(dbPayload)
        .eq("id", assignmentId)
        .eq("institution_id", ctx.institutionId)
        .select("id")
        .single(),
      "No se pudo actualizar la tarea.",
    );

  await linkAttachments(ctx, {
    attachments: payload.attachments,
    assignmentId: Number(row.id),
  });
  return { assignment: await hydrateAssignment(Number(row.id)) };
}

export async function deleteAssignment(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  const id = requiredId(payload.id, "Tarea");
  await assertTeacherCanUseAssignment(ctx, id);
  const { error } = await db
    .from("assignments")
    .update({
      deleted_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", id)
    .eq("institution_id", ctx.institutionId);
  if (error) throw new HttpError(400, error.message, "db_error");
  return { ok: true };
}

export async function publishAssignment(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  const id = requiredId(payload.id, "Tarea");
  await assertTeacherCanUseAssignment(ctx, id);
  const { error } = await db
    .from("assignments")
    .update({
      published: Boolean(payload.published),
      updated_at: new Date().toISOString(),
    })
    .eq("id", id)
    .eq("institution_id", ctx.institutionId);
  if (error) throw new HttpError(400, error.message, "db_error");
  return { ok: true };
}

export async function submitAssignment(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  requireRole(ctx, ["student"]);
  const assignmentId = requiredId(payload.assignmentId, "Tarea");
  const studentId = await normalizeStudentId(ctx, payload.studentId);
  const assignment = await expectSingle<Record<string, unknown>>(
    db
      .from("assignments")
      .select("id, class_id, due_at, allow_late, published, classes(group_id)")
      .eq("id", assignmentId)
      .eq("institution_id", ctx.institutionId)
      .is("deleted_at", null)
      .single(),
    "Tarea no encontrada.",
  );
  if (!assignment.published) {
    throw new HttpError(
      400,
      "La tarea aún no está publicada.",
      "validation_error",
    );
  }
  const groupId = Number(
    (assignment.classes as Record<string, unknown> | null)?.group_id,
  );
  await assertStudentEnrolledInClass(
    ctx.institutionId,
    studentId,
    Number(assignment.class_id),
    groupId,
  );

  const dueAt = assignment.due_at == null
    ? null
    : new Date(String(assignment.due_at));
  if (
    dueAt != null && !assignment.allow_late &&
    Date.now() > dueAt.getTime()
  ) {
    throw new HttpError(
      400,
      "Esta tarea ya venció y no permite entregas tarde.",
      "validation_error",
    );
  }

  const statusId = await taskStatusId("ENTR");
  const now = new Date().toISOString();
  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("submissions")
      .upsert({
        institution_id: ctx.institutionId,
        assignment_id: assignmentId,
        student_id: studentId,
        submitted_at: now,
        student_notes: optionalString(payload.notes),
        task_status_id: statusId,
        updated_at: now,
      }, { onConflict: "assignment_id,student_id" })
      .select("id")
      .single(),
    "No se pudo guardar la entrega.",
  );
  await linkAttachments(ctx, {
    attachments: payload.attachments,
    submissionId: Number(row.id),
  });
  return { submission: await hydrateSubmission(Number(row.id)) };
}

export async function gradeSubmission(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  requireRole(ctx, ["teacher"]);
  const submissionId = requiredId(payload.submissionId, "Entrega");
  const score = requiredNumber(payload.score, "Nota");
  if (score < 0) {
    throw new HttpError(
      400,
      "La nota no puede ser negativa.",
      "validation_error",
    );
  }
  const submission = await expectSingle<Record<string, unknown>>(
    db
      .from("submissions")
      .select("id, assignment_id, assignments(class_id)")
      .eq("id", submissionId)
      .eq("institution_id", ctx.institutionId)
      .single(),
    "Entrega no encontrada.",
  );
  const classId = Number(
    (submission.assignments as Record<string, unknown> | null)?.class_id,
  );
  await assertTeacherCanUseClass(ctx, classId);
  const { error } = await db.rpc("grade_submission", {
    p_submission_id: submissionId,
    p_score: score,
    p_feedback: optionalString(payload.feedback),
  });
  if (error) throw new HttpError(400, error.message, "db_error");
  return { submission: await hydrateSubmission(submissionId) };
}
