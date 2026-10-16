import { assertNoDbError, expectSingle } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { requireSupabaseServiceRole } from "../../lib/supabase";

const loginSelect =
  "id, auth_user_id, institution_id, person_id, username, email, full_name, admin_permissions, active, locked_until, two_factor, user_roles(roles(code, name))";

const loginSelectWithInstitution = `${loginSelect}, institutions(id, code, name, commercial_name, active)`;

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

  async findLoginTwoFactorSettings(userId: number): Promise<Record<string, unknown>> {
    const user = await this.findUserForTwoFactor(userId);
    return user;
  }

  async findUserForTwoFactor(userId: number): Promise<Record<string, unknown>> {
    const db = requireSupabaseServiceRole();
    const user = await expectSingle<Record<string, unknown>>(db.from("users")
      .select(loginSelectWithInstitution).eq("id", userId).eq("active", true).is("deleted_at", null).single(), "Usuario no disponible.");
    const {data,error}=await db.from("auth_two_factor_settings").select("*").eq("user_id",userId).maybeSingle();
    assertNoDbError(error);
    const settings=data ?? {};
    return {...user,two_factor:settings.enabled === true,two_factor_method:settings.method ?? "email",
      two_factor_secret:settings.secret,two_factor_pending_method:settings.pending_method,
      two_factor_pending_secret:settings.pending_secret,two_factor_recovery_codes:settings.recovery_codes ?? [],
      two_factor_locked_until:settings.locked_until,two_factor_verified_at:settings.verified_at};
  }

  async beginTwoFactor(args: Record<string,unknown>) {
    return this.factorResult(await requireSupabaseServiceRole().rpc("auth_2fa_begin",args));
  }
  async verifyTwoFactor(args: Record<string,unknown>) {
    return this.factorResult(await requireSupabaseServiceRole().rpc("auth_2fa_verify",args));
  }
  async findTwoFactorChallenge(id: string) {
    const {data,error}=await requireSupabaseServiceRole().from("auth_two_factor_challenges").select("*").eq("id",id).maybeSingle();
    assertNoDbError(error);return data as Record<string,unknown> | null;
  }
  async latestTwoFactorChallenge(userId: number,purpose: string) {
    const {data,error}=await requireSupabaseServiceRole().from("auth_two_factor_challenges").select("*")
      .eq("user_id",userId).eq("purpose",purpose).is("consumed_at",null).order("created_at",{ascending:false}).limit(1).maybeSingle();
    assertNoDbError(error);return data as Record<string,unknown> | null;
  }
  async finishTwoFactorDelivery(id: string,success: boolean) {
    const {error}=await requireSupabaseServiceRole().from("auth_two_factor_challenges")
      .update(success ? {delivery_status:"sent"} : {delivery_status:"failed",consumed_at:new Date().toISOString(),session_payload:{},auth_user_payload:{}})
      .eq("id",id).is("consumed_at",null);
    assertNoDbError(error);
  }
  private factorResult(result: {data: any;error: {message:string} | null}) {
    assertNoDbError(result.error);
    const data=result.data as Record<string,unknown>;
    if(data?.ok === true) return data;
    const errors: Record<string,[number,string]>={
      cooldown:[429,"Espera 60 segundos antes de solicitar otro código."],send_limit:[429,"Alcanzaste el límite de 5 correos por hora. Intenta más tarde."],
      locked:[423,"Demasiados intentos. La verificación está bloqueada durante 15 minutos."],
      expired:[401,"El código ha expirado. Solicita uno nuevo."],used:[401,"Este código ya fue utilizado. Solicita uno nuevo."],
      incorrect:[401,"El código es incorrecto. Revisa los 6 dígitos e inténtalo otra vez."],
      already_enabled:[409,"Desactiva el método actual antes de activar otro."],method_changed:[409,"La configuración cambió. Inicia la verificación nuevamente."],
      not_sent:[409,"El código no se ha enviado correctamente. Solicita uno nuevo."],account_unavailable:[403,"La cuenta no está disponible."],
      invalid:[401,"La verificación no es válida. Iníciala nuevamente."],
    };
    const code=String(data?.error ?? "invalid");const [status,message]=errors[code] ?? errors.invalid;
    throw new HttpError(status,message,`two_factor_${code}`);
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

}

export const authFlowRepository = new AuthFlowRepository();
