import { sessionIdFromToken } from "../modules/auth/auth-flow.service";
import type { NextFunction, Response } from "express";
import { portalAccessService } from "../modules/portal-access/portal-access.service";

import { authRepository } from "../modules/auth/auth.repository";
import type { AppContext, AppRequest } from "../types/app-context";
import { HttpError } from "../lib/errors";
import { currentSupabaseClient, withRequestSupabase } from "../lib/supabase";
import { asList } from "../validators/common.validators";
import { consumeUserQuota } from "../lib/user-rate-limit";

export async function authMiddleware(
  req: AppRequest,
  res: Response,
  next: NextFunction,
) {
  try {
    const token = bearerToken(req);
    await withRequestSupabase(token, async () => {
      req.appContext = await loadContextFromToken(token);
      try {
        consumeUserQuota(req.appContext.userId);
      } catch (error) {
        res.locals.userQuotaExceeded = true;
        throw error;
      }
      await portalAccessService.enforceRequest(req.appContext, req.originalUrl, req.method, (req.body ?? {}) as Record<string,unknown>);
      next();
    });
  } catch (error) {
    next(error);
  }
}

export function requireAppContext(req: AppRequest): AppContext {
  if (req.appContext == null) {
    throw new HttpError(401, "Sesión requerida.", "unauthorized");
  }
  return req.appContext;
}

function bearerToken(req: AppRequest) {
  const auth = req.header("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    throw new HttpError(401, "Sesión requerida.", "unauthorized");
  }
  return token;
}

async function loadContextFromToken(token: string): Promise<AppContext> {
  const { data: authData, error: authError } =
    await authRepository.getAuthUser(token);
  if (authError || !authData.user) {
    throw new HttpError(401, "Sesión inválida o expirada.", "unauthorized");
  }

  let appUser;
  try {
    appUser = await authRepository.findAppUserByAuthUserId(authData.user.id);
  } catch (error) {
    const {data} = await currentSupabaseClient().rpc("auth_2fa_session_allowed");
    if (data === false) throw new HttpError(403,"Completa la verificación de seguridad e inicia sesión nuevamente.","two_factor_required");
    throw error;
  }
  const roles = new Set(
    asList(appUser.user_roles)
      .map((entry) =>
        ((entry as Record<string, unknown>).roles as
          | Record<string, unknown>
          | null)?.code
      )
      .filter((code): code is string => typeof code === "string"),
  );
  if (roles.size === 0) {
    throw new HttpError(403, "Usuario sin roles asignados.", "forbidden");
  }

  return {
    authUserId: authData.user.id,
    sessionId: sessionIdFromToken(token),
    userId: Number(appUser.id),
    institutionId: Number(appUser.institution_id),
    personId: appUser.person_id == null ? null : Number(appUser.person_id),
    fullName: String(appUser.full_name ?? "Usuario"),
    roles,
    adminPermissions: Array.isArray(appUser.admin_permissions)
      ? (appUser.admin_permissions as unknown[]).map(String)
      : null,
  };
}
