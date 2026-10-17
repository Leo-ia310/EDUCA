import cors, { CorsOptions } from "cors";
import rateLimit, { ipKeyGenerator } from "express-rate-limit";
import helmet from "helmet";
import type { RequestHandler } from "express";

import { env } from "../lib/env";

/**
 * Solo los 401 (contraseña o código incorrectos, token inválido) gastan el cupo de fallos de la IP. Los demás
 * errores (400 de validación, 403, 404, 409…) son normales en el uso diario y, como la web llega toda desde
 * una misma IP, no deben acumularse contra todos los usuarios. Los 429 del cupo propio de un usuario
 * (ver auth.middleware) tampoco cuentan.
 */
const isNotAnIpFailure = (_req: unknown, res: { statusCode: number }) => res.statusCode !== 401;

const allowedOrigins = env.corsOrigin
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

export const securityHeaders = helmet({
  crossOriginEmbedderPolicy: false,
  contentSecurityPolicy: env.isProduction ? undefined : false,
});

export const corsMiddleware = cors({
  origin: corsOrigin,
  allowedHeaders: [
    "authorization",
    "x-client-info",
    "apikey",
    "content-type",
    "x-request-id",
  ],
  exposedHeaders: ["x-request-id"],
  methods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
} satisfies CorsOptions);

// Por IP y solo se cobran los fallos de autenticación (401): el uso normal no gasta el cupo, así que
// muchos usuarios detrás de una misma IP (p. ej. el servidor de la web) no se bloquean entre sí, pero
// los intentos fallidos (contraseñas erróneas, tokens falsos) siguen limitados. El uso normal de cada
// usuario autenticado se limita aparte, por usuario (ver lib/user-rate-limit.ts).
export const generalRateLimit = rateLimit({
  windowMs: env.rateLimitWindowMs,
  limit: env.rateLimitMax,
  skipSuccessfulRequests: true,
  requestWasSuccessful: isNotAnIpFailure,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  message: {
    ok: false,
    error: {
      code: "rate_limited",
      message: "Demasiadas solicitudes. Intenta de nuevo en unos minutos.",
    },
  },
});

// Tope más estricto para los fallos en las rutas /api (inicio de sesión, 2FA…), siempre por IP: la clave
// no puede depender de la cabecera Authorization, porque un cliente podría inventarla para abrir cupos nuevos.
export const authenticatedRateLimit = rateLimit({
  windowMs: env.rateLimitWindowMs,
  limit: env.authRateLimitMax,
  skipSuccessfulRequests: true,
  requestWasSuccessful: isNotAnIpFailure,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  keyGenerator: (req) => ipKeyGenerator(req.ip ?? "0.0.0.0"),
  message: {
    ok: false,
    error: {
      code: "rate_limited",
      message: "Demasiadas acciones autenticadas. Intenta de nuevo en unos minutos.",
    },
  },
});

export const noStore: RequestHandler = (_req, res, next) => {
  res.setHeader("cache-control", "no-store");
  next();
};

function corsOrigin(
  origin: string | undefined,
  callback: (err: Error | null, allow?: boolean) => void,
) {
  if (!origin) return callback(null, true);
  if (allowedOrigins.includes("*")) {
    if (env.isProduction) {
      return callback(
        new Error("CORS_ORIGIN=* no esta permitido en produccion."),
      );
    }
    return callback(null, true);
  }
  return callback(null, allowedOrigins.includes(origin));
}
