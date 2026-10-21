import { env } from "./env";
import { InstitutionCatalogCache } from "./institution-catalog-cache";

// One client/circuit/metrics scope per process; secrets never leave the backend.
export const institutionCatalogCache = new InstitutionCatalogCache({
  url: env.upstashRedisRestUrl,
  token: env.upstashRedisRestToken,
  timeoutMs: env.redisTimeoutMs,
  namespace: `${env.cacheNamespace}:${new URL(env.supabaseUrl).host}`,
});
