import {assertAuthAvailable} from "../../lib/auth-error";
import {dependencyFetch} from "../../lib/dependency-fetch";
import crypto from "crypto";
import { createClient } from "@supabase/supabase-js";

import {
  asList,
  asRecord,
  optionalString,
  requiredString,
} from "../../validators/common.validators";
import { env } from "../../lib/env";
import { HttpError } from "../../lib/errors";
import { requireSupabaseServiceRole, supabasePublic } from "../../lib/supabase";
import { emailService } from "./email.service";
import { authFlowRepository, AuthFlowRepository } from "./auth-flow.repository";

const base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export class AuthFlowService {
  constructor(
    private readonly repository: AuthFlowRepository = authFlowRepository,
    private readonly emails: typeof emailService = emailService,
    private readonly auth: typeof supabasePublic.auth = supabasePublic.auth,
    private readonly passwordAuth = () => createClient(env.supabaseUrl, env.supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
      global:{fetch:dependencyFetch},
    }).auth,
  ) {}

  async login(payload: Record<string, unknown>) {
    const institutionCode = optionalString(
      payload.institutionCode ?? payload.institution_code ?? payload.schoolCode,
      50,
    );
    const username = requiredString(payload.username, "Usuario", 100);
    const password = requiredString(payload.password, "Contrasena", 200);

    const { institution, appUser } = await this.resolveLoginTarget(
      username,
      institutionCode ?? undefined,
    );
    if (
      institution == null ||
      institution.active === false ||
      appUser == null ||
      appUser.active === false
    ) {
      throw new HttpError(
        401,
        "Credenciales invalidas.",
        "invalid_credentials",
      );
    }
    if (this.isLocked(appUser.locked_until)) {
      throw new HttpError(
        423,
        "Usuario bloqueado temporalmente. Intenta mas tarde.",
        "user_locked",
      );
    }

    const { data, error } = await this.auth.signInWithPassword({
      email: String(appUser.email),
      password,
    });
    assertAuthAvailable(error);
    if (!error && (data.session==null||data.user==null))throw new HttpError(503,"No se pudo confirmar el inicio de sesión.","authentication_unavailable",2);
    if (error || data.session == null || data.user == null) {
      await this.repository.incrementFailedAttempts(Number(appUser.id));
      throw new HttpError(
        401,
        "Credenciales invalidas.",
        "invalid_credentials",
      );
    }
    if (
      appUser.auth_user_id != null &&
      String(appUser.auth_user_id) !== data.user.id
    ) {
      throw new HttpError(
        403,
        "La cuenta de autenticacion no coincide con el usuario institucional.",
        "forbidden",
      );
    }

    const twoFactorSettings = await this.repository.findLoginTwoFactorSettings(
      Number(appUser.id),
    );
    if (this.requiresTwoFactor(twoFactorSettings)) {
      return this.createTwoFactorLoginChallenge(data, {
        ...appUser,
        ...twoFactorSettings,
      });
    }

    await this.repository.updateLastSignIn(Number(appUser.id));
    return this.authResponse(data, appUser, institution);
  }

  async refresh(payload: Record<string, unknown>) {
    const refreshToken = requiredString(
      payload.refreshToken ?? payload.refresh_token,
      "Refresh token",
      4000,
    );
    const { data, error } = await this.auth.refreshSession({
      refresh_token: refreshToken,
    });
    if (error || data.session == null || data.user == null) {
      throw new HttpError(401, "Refresh token invalido.", "unauthorized");
    }
    return {
      session: this.sessionPayload(
        data.session as unknown as Record<string, unknown>,
      ),
      authUser: { id: data.user.id, email: data.user.email ?? null },
    };
  }

  async recoverPassword(payload: Record<string, unknown>) {
    const institutionCode = optionalString(
      payload.institutionCode ?? payload.institution_code ?? payload.schoolCode,
      50,
    );
    const username = requiredString(payload.username, "Usuario", 100);
    let appUser: Record<string, unknown> | null = null;

    if (institutionCode != null) {
      const institution =
        await this.repository.findInstitutionByCode(institutionCode);
      appUser =
        institution == null
          ? null
          : await this.repository.findLoginUser(
              Number(institution.id),
              username,
            );
    } else {
      const found = await this.repository.findLoginUserByIdentifier(username);
      appUser = found?.ambiguous === true ? null : found;
    }

    if (appUser?.email) {
      // Link directly to the app. Supabase's default Site URL must not decide
      // where password recovery lands, nor require a browser's PKCE verifier.
      const recoveryUrl = this.passwordRecoveryUrl();
      const admin = requireSupabaseServiceRole();
      const { data, error } = await admin.auth.admin.generateLink({
        type: "recovery",
        email: String(appUser.email),
        options: {
          redirectTo: recoveryUrl.toString(),
        },
      });
      if (error) {
        throw new HttpError(
          503,
          "No se pudo preparar el enlace de recuperación. Intenta nuevamente.",
          "password_recovery_link_failed",
        );
      }
      const tokenHash = data?.properties?.hashed_token;
      if (typeof tokenHash === "string" && tokenHash.length > 0) {
        if (recoveryUrl.hash.startsWith("#/")) {
          const [route, query] = recoveryUrl.hash.slice(1).split("?");
          const params = new URLSearchParams(query);
          params.set("token_hash", tokenHash);
          recoveryUrl.hash = `${route}?${params}`;
        } else {
          recoveryUrl.searchParams.set("token_hash", tokenHash);
        }
        await this.emails.sendPasswordRecovery(
          String(appUser.email),
          String(appUser.full_name ?? username),
          recoveryUrl.toString(),
        );
      } else {
        throw new HttpError(502, "No se pudo generar el enlace de recuperación.", "password_recovery_link_failed");
      }
    }

    return {
      ok: true,
      message:
        "Si la cuenta existe y tiene correo, recibirás instrucciones de recuperación.",
    };
  }

  private passwordRecoveryUrl() {
    let url: URL;
    try { url = new URL(env.passwordResetRedirectUrl); } catch {
      throw new HttpError(503, "La recuperación de contraseña no está configurada. Contacta a la administración.", "password_recovery_unavailable");
    }
    if (!["http:", "https:"].includes(url.protocol) || url.username || url.password ||
      (url.hash.split("?")[0] !== "#/reset-password" && url.pathname !== "/reset-password")) {
      throw new HttpError(503, "La dirección de recuperación no está configurada correctamente. Contacta a la administración.", "password_recovery_unavailable");
    }
    return url;
  }

  async resetPassword(payload: Record<string, unknown>) {
    const tokenHash = requiredString(payload.tokenHash, "Enlace de recuperación", 300);
    const password = requiredString(payload.newPassword, "Nueva contraseña", 200);
    if (password.length < 8) throw new HttpError(400, "La nueva contraseña debe tener al menos 8 caracteres.", "validation_error");
    const auth = this.passwordAuth();
    const { data, error } = await auth.verifyOtp({ token_hash: tokenHash, type: "recovery" });
    if (error || !data.session || !data.user) {
      throw new HttpError(400, "El enlace es inválido, expiró o ya fue utilizado. Solicita uno nuevo.", "password_recovery_invalid");
    }
    try {
      const result = await auth.updateUser({ password });
      if (result.error) throw new HttpError(400, "No se pudo actualizar la contraseña. Solicita un enlace nuevo y usa una contraseña diferente de al menos 8 caracteres.", "password_reset_failed");
      // Recovery grants only a password change, never a returned app session.
      // Keep the configured second factor; the next login must still verify it.
      await auth.signOut({ scope: "global" });
      return { ok: true };
    } finally {
      await auth.signOut({ scope: "local" }).catch(() => undefined);
    }
  }

  /** Cambia la contrasena de quien tiene la sesion: exige la actual y una nueva distinta (min. 8). */
  async changePassword(userId: number, payload: Record<string, unknown>) {
    const current = requiredString(payload.currentPassword ?? payload.current_password, "Contrasena actual", 200);
    const next = requiredString(payload.newPassword ?? payload.new_password, "Contrasena nueva", 200);
    if (next.length < 8) {
      throw new HttpError(400, "La contrasena nueva debe tener al menos 8 caracteres.", "validation_error");
    }
    if (next === current) {
      throw new HttpError(400, "La contrasena nueva debe ser distinta de la actual.", "validation_error");
    }
    const user = await this.repository.findUserForTwoFactor(userId);
    const authUserId = String(user.auth_user_id ?? "");
    const email = String(user.email ?? "");
    if (!authUserId || !email) {
      throw new HttpError(400, "La cuenta no tiene acceso por contrasena.", "validation_error");
    }
    const verifier = this.passwordAuth();
    const { data, error } = await verifier.signInWithPassword({ email, password: current });
    assertAuthAvailable(error);
    if (error || data.user?.id !== authUserId) {
      throw new HttpError(400, "La contrasena actual no es correcta.", "invalid_credentials");
    }
    await verifier.signOut({ scope: "local" });
    const admin = requireSupabaseServiceRole();
    const { error: updateError } = await admin.auth.admin.updateUserById(authUserId, { password: next });
    if (updateError) {
      assertAuthAvailable(updateError);
      throw new HttpError(400,"Auth rechazó el cambio de contraseña. Revisa sus requisitos.","password_change_failed");
    }
    return { ok: true };
  }

  async twoFactorStatus(userId: number) {
    const user=await this.repository.findUserForTwoFactor(userId);
    return {enabled:user.two_factor === true,required:false,method:user.two_factor_method ?? "email",
      hasAuthenticator:!!user.two_factor_secret,recoveryCodesRemaining:asList(user.two_factor_recovery_codes).length,
      verifiedAt:user.two_factor_verified_at ?? null,emailHint:this.maskEmail(String(user.email ?? "")),availableMethods:["totp","email"]};
  }

  async setupTwoFactor(userId: number,payload: Record<string,unknown>) {
    const method=optionalString(payload.method,20) ?? "totp";
    if(method !== "totp" && method !== "email") throw new HttpError(400,"Elige app autenticadora o correo electrónico.","unsupported_two_factor_method");
    const user=await this.repository.findUserForTwoFactor(userId);
    const secret=method === "totp" ? this.generateBase32Secret() : null;
    const challenge=await this.beginChallenge(user,method,"setup",secret);
    const issuer="Nivra", accountName=String(user.email ?? user.username ?? user.id);
    return {...challenge,secret,accountName,issuer,
      otpauthUrl:secret == null ? null : `otpauth://totp/${encodeURIComponent(`${issuer}:${accountName}`)}?secret=${secret}&issuer=${issuer}&algorithm=SHA1&digits=6&period=30`};
  }

  async sendTwoFactorEmailCode(userId: number,payload: Record<string,unknown>) {
    if(payload.purpose !== "disable") throw new HttpError(400,"Verificación no válida.","validation_error");
    const user=await this.repository.findUserForTwoFactor(userId);
    if(user.two_factor !== true || user.two_factor_method !== "email") throw new HttpError(409,"La cuenta no tiene 2FA por correo activo.","two_factor_method_changed");
    return this.beginChallenge(user,"email","disable",null);
  }

  async enableTwoFactor(userId: number,payload: Record<string,unknown>,sessionId?: string | null) {
    const recoveryCodes=this.generateRecoveryCodes();
    const result=await this.verifyChallenge(payload,"setup",userId,recoveryCodes,sessionId);
    return {enabled:true,method:result.method,recoveryCodes};
  }

  async disableTwoFactor(userId: number,payload: Record<string,unknown>) {
    const user=await this.repository.findUserForTwoFactor(userId);
    if(user.two_factor !== true) return {enabled:false};
    // TOTP and recovery confirmations need no email. Email codes use an explicit challenge.
    if(payload.challengeId == null && (user.two_factor_method === "totp" || payload.recoveryCode != null)) {
      const challenge=await this.beginChallenge(user,String(user.two_factor_method) as "email"|"totp","disable",
        optionalString(user.two_factor_secret,200),{},null,true);
      payload={...payload,challengeId:challenge.id};
    }
    await this.verifyChallenge(payload,"disable",userId);
    return {enabled:false};
  }

  async verifyTwoFactorLogin(payload: Record<string,unknown>) {
    const result=await this.verifyChallenge(payload,"login",null);
    const user=await this.repository.findUserForTwoFactor(Number(result.userId));
    return this.authResponse({session:result.session,user:{id:String(asRecord(result.authUser).id),email:optionalString(asRecord(result.authUser).email,200)}},user,asRecord(user.institutions));
  }

  async resendTwoFactorLogin(payload: Record<string,unknown>) {
    const id=this.challengeId(payload.challengeId);
    const old=await this.repository.findTwoFactorChallenge(id);
    if(old == null || old.purpose !== "login" || old.method !== "email" || old.consumed_at != null || Date.parse(String(old.expires_at))<=Date.now()) {
      throw new HttpError(401,"La verificación expiró. Inicia sesión nuevamente.","two_factor_expired");
    }
    const user=await this.repository.findUserForTwoFactor(Number(old.user_id));
    return {challenge:await this.beginChallenge(user,"email","login",null,asRecord(old.session_payload),id)};
  }

  private challengeId(value: unknown) {
    const id=requiredString(value,"Verificación",80);
    if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw new HttpError(401,"Verificación no válida.","two_factor_invalid");
    return id.toLowerCase();
  }
  private async verifyChallenge(payload: Record<string,unknown>,purpose:string,userId:number|null,recoveryCodes:string[]=[],sessionId?:string|null) {
    const recovery=optionalString(payload.recoveryCode,80);
    const code=optionalString(payload.code,40)?.replace(/\s/g,"");
    if(recovery == null && (code == null || !/^\d{6}$/.test(code))) throw new HttpError(400,"Ingresa un código de 6 dígitos.","validation_error");
    const latest=payload.challengeId == null && userId != null ? await this.repository.latestTwoFactorChallenge(userId,purpose) : null;
    const id=this.challengeId(payload.challengeId ?? latest?.id);
    const challenge=latest ?? await this.repository.findTwoFactorChallenge(id);
    if(challenge == null || challenge.purpose !== purpose || (userId != null && Number(challenge.user_id)!==userId)) throw new HttpError(401,"Verificación no válida.","two_factor_invalid");
    const secret=optionalString(challenge.secret_snapshot,200);
    return this.repository.verifyTwoFactor({p_id:id,p_user_id:userId,p_purpose:purpose,
      p_hash:code == null ? null : this.hashEmailCode(id,code),
      p_totp_valid:secret != null && code != null && this.verifyTotp(secret,code),p_secret:secret,
      p_recovery_hash:recovery == null ? null : this.hashSecret(recovery.toUpperCase().replace(/\s/g,"")),
      p_recovery_codes:recoveryCodes.map(c=>this.hashSecret(c)),p_session_id:sessionId ?? null});
  }
  async logout(accessToken: string) {
    const response = await dependencyFetch(`${env.supabaseUrl}/auth/v1/logout`, {
      method: "POST",
      headers: {
        apikey: env.supabaseAnonKey,
        authorization: `Bearer ${accessToken}`,
      },
    });
    if (!response.ok && response.status !== 401) {
      throw new HttpError(503, "No se pudo confirmar el cierre de sesión. Intenta nuevamente.", "logout_failed");
    }
    return { ok: true };
  }

  private async resolveLoginTarget(username: string, institutionCode?: string) {
    if (institutionCode != null && institutionCode.trim() !== "") {
      const institution =
        await this.repository.findInstitutionByCode(institutionCode);
      if (institution == null || institution.active === false) {
        throw new HttpError(
          401,
          "Credenciales invalidas.",
          "invalid_credentials",
        );
      }
      const appUser = await this.repository.findLoginUser(
        Number(institution.id),
        username,
      );
      return { institution, appUser };
    }

    const appUser = await this.repository.findLoginUserByIdentifier(username);
    if (appUser?.ambiguous === true) {
      throw new HttpError(
        401,
        "Credenciales invalidas.",
        "invalid_credentials",
      );
    }
    const institution = asRecord(appUser?.institutions);
    return { institution, appUser };
  }

  private authResponse(
    data: { session: unknown; user: { id: string; email?: string | null } },
    appUser: Record<string, unknown>,
    institution: Record<string, unknown>,
  ) {
    return {
      session: this.sessionPayload(asRecord(data.session)),
      authUser: { id: data.user.id, email: data.user.email ?? null },
      user: {
        id: String(appUser.id),
        institutionId: String(appUser.institution_id),
        personId: appUser.person_id == null ? null : String(appUser.person_id),
        username: appUser.username ?? null,
        email: appUser.email ?? null,
        fullName: String(appUser.full_name ?? ""),
        adminPermissions: Array.isArray(appUser.admin_permissions)
          ? (appUser.admin_permissions as unknown[]).map(String)
          : null,
        roles: this.roleCodes(appUser),
      },
      institution: {
        id: String(institution.id),
        code: String(institution.code),
        name: String(institution.commercial_name ?? institution.name),
      },
    };
  }

  private async createTwoFactorLoginChallenge(data: {session:unknown;user:{id:string;email?:string|null}},appUser:Record<string,unknown>) {
    const method=appUser.two_factor_method === "totp" ? "totp" : "email";
    const raw=asRecord(data.session);
    const session={...raw,session_id:sessionIdFromToken(String(raw.access_token ?? ""))};
    return {twoFactorRequired:true,challenge:await this.beginChallenge(appUser,method,"login",optionalString(appUser.two_factor_secret,200),session)};
  }

  private async beginChallenge(user:Record<string,unknown>,method:"email"|"totp",purpose:string,secret:string|null,
    session:Record<string,unknown>={},replaceId:string|null=null,recoveryOnly=false) {
    const id=crypto.randomUUID();
    const code=method === "email" && !recoveryOnly ? this.generateEmailCode() : null;
    const result=await this.repository.beginTwoFactor({p_id:id,p_user_id:Number(user.id),p_method:method,p_purpose:purpose,p_secret:secret,
      p_code_hash:code == null ? null : this.hashEmailCode(id,code),p_session:session,
      p_auth:{id:user.auth_user_id,email:user.email},p_replace:replaceId});
    if(code != null) {
      try {
        await this.emails.sendTwoFactorCode(String(user.email),String(user.full_name ?? "usuario"),code,purpose,id);
        await this.repository.finishTwoFactorDelivery(id,true);
      } catch (error) {
        await this.repository.finishTwoFactorDelivery(id,false);
        if (error instanceof HttpError && error.status === 503) throw error;
        throw new HttpError(502,"No se pudo enviar el código por correo. Intenta nuevamente en un minuto.","email_send_failed");
      }
    } else if(recoveryOnly && method === "email") {
      await this.repository.finishTwoFactorDelivery(id,true);
    }
    return {...result,id,method,emailHint:this.maskEmail(String(user.email ?? ""))};
  }

  private hashEmailCode(id:string,code:string) {
    if(!env.supabaseServiceRoleKey) throw new HttpError(503,"2FA no está configurado en el servidor.","two_factor_unavailable");
    return crypto.createHmac("sha256",env.supabaseServiceRoleKey).update(`2fa:${id}:${code}`).digest("hex");
  }

  private requiresTwoFactor(settings: Record<string, unknown> | null) {
    return settings?.two_factor === true;
  }

  private roleCodes(appUser: Record<string, unknown>) {
    return asList(appUser.user_roles)
      .map((entry) => asRecord(asRecord(entry).roles).code ?? null)
      .filter((role): role is string => typeof role === "string");
  }

  private sessionPayload(session: Record<string, unknown>) {
    return {
      accessToken: session.access_token,
      refreshToken: session.refresh_token,
      expiresAt: session.expires_at,
      expiresIn: session.expires_in,
      tokenType: session.token_type ?? "bearer",
    };
  }

  private isLocked(value: unknown) {
    if (value == null) return false;
    const until = new Date(String(value));
    return !Number.isNaN(until.getTime()) && until.getTime() > Date.now();
  }

  private generateEmailCode() {
    return String(crypto.randomInt(0, 1000000)).padStart(6, "0");
  }

  private generateRecoveryCodes() {
    return Array.from({ length: 10 }, () => {
      const raw = crypto.randomBytes(8).toString("hex").toUpperCase();
      return raw.match(/.{4}/g)!.join("-");
    });
  }

  private generateBase32Secret() {
    const bits=[...crypto.randomBytes(20)].map(byte=>byte.toString(2).padStart(8,"0")).join("");
    return Array.from({length:32},(_,index)=>base32Alphabet[parseInt(bits.slice(index*5,index*5+5),2)]).join("");
  }

  private verifyTotp(secret: string, code: string) {
    if(!/^[A-Z2-7]{16,128}$/i.test(secret)) return false;
    const normalized = code.replace(/\s/g, "");
    if (!/^\d{6}$/.test(normalized)) return false;
    const step = Math.floor(Date.now() / 30000);
    return [-1, 0, 1].some(
      (offset) => this.totpAt(secret, step + offset) === normalized,
    );
  }

  private totpAt(secret: string, step: number) {
    const key = this.base32Decode(secret);
    const counter = Buffer.alloc(8);
    counter.writeBigUInt64BE(BigInt(step));
    const hmac = crypto.createHmac("sha1", key).update(counter).digest();
    const offset = hmac[hmac.length - 1] & 0x0f;
    const binary =
      ((hmac[offset] & 0x7f) << 24) |
      ((hmac[offset + 1] & 0xff) << 16) |
      ((hmac[offset + 2] & 0xff) << 8) |
      (hmac[offset + 3] & 0xff);
    return String(binary % 1000000).padStart(6, "0");
  }

  private base32Decode(value: string) {
    let bits = "";
    for (const char of value.replace(/=+$/g, "").toUpperCase()) {
      const index = base32Alphabet.indexOf(char);
      if (index < 0) continue;
      bits += index.toString(2).padStart(5, "0");
    }
    const bytes: number[] = [];
    for (let i = 0; i + 8 <= bits.length; i += 8) {
      bytes.push(parseInt(bits.slice(i, i + 8), 2));
    }
    return Buffer.from(bytes);
  }

  private hashSecret(value: string) {
    return crypto.createHash("sha256").update(value).digest("hex");
  }

  private maskEmail(email: string) {
    const [name, domain] = email.split("@");
    if (!name || !domain) return "";
    return `${name.slice(0, 2)}***@${domain}`;
  }
}

export function sessionIdFromToken(token:string):string|null {
  try {const id=JSON.parse(Buffer.from(token.split(".")[1],"base64url").toString()).session_id;return typeof id === "string" ? id : null;} catch {return null;}
}
export const authFlowService = new AuthFlowService();
