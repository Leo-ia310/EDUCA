import cors, { CorsOptions } from "cors";
import rateLimit, { ipKeyGenerator } from "express-rate-limit";
import helmet from "helmet";
import type { RequestHandler } from "express";

import { env } from "../lib/env";

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

export const generalRateLimit = rateLimit({
  windowMs: env.rateLimitWindowMs,
  limit: env.rateLimitMax,
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

export const authenticatedRateLimit = rateLimit({
  windowMs: env.rateLimitWindowMs,
  limit: env.authRateLimitMax,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  keyGenerator: (req) => {
    const auth = req.header("authorization") ?? "";
    return auth.length > 0
      ? auth.slice(-80)
      : ipKeyGenerator(req.ip ?? "0.0.0.0");
  },
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
