import { expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";
import { dateOnly } from "../validators/common.validators";

const db = supabaseAdmin as any;

export class AssignmentsRepository {
  async currentAcademicPeriodId(institutionId: number, dueAt: Date) {
    const { data } = await db
      .from("academic_periods")
      .select("id")
      .eq("institution_id", institutionId)
      .lte("start_date", dateOnly(dueAt))
      .gte("end_date", dateOnly(dueAt))
      .order("display_order")
      .limit(1)
      .maybeSingle();
    return data == null ? null : Number(data.id);
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
    const { data } = await db
      .from("files")
      .select("id")
      .eq("id", fileId)
      .eq("institution_id", institutionId)
      .is("deleted_at", null)
      .maybeSingle();
    return data;
  }

  async linkAssignmentFile(assignmentId: number, fileId: number) {
    return db
      .from("assignment_files")
      .upsert({ assignment_id: assignmentId, file_id: fileId }, {
        onConflict: "assignment_id,file_id",
        ignoreDuplicates: true,
      });
  }

  async linkSubmissionFile(submissionId: number, fileId: number) {
    return db
      .from("submission_files")
      .upsert({ submission_id: submissionId, file_id: fileId }, {
        onConflict: "submission_id,file_id",
        ignoreDuplicates: true,
      });
  }

  async findAssignmentForHydration(id: number) {
    return expectSingle<Record<string, unknown>>(
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
  }

  async enrollmentsByGroupId(groupId: number) {
    return db.from("enrollments").select("id").eq("group_id", groupId);
  }

  async submissionsByAssignmentId(assignmentId: number) {
    return db
      .from("submissions")
      .select("id, task_status_id")
      .eq("assignment_id", assignmentId);
  }

  async findSubmissionForHydration(id: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("submissions")
        .select(
          "id, assignment_id, student_id, submitted_at, student_notes, is_late, task_status_id, students(persons(first_name, last_name))",
        )
        .eq("id", id)
        .single(),
      "Entrega no encontrada.",
    );
  }

  async findEvaluationByAssignmentId(assignmentId: unknown) {
    const { data } = await db
      .from("evaluations")
      .select("id")
      .eq("assignment_id", assignmentId)
      .limit(1)
      .maybeSingle();
    return data;
  }

  async findGrade(evaluationId: unknown, studentId: unknown) {
    const { data } = await db
      .from("grades")
      .select("score, notes")
      .eq("evaluation_id", evaluationId)
      .eq("student_id", studentId)
      .maybeSingle();
    return data;
  }

  async teacherClassRows(institutionId: number, teacherId: number | null) {
    let query = db
      .from("classes")
      .select("id, group_id, subjects(name), groups(name)")
      .eq("institution_id", institutionId)
      .eq("active", true);
    if (teacherId != null) {
      query = query.eq("teacher_id", teacherId);
    }
    return query.order("id");
  }

  async enrollmentsByGroupIds(institutionId: number, groupIds: number[]) {
    return db
      .from("enrollments")
      .select("group_id")
      .in("group_id", groupIds)
      .eq("institution_id", institutionId);
  }

  async insertAssignment(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("assignments").insert(payload).select("id").single(),
      "No se pudo crear la tarea.",
    );
  }

  async updateAssignment(
    assignmentId: number,
    institutionId: number,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("assignments")
        .update(payload)
        .eq("id", assignmentId)
        .eq("institution_id", institutionId)
        .select("id")
        .single(),
      "No se pudo actualizar la tarea.",
    );
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
