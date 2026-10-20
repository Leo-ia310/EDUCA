import { assertNoDbError, expectSingle } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { supabaseAdmin, requireSupabaseServiceRole } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class AuthRepository {
  async classPermission(classId: number, permission: string) {
    const { data, error } = await db.rpc("class_permission", { p_class_id: classId, p_permission: permission });
    assertNoDbError(error);
    return data === true;
  }
  async getAuthUser(token: string) {
    return db.auth.getUser(token);
  }

  async requestContext(authUserId: string, sessionId: string, windowMs: number, limit: number) {
    const {data, error} = await requireSupabaseServiceRole().rpc("backend_request_context", {
      p_auth_user_id: authUserId, p_session_id: sessionId, p_window_ms: windowMs, p_limit: limit,
    });
    if (error) {
      if (error.code === "28000") throw new HttpError(401,"Sesión inválida o revocada.","unauthorized");
      if (error.code === "42501") throw new HttpError(403,
        error.details === "two_factor_required" ? "Completa la verificación de seguridad e inicia sesión nuevamente." : "Cuenta no disponible o sin roles asignados.",
        error.details === "two_factor_required" ? "two_factor_required" : "forbidden");
      throw new HttpError(503,"No se pudo verificar tu acceso. Intenta nuevamente.","authorization_unavailable");
    }
    if (data == null) throw new HttpError(503,"No se pudo verificar tu acceso.","authorization_unavailable");
    return data as Record<string, unknown>;
  }

  async findTeacherIdByPerson(institutionId: number, personId: number) {
    const { data , error: queryError_1} = await db
      .from("teachers")
      .select("id")
      .eq("person_id", personId)
      .eq("institution_id", institutionId)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(queryError_1);
    return data == null ? null : Number(data.id);
  }

  async findStudentIdByPerson(institutionId: number, personId: number) {
    const { data , error: queryError_2} = await db
      .from("students")
      .select("id")
      .eq("person_id", personId)
      .eq("institution_id", institutionId)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(queryError_2);
    return data == null ? null : Number(data.id);
  }

  async findParentIdByPerson(institutionId: number, personId: number) {
    const { data , error: queryError_3} = await db
      .from("parents")
      .select("id")
      .eq("person_id", personId)
      .eq("institution_id", institutionId)
      .maybeSingle();
    assertNoDbError(queryError_3);
    return data == null ? null : Number(data.id);
  }

  /**
   * La consulta corre con el token del usuario (RLS): una clase que un maestro no puede ver llega vacía.
   * Se responde 403 en vez de un 400 de BD, sin distinguir "no existe" de "no es tuya".
   */
  async findClassForPermission(institutionId: number, classId: number) {
    const { data, error } = await db
      .from("classes")
      .select("id, group_id, teacher_id, institution_id, academic_year_id")
      .eq("id", classId)
      .eq("institution_id", institutionId)
      .eq("active", true)
      .maybeSingle();
    assertNoDbError(error);
    if (data == null) throw new HttpError(403, "No tienes acceso a esta clase.", "forbidden");
    return data as Record<string, unknown>;
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

  async findClassGroupId(institutionId: number, classId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("classes")
        .select("group_id")
        .eq("institution_id", institutionId)
        .eq("id", classId)
        .single(),
      "Clase no encontrada.",
    );
  }

  async studentEnrollmentExists(
    institutionId: number,
    studentId: number,
    groupId: number,
  ) {
    const { data , error: queryError_4} = await db
      .from("enrollments")
      .select("id")
      .eq("student_id", studentId)
      .eq("group_id", groupId)
      .eq("institution_id", institutionId)
      .limit(1);
    assertNoDbError(queryError_4);
    return Array.isArray(data) && data.length > 0;
  }

  async parentStudentLinkExists(
    institutionId: number,
    parentId: number,
    studentId: number,
  ) {
    const { data , error: queryError_5} = await db
      .from("parent_students")
      .select("id, parents!inner(institution_id), students!inner(institution_id)")
      .eq("parent_id", parentId)
      .eq("student_id", studentId)
      .eq("parents.institution_id", institutionId)
      .eq("students.institution_id", institutionId)
      .limit(1);
    assertNoDbError(queryError_5);
    return Array.isArray(data) && data.length > 0;
  }
}

export const authRepository = new AuthRepository();

