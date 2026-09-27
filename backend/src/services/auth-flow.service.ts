import { asList, asRecord, requiredString } from "../validators/common.validators";
import { env } from "../lib/env";
import { HttpError } from "../lib/errors";
import { requireSupabaseServiceRole, supabasePublic } from "../lib/supabase";
import { emailService } from "./email.service";
import {
  authFlowRepository,
  AuthFlowRepository,
} from "../repositories/auth-flow.repository";

export class AuthFlowService {
  constructor(
    private readonly repository: AuthFlowRepository = authFlowRepository,
  ) {}

  async login(payload: Record<string, unknown>) {
    const institutionCode = requiredString(
      payload.institutionCode ?? payload.institution_code ?? payload.schoolCode,
      "Código de colegio",
      50,
    );
    const username = requiredString(payload.username, "Usuario", 100);
    const password = requiredString(payload.password, "Contraseña", 200);

    const institution = await this.repository.findInstitutionByCode(
      institutionCode,
    );
    if (institution == null || institution.active === false) {
      throw new HttpError(
        401,
        "Credenciales inválidas.",
        "invalid_credentials",
      );
    }

    const appUser = await this.repository.findLoginUser(
      Number(institution.id),
      username,
    );
    if (appUser == null || appUser.active === false) {
      throw new HttpError(
        401,
        "Credenciales inválidas.",
        "invalid_credentials",
      );
    }
    if (this.isLocked(appUser.locked_until)) {
      throw new HttpError(
        423,
        "Usuario bloqueado temporalmente. Intenta más tarde.",
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
        "Credenciales inválidas.",
        "invalid_credentials",
      );
    }
    if (
      appUser.auth_user_id != null &&
      String(appUser.auth_user_id) !== data.user.id
    ) {
      throw new HttpError(
        403,
        "La cuenta de autenticación no coincide con el usuario institucional.",
        "forbidden",
      );
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
      throw new HttpError(401, "Refresh token inválido.", "unauthorized");
    }
    return {
      session: this.sessionPayload(data.session as unknown as Record<string, unknown>),
      authUser: { id: data.user.id, email: data.user.email ?? null },
    };
  }

  async recoverPassword(payload: Record<string, unknown>) {
    const institutionCode = requiredString(
      payload.institutionCode ?? payload.institution_code ?? payload.schoolCode,
      "Código de colegio",
      50,
    );
    const username = requiredString(payload.username, "Usuario", 100);
    const institution = await this.repository.findInstitutionByCode(
      institutionCode,
    );
    const appUser = institution == null
      ? null
      : await this.repository.findLoginUser(Number(institution.id), username);

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
        "Si la cuenta existe y tiene correo, Supabase Auth enviará instrucciones de recuperación.",
    };
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
      throw new HttpError(400, "No se pudo cerrar sesión.", "logout_failed");
    }
    return { ok: true };
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
        roles: asList(appUser.user_roles)
          .map((entry) =>
            (asRecord(asRecord(entry).roles).code ?? null)
          )
          .filter((role): role is string => typeof role === "string"),
      },
      institution: {
        id: String(institution.id),
        code: String(institution.code),
        name: String(institution.commercial_name ?? institution.name),
      },
    };
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
}

export const authFlowService = new AuthFlowService();
