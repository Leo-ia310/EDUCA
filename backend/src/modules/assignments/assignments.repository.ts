import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";
import { readAllPages } from "../../lib/read-all";

const db = supabaseAdmin as any;

export class AssignmentsRepository {
  async writeAssignment(id: number | null, data: Record<string, unknown>, fileIds: number[] | null, key: string) {
    return expectSingle<Record<string, unknown>>(db.rpc('assignment_write', {
      p_id: id, p_data: data, p_file_ids: fileIds, p_key: key,
    }), 'No se pudo guardar la tarea.');
  }
  async feed(parameters: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(db.rpc("assignment_feed", parameters), "No se pudieron cargar las tareas.");
  }
  async taskStatusId(code: string) {
    const row = await expectSingle<Record<string, unknown>>(
      db.from("catalog_task_statuses").select("id").eq("code", code).single(),
      `Estado de tarea ${code} no configurado.`,
    );
    return Number(row.id);
  }

  async attachmentRows(
    table: "assignment_files" | "submission_files",
    column: string,
    id: number,
  ) {
    return db
      .from(table)
      .select("files(id, original_name, url, size_bytes, mime_type)")
      .eq(column, id);
  }

  async findInstitutionFile(institutionId: number, fileId: number) {
    const { data , error: queryError_2} = await db
      .from("files")
      .select("id")
      .eq("id", fileId)
      .eq("institution_id", institutionId)
      .is("deleted_at", null)
      .maybeSingle();
    assertNoDbError(queryError_2);
    return data;
  }

  async linkSubmissionFile(submissionId: number, fileId: number) {
    return db
      .from("submission_files")
      .upsert({ submission_id: submissionId, file_id: fileId }, {
        onConflict: "submission_id,file_id",
        ignoreDuplicates: true,
      });
  }

  async findAssignmentForHydration(id: number, institutionId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("assignments")
        .select(
          "id, class_id, title, description, instructions, kind, assigned_at, due_at, max_score, allow_late, published, created_at, " +
            "classes(id, group_id, academic_year_id, subjects(name), groups(name), teachers(persons(first_name, last_name)))",
        )
        .eq("id", id)
        .eq("institution_id", institutionId)
        .single(),
      "Tarea no encontrada.",
    );
  }

  async findSubmissionForHydration(id: number, institutionId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("submissions")
        .select(
          "id, assignment_id, student_id, submitted_at, student_notes, is_late, task_status_id, students(persons(first_name, last_name))",
        )
        .eq("id", id)
        .eq("institution_id", institutionId)
        .single(),
      "Entrega no encontrada.",
    );
  }

  async findEvaluationByAssignmentId(
    institutionId: number,
    assignmentId: unknown,
  ) {
    const { data , error: queryError_3} = await db
      .from("evaluations")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("assignment_id", assignmentId)
      .limit(1)
      .maybeSingle();
    assertNoDbError(queryError_3);
    return data;
  }

  async findGrade(
    institutionId: number,
    evaluationId: unknown,
    studentId: unknown,
  ) {
    const { data , error: queryError_4} = await db
      .from("grades")
      .select("score, notes")
      .eq("institution_id", institutionId)
      .eq("evaluation_id", evaluationId)
      .eq("student_id", studentId)
      .maybeSingle();
    assertNoDbError(queryError_4);
    return data;
  }

  async teacherClassRows(institutionId: number) {
    const data = await readAllPages<Record<string, unknown>>((from, to) => db
      .from('classes').select('id, group_id, subjects(name), groups(name), academic_years!inner(is_current)')
      .eq('institution_id', institutionId).eq('active', true).eq('academic_years.is_current', true).order('id').range(from, to));
    return { data, error: null };
  }

  async classEnrollmentCounts(classIds: number[]) {
    const counts = new Map<number, number>();
    for (let i = 0; i < classIds.length; i += 200) {
      const { data, error } = await db.rpc('class_enrollment_counts', { p_class_ids: classIds.slice(i, i + 200) });
      assertNoDbError(error);
      for (const row of data ?? []) counts.set(Number(row.class_id), Number(row.total));
    }
    return counts;
  }

  async submissionsOfAssignment(institutionId: number, assignmentId: number) {
    return readAllPages<Record<string, unknown>>((from, to) => db
      .from("submissions")
      .select("id, student_id, submitted_at, student_notes, is_late, task_status_id, catalog_task_statuses(code)")
      .eq("institution_id", institutionId)
      .eq("assignment_id", assignmentId).order("id").range(from, to));
  }

  async activeStudentsOfGroup(institutionId: number, groupId: number, academicYearId: number | null) {
    const rows = await readAllPages<Record<string, unknown>>((from, to) => {
    let query = db
      .from("enrollments")
      .select("student_id, students!inner(id, active, persons(first_name, last_name)), academic_years!inner(is_current), catalog_enrollment_statuses!inner(code)")
      .eq("institution_id", institutionId)
      .eq("group_id", groupId)
      .eq("students.active", true).eq("catalog_enrollment_statuses.code", "ACT");
    query = academicYearId == null ? query.eq("academic_years.is_current", true) : query.eq("academic_year_id", academicYearId);
    return query.order("id").range(from, to);
    });
    return [...new Map(rows.map(row => [Number(row.student_id), row])).values()];
  }

  async gradesOfEvaluation(institutionId: number, evaluationId: unknown) {
    return readAllPages<Record<string, unknown>>((from, to) => db
      .from("grades")
      .select("student_id, score, notes")
      .eq("institution_id", institutionId)
      .eq("evaluation_id", evaluationId).order("id").range(from, to));
  }

  async submissionAttachments(submissionIds: number[]) {
    const rows: Record<string, unknown>[] = [];
    for (let i = 0; i < submissionIds.length; i += 150) {
    rows.push(...await readAllPages<Record<string, unknown>>((from, to) => db
      .from("submission_files")
      .select("submission_id, files(id, original_name, url, size_bytes, mime_type)")
      .in("submission_id", submissionIds.slice(i, i + 150)).order("id").range(from, to)));
    }
    return rows;
  }

  async softDeleteAssignment(
    assignmentId: number,
    institutionId: number,
    updatedAt: string,
  ) {
    return db
      .from("assignments")
      .update({ deleted_at: updatedAt, updated_at: updatedAt })
      .eq("id", assignmentId)
      .eq("institution_id", institutionId);
  }

  async updateAssignmentPublished(
    assignmentId: number,
    institutionId: number,
    published: boolean,
    updatedAt: string,
  ) {
    return db
      .from("assignments")
      .update({ published, updated_at: updatedAt })
      .eq("id", assignmentId)
      .eq("institution_id", institutionId);
  }

  async findAssignmentForSubmit(assignmentId: number, institutionId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("assignments")
        .select("id, class_id, due_at, allow_late, published, classes(group_id)")
        .eq("id", assignmentId)
        .eq("institution_id", institutionId)
        .is("deleted_at", null)
        .single(),
      "Tarea no encontrada.",
    );
  }

  async unlinkAssignmentFile(assignmentId: number, fileId: number) {
    const { error } = await db.from("assignment_files").delete().eq("assignment_id", assignmentId).eq("file_id", fileId);
    assertNoDbError(error);
  }

  async findSubmissionOf(institutionId: number, assignmentId: number, studentId: number) {
    const { data, error } = await db
      .from("submissions")
      .select("id, task_status_id")
      .eq("institution_id", institutionId)
      .eq("assignment_id", assignmentId)
      .eq("student_id", studentId)
      .maybeSingle();
    assertNoDbError(error);
    return (data ?? null) as Record<string, unknown> | null;
  }

  async upsertSubmission(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("submissions")
        .upsert(payload, { onConflict: "assignment_id,student_id" })
        .select("id")
        .single(),
      "No se pudo guardar la entrega.",
    );
  }

  async findSubmissionWithAssignment(
    submissionId: number,
    institutionId: number,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("submissions")
        .select("id, assignment_id, assignments(class_id)")
        .eq("id", submissionId)
        .eq("institution_id", institutionId)
        .single(),
      "Entrega no encontrada.",
    );
  }

  async gradeSubmissionRpc(
    submissionId: number,
    score: number,
    feedback: string | null,
  ) {
    return db.rpc("grade_submission", {
      p_submission_id: submissionId,
      p_score: score,
      p_feedback: feedback,
    });
  }
}

export const assignmentsRepository = new AssignmentsRepository();

