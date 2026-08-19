import { expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class AuthRepository {
  async getAuthUser(token: string) {
    return db.auth.getUser(token);
  }

  async findAppUserByAuthUserId(authUserId: string) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("users")
        .select(
          "id, institution_id, person_id, full_name, user_roles(roles(code))",
        )
        .eq("auth_user_id", authUserId)
        .eq("active", true)
        .is("deleted_at", null)
        .single(),
      "Usuario de aplicación no encontrado.",
    );
  }

  async findTeacherIdByPerson(institutionId: number, personId: number) {
    const { data } = await db
      .from("teachers")
      .select("id")
      .eq("person_id", personId)
      .eq("institution_id", institutionId)
      .eq("active", true)
      .maybeSingle();
    return data == null ? null : Number(data.id);
  }

  async findStudentIdByPerson(institutionId: number, personId: number) {
    const { data } = await db
      .from("students")
      .select("id")
      .eq("person_id", personId)
      .eq("institution_id", institutionId)
      .eq("active", true)
      .maybeSingle();
    return data == null ? null : Number(data.id);
  }

  async findParentIdByPerson(institutionId: number, personId: number) {
    const { data } = await db
      .from("parents")
      .select("id")
      .eq("person_id", personId)
      .eq("institution_id", institutionId)
      .maybeSingle();
    return data == null ? null : Number(data.id);
  }

  async findClassForPermission(institutionId: number, classId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("classes")
        .select("id, group_id, teacher_id, institution_id")
        .eq("id", classId)
        .eq("institution_id", institutionId)
        .eq("active", true)
        .single(),
      "Clase no encontrada.",
    );
  }

  async findAssignmentForPermission(institutionId: number, assignmentId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("assignments")
        .select("id, class_id, institution_id, classes(teacher_id, group_id)")
        .eq("id", assignmentId)
        .eq("institution_id", institutionId)
        .is("deleted_at", null)
        .single(),
      "Tarea no encontrada.",
    );
  }

  async findClassGroupId(classId: number) {
    return expectSingle<Record<string, unknown>>(
      db.from("classes").select("group_id").eq("id", classId).single(),
      "Clase no encontrada.",
    );
  }

  async studentEnrollmentExists(
    institutionId: number,
    studentId: number,
    groupId: number,
  ) {
    const { data } = await db
      .from("enrollments")
      .select("id")
      .eq("student_id", studentId)
      .eq("group_id", groupId)
      .eq("institution_id", institutionId)
      .limit(1);
    return Array.isArray(data) && data.length > 0;
  }

  async parentStudentLinkExists(parentId: number, studentId: number) {
    const { data } = await db
      .from("parent_students")
      .select("id")
      .eq("parent_id", parentId)
      .eq("student_id", studentId)
      .limit(1);
    return Array.isArray(data) && data.length > 0;
  }
}

export const authRepository = new AuthRepository();
