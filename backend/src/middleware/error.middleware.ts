import type { NextFunction, Request, RequestHandler, Response } from "express";

import { HttpError, isHttpError } from "../lib/errors";
import type { AppRequest } from "../types/app-context";

export function asyncHandler(handler: RequestHandler): RequestHandler {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

export function notFoundHandler(
  req: Request,
  _res: Response,
  next: NextFunction,
) {
  next(
    new HttpError(
      404,
      `Ruta no encontrada: ${req.method} ${req.originalUrl}`,
      "not_found",
    ),
  );
}

export function errorHandler(
  error: unknown,
  req: Request,
  res: Response,
  _next: NextFunction,
) {
  const requestId = (req as AppRequest).requestId;
  if (isHttpError(error)) {
    return res.status(error.status).json({
      ok: false,
      error: { code: error.code, message: error.message, requestId },
    });
  }

  console.error({ requestId, error });
  return res.status(500).json({
    ok: false,
    error: {
      code: "internal_error",
      message: "Error interno del backend.",
      requestId,
    },
  });
}
