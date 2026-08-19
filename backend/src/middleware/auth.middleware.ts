import type { NextFunction, Response } from "express";

import { authRepository } from "../repositories/auth.repository";
import type { AppContext, AppRequest } from "../types/app-context";
import { HttpError } from "../lib/errors";
import { withRequestSupabase } from "../lib/supabase";
import { asList } from "../validators/common.validators";

export async function authMiddleware(
  req: AppRequest,
  _res: Response,
  next: NextFunction,
) {
  try {
    const token = bearerToken(req);
    await withRequestSupabase(token, async () => {
      req.appContext = await loadContextFromToken(token);
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

  const appUser = await authRepository.findAppUserByAuthUserId(
    authData.user.id,
  );
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
    userId: Number(appUser.id),
    institutionId: Number(appUser.institution_id),
    personId: appUser.person_id == null ? null : Number(appUser.person_id),
    fullName: String(appUser.full_name ?? "Usuario"),
    roles,
  };
}
