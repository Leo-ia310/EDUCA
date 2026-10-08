import { assertNoDbError, expectSingle } from "../lib/db";
import { requireSupabaseServiceRole } from "../lib/supabase";

export class AuthFlowRepository {
  async findInstitutionByCode(code: string) {
    const db = requireSupabaseServiceRole();
    const { data } = await db
      .from("institutions")
      .select("id, code, name, commercial_name, active")
      .ilike("code", code)
      .is("deleted_at", null)
      .maybeSingle();
    return data == null ? null : data as Record<string, unknown>;
  }

  async findLoginUser(institutionId: number, username: string) {
    const db = requireSupabaseServiceRole();
    const { data } = await db
      .from("users")
      .select(
        "id, auth_user_id, institution_id, person_id, username, email, full_name, active, locked_until, user_roles(roles(code, name))",
      )
      .eq("institution_id", institutionId)
      .ilike("username", username)
      .is("deleted_at", null)
      .maybeSingle();
    return data == null ? null : data as Record<string, unknown>;
  }

  async updateLastSignIn(userId: number) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("users")
      .update({ last_sign_in: new Date().toISOString(), failed_attempts: 0 })
      .eq("id", userId);
    assertNoDbError(error);
  }

  async incrementFailedAttempts(userId: number) {
    const db = requireSupabaseServiceRole();
    const user = await expectSingle<Record<string, unknown>>(
      db.from("users").select("failed_attempts").eq("id", userId).single(),
      "Usuario no encontrado.",
    );
    const failedAttempts = Number(user.failed_attempts ?? 0) + 1;
    const payload: Record<string, unknown> = { failed_attempts: failedAttempts };
    if (failedAttempts >= 10) {
      payload.locked_until = new Date(Date.now() + 15 * 60 * 1000).toISOString();
    }
    const { error } = await db.from("users").update(payload).eq("id", userId);
    assertNoDbError(error);
  }
}

export const authFlowRepository = new AuthFlowRepository();
