import { env } from "./env";
import { HttpError } from "./errors";

type Bucket = { count: number; resetAt: number };

const buckets = new Map<number, Bucket>();
let lastSweep = 0;

/**
 * Cupo por usuario autenticado (ventana fija en memoria). Se cobra después de validar el token, así que
 * un usuario no gasta el cupo de otro ni de la IP compartida (la web llega toda desde el servidor Next),
 * y un token falso no abre cupos nuevos. Con varias instancias del backend cada una cuenta por separado.
 */
export function consumeUserQuota(userId: number, now = Date.now()) {
  if (now - lastSweep > env.rateLimitWindowMs) {
    for (const [id, bucket] of buckets) if (bucket.resetAt <= now) buckets.delete(id);
    lastSweep = now;
  }
  let bucket = buckets.get(userId);
  if (!bucket || bucket.resetAt <= now) {
    bucket = { count: 0, resetAt: now + env.rateLimitWindowMs };
    buckets.set(userId, bucket);
  }
  bucket.count += 1;
  if (bucket.count > env.userRateLimitMax) {
    throw new HttpError(429, "Demasiadas solicitudes. Intenta de nuevo en unos minutos.", "rate_limited");
  }
}
