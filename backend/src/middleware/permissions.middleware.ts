import type { NextFunction, Response } from "express";

import { requireAppContext } from "./auth.middleware";
import { HttpError } from "../lib/errors";
import { permissionsService } from "../services/permissions.service";
import type { AppRequest } from "../types/app-context";

export function requireRoles(roles: string[]) {
  return (req: AppRequest, _res: Response, next: NextFunction) => {
    try {
      permissionsService.requireRole(requireAppContext(req), roles);
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireAdmin(req: AppRequest, _res: Response, next: NextFunction) {
  try {
    const ctx = requireAppContext(req);
    if (!permissionsService.isAdmin(ctx)) {
      throw new HttpError(403, "Solo administración puede realizar esta acción.", "forbidden");
    }
    next();
  } catch (error) {
    next(error);
  }
}
