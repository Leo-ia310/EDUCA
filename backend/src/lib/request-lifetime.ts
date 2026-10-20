import { AsyncLocalStorage } from "node:async_hooks";
import type { RequestHandler } from "express";
import { HttpError } from "./errors";
import { operationalMetrics } from "./operational-metrics";
type Lifetime = {
    signal: AbortSignal;
};
const lifetimes = new AsyncLocalStorage<Lifetime>();
const activeControllers = new Set<AbortController>();
let draining = false;
export function currentRequestSignal() { return lifetimes.getStore()?.signal; }
export function detached<T>(operation: () => T) { return lifetimes.exit(operation); }
export function beginDrain() { draining = true; }
export function abortRequests() {
    for (const controller of activeControllers)
        controller.abort();
}
export function requestRuntime() { return { active: activeControllers.size, draining }; }
export function requestLifetime({ maxConcurrent = 100, timeoutMs = 60000 } = {}): RequestHandler {
    return (req, res, next) => {
        if (req.path === "/health" || req.path === "/ready" || req.path === "/internal/metrics")
            return next();
        if (draining)
            return next(new HttpError(503, "El servidor se está reiniciando. Reintenta con la misma clave.", "server_draining", 2));
        if (activeControllers.size >= maxConcurrent)
            return next(new HttpError(503, "El servidor está ocupado. Reintenta con la misma clave.", "server_busy", 2));
        const controller = new AbortController(), start = performance.now();
        activeControllers.add(controller);
        let finished = false;
        const cleanup = () => {
            if (finished)
                return;
            finished = true;
            clearTimeout(timer);
            req.off("aborted", abort);
            activeControllers.delete(controller);
            // Only route templates are labels. Never query strings, IDs, emails or bodies.
            const route = req.route?.path;
            operationalMetrics.request(req.method, typeof route === "string" ? `${req.baseUrl}${route}` : "unmatched", res.statusCode, performance.now() - start);
        };
        const abort = () => { controller.abort(); };
        const timer = setTimeout(() => {
            controller.abort();
            if (!res.headersSent)
                res.setHeader("retry-after", "2").status(504).json({ ok: false, error: { code: "request_timeout", message: "No se pudo confirmar a tiempo. Reintenta con la misma clave.", requestId: res.getHeader("x-request-id") } });
            else
                res.destroy();
        }, timeoutMs);
        timer.unref();
        req.once("aborted", abort);
        res.once("finish", cleanup);
        res.once("close", () => {
            if (!res.writableFinished)
                abort();
            cleanup();
        });
        lifetimes.run({ signal: controller.signal }, next);
    };
}
