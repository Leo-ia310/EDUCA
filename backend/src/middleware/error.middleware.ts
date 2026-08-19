import type { NextFunction, Request, RequestHandler, Response } from "express";

import { HttpError, isHttpError } from "../lib/errors";

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
  _req: Request,
  res: Response,
  _next: NextFunction,
) {
  if (isHttpError(error)) {
    return res.status(error.status).json({
      ok: false,
      error: { code: error.code, message: error.message },
    });
  }

  console.error(error);
  return res.status(500).json({
    ok: false,
    error: {
      code: "internal_error",
      message: "Error interno del backend.",
    },
  });
}
