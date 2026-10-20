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
  if(res.headersSent || res.destroyed)return;
  const parser=error as {type?:string};
  if(parser?.type==='entity.parse.failed')error=new HttpError(400,"JSON inválido.","invalid_json");
  else if(parser?.type==='entity.too.large')error=new HttpError(413,"El cuerpo excede el tamaño permitido.","payload_too_large");
  else if(parser?.type==='encoding.unsupported'||parser?.type==='charset.unsupported')error=new HttpError(415,"Codificación no admitida.","unsupported_encoding");
  if (isHttpError(error)) {
    if(error.retryAfter!=null)res.setHeader("retry-after",String(error.retryAfter));
    return res.status(error.status).json({
      ok: false,
      error: { code: error.code, message: error.message, requestId },
    });
  }

  console.error({ event:"request_failed",requestId,errorType:error instanceof Error?error.name:"unknown" });
  return res.status(500).json({
    ok: false,
    error: {
      code: "internal_error",
      message: "Error interno del backend.",
      requestId,
    },
  });
}
