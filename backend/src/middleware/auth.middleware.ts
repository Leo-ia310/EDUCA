import {assertAuthAvailable} from "../lib/auth-error";
import { sessionIdFromToken } from "../modules/auth/auth-flow.service";
import type { NextFunction, Response } from "express";
import { portalAccessService } from "../modules/portal-access/portal-access.service";

import { authRepository } from "../modules/auth/auth.repository";
import type { AppContext, AppRequest } from "../types/app-context";
import { HttpError } from "../lib/errors";
import { withRequestSupabase } from "../lib/supabase";
import { env } from "../lib/env";

export async function authMiddleware(
  req: AppRequest,
  res: Response,
  next: NextFunction,
) {
  try {
    const token = bearerToken(req);
    await withRequestSupabase(token, async () => {
      req.appContext = await loadContextFromToken(token, res);
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

async function loadContextFromToken(token: string, res: Response): Promise<AppContext> {
  const { data: authData, error: authError } = await authRepository.getAuthUser(token);
  if (authError || !authData.user) {
    assertAuthAvailable(authError);
    throw new HttpError(401, "Sesión inválida o expirada.", "unauthorized");
  }
  const sessionId = sessionIdFromToken(token);
  if (sessionId == null || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(sessionId)) {
    throw new HttpError(401, "Sesión inválida. Inicia sesión nuevamente.", "unauthorized");
  }
  // Auth has verified this exact token. Only the backend service credential can
  // invoke the context/quota RPC; handlers keep their user-scoped RLS client.
  const row = await authRepository.requestContext(authData.user.id, sessionId, env.rateLimitWindowMs, env.userRateLimitMax);
  res.setHeader("x-user-ratelimit-limit", String(row.limit));
  res.setHeader("x-user-ratelimit-remaining", String(row.remaining));
  res.setHeader("x-user-ratelimit-reset", String(row.resetsAt));
  if (row.allowed !== true) {
    res.setHeader("retry-after", String(row.retryAfterSeconds));
    throw new HttpError(429, "Demasiadas solicitudes. Intenta de nuevo más tarde.", "rate_limited");
  }
  return {
    authUserId: String(row.authUserId), sessionId: String(row.sessionId),
    userId: Number(row.userId), institutionId: Number(row.institutionId),
    personId: row.personId == null ? null : Number(row.personId), fullName: String(row.fullName ?? "Usuario"),
    roles: new Set((row.roles as string[]) ?? []),
    adminPermissions: Array.isArray(row.adminPermissions) ? row.adminPermissions.map(String) : null,
    teacherId: row.teacherId == null ? null : Number(row.teacherId),
    studentId: row.studentId == null ? null : Number(row.studentId),
    parentId: row.parentId == null ? null : Number(row.parentId),
    portalPermissions: row.portalPermissions as Record<string, boolean>,
  };
}
