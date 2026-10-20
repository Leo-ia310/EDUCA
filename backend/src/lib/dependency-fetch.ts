import { env } from "./env";
import { currentRequestSignal } from "./request-lifetime";
import { operationalMetrics } from "./operational-metrics";
/** Deadline covers response body consumption too. Supabase receives structured
 * transport errors; mutations may have committed and must replay their UUID. */
export const dependencyFetch: typeof fetch = async (input, init) => {
    const request = input instanceof Request ? input : undefined;
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
    const category = url.pathname.startsWith("/auth/") ? "auth" : url.pathname.startsWith("/rest/") ? "database" : url.pathname.startsWith("/storage/") ? "storage" : "supabase";
    const signals = [AbortSignal.timeout(env.dependencyTimeoutMs), currentRequestSignal(), init?.signal, request?.signal].filter((signal): signal is AbortSignal => signal != null);
    const started = performance.now();
    try {
        const response = await fetch(input, { ...init, signal: AbortSignal.any(signals) });
        operationalMetrics.dependency(category, response.status, performance.now() - started);
        return response;
    }
    catch (error) {
        operationalMetrics.dependency(category, 0, performance.now() - started);
        throw error;
    }
};
