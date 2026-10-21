import { randomUUID } from "node:crypto";
import { env } from "../src/lib/env";
import { InstitutionCatalogCache } from "../src/lib/institution-catalog-cache";

/** Live transport check in a unique short-lived probe namespace. No DB access,
 * no real users and no application cache keys. Never print endpoint or token.
 */
async function verify() {
  if (!env.upstashRedisRestUrl || !env.upstashRedisRestToken) {
    throw new Error("Redis is not configured");
  }
  const namespace = `${env.cacheNamespace}:verification:${randomUUID()}`;
  const keys = new Set<string>();
  const transport: typeof fetch = async (url, options) => {
    const args = JSON.parse(String(options?.body)) as string[];
    if (args[0] === "SET") keys.add(args[1]);
    return fetch(url, options);
  };
  const makeCache = () => new InstitutionCatalogCache({ url: env.upstashRedisRestUrl,
    token: env.upstashRedisRestToken, timeoutMs: env.redisTimeoutMs, namespace, fetch: transport });
  const missing = async (): Promise<never> => { throw new Error("Expected a Redis hit"); };
  try {
    const writer = makeCache(), reader = makeCache();
    await writer.read(1, async () => ({ scale: { id: 1, name: "Connection probe" }, status: "configured" }));
    await reader.read(1, missing);
    await writer.readAttendanceStatuses(1, async () => [
      { id: 1, name: "Connection probe", code: "VERIFY", counts_as_absent: false },
    ]);
    await reader.readAttendanceStatuses(1, missing);
    await writer.invalidate(1);
    let invalidated = false;
    await reader.read(1, async () => { invalidated = true; return { scale: null, status: "not_configured" }; });
    if (!invalidated || reader.metrics.hits !== 2 || writer.metrics.failures || reader.metrics.failures) {
      throw new Error("Redis cache verification failed");
    }
    console.log(JSON.stringify({ connected: true, crossClientHits: reader.metrics.hits,
      invalidationVerified: true, failures: 0 }));
  } finally {
    if (keys.size) {
      const response = await fetch(env.upstashRedisRestUrl, { method: "POST",
        headers: { Authorization: `Bearer ${env.upstashRedisRestToken}`, "Content-Type": "application/json" },
        body: JSON.stringify(["DEL", ...keys]), signal: AbortSignal.timeout(5000) });
      const data = await response.json() as { error?: unknown };
      if (!response.ok || data.error) throw new Error("Probe cleanup failed; keys expire automatically");
    }
  }
}
verify().catch(() => {
  console.error("Redis verification failed. Check configuration/connectivity; credentials hidden.");
  process.exitCode = 1;
});
