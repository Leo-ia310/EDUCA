import crypto from "crypto";

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

const challengeTtlMs = 5 * 60 * 1000;
const base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export class AuthFlowService {
  constructor(
    private readonly repository: AuthFlowRepository = authFlowRepository,
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

    const { data, error } = await supabasePublic.auth.signInWithPassword({
      email: String(appUser.email),
      password,
    });
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
    const { data, error } = await supabasePublic.auth.refreshSession({
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
      const admin = requireSupabaseServiceRole();
      const { data, error } = await admin.auth.admin.generateLink({
        type: "recovery",
        email: String(appUser.email),
        options: {
          redirectTo: env.passwordResetRedirectUrl || undefined,
        },
      });
      if (error) {
        throw new HttpError(
          400,
          error.message,
          "password_recovery_link_failed",
        );
      }
      const actionLink =
        data?.properties?.action_link ?? data?.properties?.email_otp ?? null;
      if (typeof actionLink === "string") {
        await emailService.sendPasswordRecovery(
          String(appUser.email),
          String(appUser.full_name ?? username),
          actionLink,
        );
      }
    }

    return {
      ok: true,
      message:
        "Si la cuenta existe y tiene correo, Supabase Auth enviara instrucciones de recuperacion.",
    };
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
    const { error } = await supabasePublic.auth.signInWithPassword({ email, password: current });
    if (error) {
      throw new HttpError(400, "La contrasena actual no es correcta.", "invalid_credentials");
    }
    const admin = requireSupabaseServiceRole();
    const { error: updateError } = await admin.auth.admin.updateUserById(authUserId, { password: next });
    if (updateError) {
      throw new HttpError(400, updateError.message || "No se pudo cambiar la contrasena.", "password_change_failed");
    }
    return { ok: true };
  }

  async twoFactorStatus(userId: number) {
    const user = await this.repository.findUserForTwoFactor(userId);
    const recoveryCodes = asList(user.two_factor_recovery_codes);
    return {
      enabled: user.two_factor === true,
      required: false,
      method:
        user.two_factor === true
          ? String(user.two_factor_method ?? "email")
          : "email",
      hasAuthenticator:
        typeof user.two_factor_secret === "string" &&
        user.two_factor_secret.length > 0,
      recoveryCodesRemaining: recoveryCodes.length,
    };
  }

  async setupTwoFactor(userId: number, payload: Record<string, unknown>) {
    const method = optionalString(payload.method, 20) ?? "totp";
    if (method !== "totp") {
      throw new HttpError(
        400,
        "Por ahora la activacion manual usa app autenticadora.",
        "unsupported_two_factor_method",
      );
    }
    const user = await this.repository.findUserForTwoFactor(userId);
    if (user.two_factor_schema_available === false) {
      throw new HttpError(
        503,
        "2FA todavía no está preparado en la base de datos. Aplica la migración 0018_two_factor_auth.sql.",
        "two_factor_schema_missing",
      );
    }
    const secret = this.generateBase32Secret();
    await this.repository.savePendingTotpSecret(userId, secret);
    const issuer = "Nivra";
    const label = `${issuer}:${String(user.email ?? user.username ?? user.id)}`;
    const otpauthUrl =
      `otpauth://totp/${encodeURIComponent(label)}?secret=${secret}` +
      `&issuer=${encodeURIComponent(issuer)}&digits=6&period=30`;
    return {
      method: "totp",
      secret,
      otpauthUrl,
      accountName: String(user.email ?? user.username ?? "usuario"),
      issuer,
    };
  }

  async enableTwoFactor(userId: number, payload: Record<string, unknown>) {
    const code = requiredString(payload.code, "Codigo", 20);
    const user = await this.repository.findUserForTwoFactor(userId);
    const secret = optionalString(user.two_factor_pending_secret, 200);
    if (secret == null || user.two_factor_pending_method !== "totp") {
      throw new HttpError(
        400,
        "Primero inicia la configuracion de 2FA.",
        "two_factor_setup_required",
      );
    }
    if (!this.verifyTotp(secret, code)) {
      throw new HttpError(
        401,
        "El codigo 2FA es incorrecto o vencio.",
        "invalid_two_factor_code",
      );
    }
    const recoveryCodes = this.generateRecoveryCodes();
    await this.repository.enableTwoFactor(
      userId,
      "totp",
      secret,
      recoveryCodes.map((value) => this.hashSecret(value)),
    );
    return { enabled: true, method: "totp", recoveryCodes };
  }

  async disableTwoFactor(userId: number, payload: Record<string, unknown>) {
    const user = await this.repository.findUserForTwoFactor(userId);
    if (user.two_factor !== true) {
      return { enabled: false };
    }
    await this.assertTwoFactorCode(user, payload);
    await this.repository.disableTwoFactor(userId);
    return { enabled: false };
  }

  async verifyTwoFactorLogin(payload: Record<string, unknown>) {
    const challengeId = requiredString(
      payload.challengeId ?? payload.challenge_id,
      "Verificacion",
      80,
    );
    const code = optionalString(payload.code, 40);
    const recoveryCode = optionalString(
      payload.recoveryCode ?? payload.recovery_code,
      80,
    );
    if (code == null && recoveryCode == null) {
      throw new HttpError(
        400,
        "Ingresa el codigo 2FA o un codigo de recuperacion.",
        "validation_error",
      );
    }
    const challenge = await this.repository.findTwoFactorChallenge(challengeId);
    if (challenge == null || challenge.consumed_at != null) {
      throw new HttpError(
        401,
        "La verificacion 2FA no existe o ya fue usada.",
        "invalid_two_factor_challenge",
      );
    }
    if (new Date(String(challenge.expires_at)).getTime() <= Date.now()) {
      throw new HttpError(
        401,
        "El codigo 2FA vencio. Inicia sesion nuevamente.",
        "two_factor_challenge_expired",
      );
    }
    if (Number(challenge.failed_attempts ?? 0) >= 5) {
      throw new HttpError(
        423,
        "Demasiados intentos 2FA. Intenta mas tarde.",
        "two_factor_locked",
      );
    }
    const user = await this.repository.findUserForTwoFactor(
      Number(challenge.user_id),
    );
    let ok = false;
    if (recoveryCode != null) {
      ok = await this.consumeRecoveryCode(user, recoveryCode);
    } else if (challenge.method === "totp") {
      ok = this.verifyTotp(String(user.two_factor_secret ?? ""), String(code));
    } else {
      ok = this.hashSecret(String(code)) === challenge.code_hash;
    }
    if (!ok) {
      await this.repository.incrementTwoFactorChallengeAttempts(challengeId);
      throw new HttpError(
        401,
        "El codigo 2FA es incorrecto o vencio.",
        "invalid_two_factor_code",
      );
    }
    await this.repository.consumeTwoFactorChallenge(challengeId);
    await this.repository.updateLastSignIn(Number(user.id));
    return this.authResponse(
      {
        session: asRecord(challenge.session_payload),
        user: {
          id: String(
            asRecord(challenge.auth_user_payload).id ?? user.auth_user_id,
          ),
          email: optionalString(
            asRecord(challenge.auth_user_payload).email,
            200,
          ),
        },
      },
      user,
      asRecord(user.institutions),
    );
  }

  async logout(accessToken: string) {
    const response = await fetch(`${env.supabaseUrl}/auth/v1/logout`, {
      method: "POST",
      headers: {
        apikey: env.supabaseAnonKey,
        authorization: `Bearer ${accessToken}`,
      },
    });
    if (!response.ok && response.status !== 401) {
      throw new HttpError(400, "No se pudo cerrar sesion.", "logout_failed");
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

  private async createTwoFactorLoginChallenge(
    data: { session: unknown; user: { id: string; email?: string | null } },
    appUser: Record<string, unknown>,
  ) {
    if (this.isLocked(appUser.two_factor_locked_until)) {
      throw new HttpError(
        423,
        "2FA bloqueado temporalmente. Intenta mas tarde.",
        "two_factor_locked",
      );
    }
    const hasTotp =
      appUser.two_factor === true &&
      typeof appUser.two_factor_secret === "string" &&
      appUser.two_factor_secret.length > 0;
    const method: "email" | "totp" = hasTotp ? "totp" : "email";
    const code = method === "email" ? this.generateEmailCode() : null;
    const expiresAt = new Date(Date.now() + challengeTtlMs).toISOString();
    const challenge = await this.repository.createTwoFactorChallenge({
      userId: Number(appUser.id),
      institutionId: Number(appUser.institution_id),
      method,
      codeHash: code == null ? null : this.hashSecret(code),
      sessionPayload: asRecord(data.session),
      authUserPayload: { id: data.user.id, email: data.user.email ?? null },
      expiresAt,
    });
    let debugCode: string | null = null;
    if (code != null) {
      try {
        await emailService.sendTwoFactorCode(
          String(appUser.email),
          String(appUser.full_name ?? appUser.username ?? "usuario"),
          code,
        );
      } catch (error) {
        if (env.isProduction) throw error;
        debugCode = code;
      }
    }
    return {
      twoFactorRequired: true,
      challenge: {
        id: String(challenge.id),
        method,
        expiresAt,
        emailHint: this.maskEmail(String(appUser.email ?? "")),
        requiredByRole: false,
        ...(debugCode == null ? {} : { debugCode }),
      },
    };
  }

  private async assertTwoFactorCode(
    user: Record<string, unknown>,
    payload: Record<string, unknown>,
  ) {
    const code = optionalString(payload.code, 40);
    const recoveryCode = optionalString(
      payload.recoveryCode ?? payload.recovery_code,
      80,
    );
    if (recoveryCode != null) {
      if (await this.consumeRecoveryCode(user, recoveryCode)) return;
    } else if (
      code != null &&
      typeof user.two_factor_secret === "string" &&
      this.verifyTotp(user.two_factor_secret, code)
    ) {
      return;
    }
    throw new HttpError(
      401,
      "El codigo 2FA es incorrecto o vencio.",
      "invalid_two_factor_code",
    );
  }

  private async consumeRecoveryCode(
    user: Record<string, unknown>,
    recoveryCode: string,
  ) {
    const hashes = asList(user.two_factor_recovery_codes).filter(
      (entry): entry is string => typeof entry === "string",
    );
    const hash = this.hashSecret(recoveryCode.toUpperCase().replace(/\s/g, ""));
    if (!hashes.includes(hash)) return false;
    await this.repository.replaceRecoveryCodes(
      Number(user.id),
      hashes.filter((entry) => entry !== hash),
    );
    return true;
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
      const raw = crypto.randomBytes(5).toString("hex").toUpperCase();
      return `${raw.slice(0, 5)}-${raw.slice(5, 10)}`;
    });
  }

  private generateBase32Secret() {
    const bytes = crypto.randomBytes(20);
    let value = "";
    for (const byte of bytes) {
      value += base32Alphabet[byte % base32Alphabet.length];
    }
    return value;
  }

  private verifyTotp(secret: string, code: string) {
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

export const authFlowService = new AuthFlowService();
