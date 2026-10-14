import { assertNoDbError, expectSingle } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { requireSupabaseServiceRole } from "../../lib/supabase";

const loginSelect =
  "id, auth_user_id, institution_id, person_id, username, email, full_name, admin_permissions, active, locked_until, two_factor, user_roles(roles(code, name))";

const loginSelectWithInstitution = `${loginSelect}, institutions(id, code, name, commercial_name, active)`;

const twoFactorSelect =
  "id, auth_user_id, institution_id, person_id, username, email, full_name, admin_permissions, active, locked_until, two_factor, two_factor_method, two_factor_secret, two_factor_pending_secret, two_factor_pending_method, two_factor_recovery_codes, two_factor_locked_until, user_roles(roles(code, name)), institutions(id, code, name, commercial_name, active)";

export class AuthFlowRepository {
  async findInstitutionByCode(code: string) {
    const db = requireSupabaseServiceRole();
    const { data } = await db
      .from("institutions")
      .select("id, code, name, commercial_name, active")
      .ilike("code", code)
      .is("deleted_at", null)
      .maybeSingle();
    return data == null ? null : (data as Record<string, unknown>);
  }

  async findLoginUser(institutionId: number, username: string) {
    const db = requireSupabaseServiceRole();
    const byUsername = await db
      .from("users")
      .select(loginSelect)
      .eq("institution_id", institutionId)
      .ilike("username", username)
      .is("deleted_at", null)
      .maybeSingle();
    if (byUsername.data != null) {
      return byUsername.data as Record<string, unknown>;
    }
    const byEmail = await db
      .from("users")
      .select(loginSelect)
      .eq("institution_id", institutionId)
      .ilike("email", username)
      .is("deleted_at", null)
      .maybeSingle();
    return byEmail.data == null
      ? null
      : (byEmail.data as Record<string, unknown>);
  }

  async findLoginUserByIdentifier(username: string) {
    const db = requireSupabaseServiceRole();
    const safeUsername = username.replace(/[%_]/g, "");
    const { data, error } = await db
      .from("users")
      .select(loginSelectWithInstitution)
      .or(`username.ilike.${safeUsername},email.ilike.${safeUsername}`)
      .is("deleted_at", null)
      .limit(2);
    assertNoDbError(error);
    if (!Array.isArray(data) || data.length === 0) return null;
    if (data.length > 1) return { ambiguous: true } as Record<string, unknown>;
    return data[0] as Record<string, unknown>;
  }

  async updateLastSignIn(userId: number) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("users")
      .update({ last_sign_in: new Date().toISOString(), failed_attempts: 0 })
      .eq("id", userId);
    assertNoDbError(error);
  }

  async findLoginTwoFactorSettings(
    userId: number,
  ): Promise<Record<string, unknown> | null> {
    const db = requireSupabaseServiceRole();
    const { data, error } = await db
      .from("users")
      .select(
        "two_factor, two_factor_method, two_factor_secret, two_factor_locked_until",
      )
      .eq("id", userId)
      .maybeSingle();
    if (error) {
      if (this.isMissingTwoFactorSchema(error.message)) return null;
      assertNoDbError(error);
    }
    return data == null ? null : (data as Record<string, unknown>);
  }

  async findUserForTwoFactor(userId: number): Promise<Record<string, unknown>> {
    const db = requireSupabaseServiceRole();
    const { data, error } = await db
      .from("users")
      .select(twoFactorSelect)
      .eq("id", userId)
      .is("deleted_at", null)
      .single();
    if (error) {
      if (this.isMissingTwoFactorSchema(error.message)) {
        const base = await expectSingle<Record<string, unknown>>(
          db
            .from("users")
            .select(loginSelectWithInstitution)
            .eq("id", userId)
            .is("deleted_at", null)
            .single(),
          "Usuario no encontrado.",
        );
        return {
          ...base,
          two_factor: false,
          two_factor_method: "email",
          two_factor_secret: null,
          two_factor_pending_secret: null,
          two_factor_pending_method: null,
          two_factor_recovery_codes: [],
          two_factor_locked_until: null,
          two_factor_schema_available: false,
        };
      }
      assertNoDbError(error);
    }
    return {
      ...(data as Record<string, unknown>),
      two_factor_schema_available: true,
    };
  }

  async savePendingTotpSecret(userId: number, secret: string) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("users")
      .update({
        two_factor_pending_method: "totp",
        two_factor_pending_secret: secret,
      })
      .eq("id", userId);
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
  }

  async enableTwoFactor(
    userId: number,
    method: "email" | "totp",
    secret: string | null,
    recoveryCodeHashes: string[],
  ) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("users")
      .update({
        two_factor: true,
        two_factor_method: method,
        two_factor_secret: secret,
        two_factor_pending_method: null,
        two_factor_pending_secret: null,
        two_factor_recovery_codes: recoveryCodeHashes,
        two_factor_failed_attempts: 0,
        two_factor_locked_until: null,
      })
      .eq("id", userId);
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
  }

  async disableTwoFactor(userId: number) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("users")
      .update({
        two_factor: false,
        two_factor_method: "email",
        two_factor_secret: null,
        two_factor_pending_method: null,
        two_factor_pending_secret: null,
        two_factor_recovery_codes: [],
        two_factor_failed_attempts: 0,
        two_factor_locked_until: null,
      })
      .eq("id", userId);
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
  }

  async replaceRecoveryCodes(userId: number, hashes: string[]) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("users")
      .update({ two_factor_recovery_codes: hashes })
      .eq("id", userId);
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
  }

  async createTwoFactorChallenge(payload: {
    userId: number;
    institutionId: number;
    method: "email" | "totp";
    codeHash: string | null;
    sessionPayload: Record<string, unknown>;
    authUserPayload: Record<string, unknown>;
    expiresAt: string;
  }) {
    const db = requireSupabaseServiceRole();
    const { data, error } = await db
      .from("auth_two_factor_challenges")
      .insert({
        user_id: payload.userId,
        institution_id: payload.institutionId,
        method: payload.method,
        code_hash: payload.codeHash,
        session_payload: payload.sessionPayload,
        auth_user_payload: payload.authUserPayload,
        expires_at: payload.expiresAt,
      })
      .select("id, method, expires_at, created_at")
      .single();
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
    return data as Record<string, unknown>;
  }

  async findTwoFactorChallenge(id: string) {
    const db = requireSupabaseServiceRole();
    const { data, error } = await db
      .from("auth_two_factor_challenges")
      .select("*")
      .eq("id", id)
      .maybeSingle();
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
    return data == null ? null : (data as Record<string, unknown>);
  }

  async incrementTwoFactorChallengeAttempts(id: string) {
    const db = requireSupabaseServiceRole();
    const challenge = await expectSingle<Record<string, unknown>>(
      db
        .from("auth_two_factor_challenges")
        .select("failed_attempts, user_id")
        .eq("id", id)
        .single(),
      "Verificación no encontrada.",
    );
    const failedAttempts = Number(challenge.failed_attempts ?? 0) + 1;
    const { error } = await db
      .from("auth_two_factor_challenges")
      .update({ failed_attempts: failedAttempts })
      .eq("id", id);
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
    if (failedAttempts >= 5) {
      await this.lockTwoFactorUser(Number(challenge.user_id));
    }
    return failedAttempts;
  }

  async consumeTwoFactorChallenge(id: string) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("auth_two_factor_challenges")
      .update({ consumed_at: new Date().toISOString() })
      .eq("id", id);
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
  }

  private async lockTwoFactorUser(userId: number) {
    const db = requireSupabaseServiceRole();
    const { error } = await db
      .from("users")
      .update({
        two_factor_failed_attempts: 5,
        two_factor_locked_until: new Date(
          Date.now() + 15 * 60 * 1000,
        ).toISOString(),
      })
      .eq("id", userId);
    this.assertTwoFactorSchemaError(error?.message);
    assertNoDbError(error);
  }

  async incrementFailedAttempts(userId: number) {
    const db = requireSupabaseServiceRole();
    const user = await expectSingle<Record<string, unknown>>(
      db.from("users").select("failed_attempts").eq("id", userId).single(),
      "Usuario no encontrado.",
    );
    const failedAttempts = Number(user.failed_attempts ?? 0) + 1;
    const payload: Record<string, unknown> = {
      failed_attempts: failedAttempts,
    };
    if (failedAttempts >= 10) {
      payload.locked_until = new Date(
        Date.now() + 15 * 60 * 1000,
      ).toISOString();
    }
    const { error } = await db.from("users").update(payload).eq("id", userId);
    assertNoDbError(error);
  }

  private assertTwoFactorSchemaError(message: string | undefined) {
    if (!message || !this.isMissingTwoFactorSchema(message)) return;
    throw new HttpError(
      503,
      "2FA todavía no está preparado en la base de datos. Aplica la migración 0018_two_factor_auth.sql.",
      "two_factor_schema_missing",
    );
  }

  private isMissingTwoFactorSchema(message: string) {
    return (
      message.includes("two_factor_") ||
      message.includes("auth_two_factor_challenges")
    );
  }
}

export const authFlowRepository = new AuthFlowRepository();
