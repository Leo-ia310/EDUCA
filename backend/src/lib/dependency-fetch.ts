import { env } from "./env";
import { currentRequestSignal } from "./request-lifetime";
import { operationalMetrics } from "./operational-metrics";
import {dependencyAdmission,databaseAdmission} from './dependency-admission';
/** Deadline covers response body consumption too. Supabase receives structured
 * transport errors; mutations may have committed and must replay their UUID. */
export const dependencyFetch: typeof fetch = async (input, init) => {
    const request = input instanceof Request ? input : undefined;
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
    const category = url.pathname.startsWith("/auth/") ? "auth" : url.pathname.startsWith("/rest/") ? "database" : url.pathname.startsWith("/storage/") ? "storage" : "supabase";
    const signals = [AbortSignal.timeout(env.dependencyTimeoutMs), currentRequestSignal(), init?.signal, request?.signal].filter((signal): signal is AbortSignal => signal != null);
    const started = performance.now();
    const signal = AbortSignal.any(signals);
    let release: (() => void) | undefined;
    let releaseDatabase: (() => void) | undefined;
    try {
        // The same deadline includes queue time. Once headers arrive, Auth or
        // PostgREST has finished the query. Keep its original streaming Response.
        // Acquire database admission first so a queued SQL call does not occupy
        // the shared slots needed by short Auth verifications.
        if (category === 'database') releaseDatabase = await databaseAdmission.acquire(signal);
        if (category === 'auth' || category === 'database') release = await dependencyAdmission.acquire(signal);
        signal.throwIfAborted();
        const response = await fetch(input, { ...init, signal });
        operationalMetrics.dependency(category, response.status, performance.now() - started);
        return response;
    }
    catch (error) {
        operationalMetrics.dependency(category, 0, performance.now() - started);
        throw error;
    }
    finally { release?.(); releaseDatabase?.(); }
};
