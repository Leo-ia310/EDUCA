import { setTimeout as delay } from "node:timers/promises";
import { env } from "./env";
import { HttpError } from "./errors";
import { requireSupabaseServiceRole } from "./supabase";
export class EmailProviderError extends HttpError {
    constructor(message: string, code: string, readonly retryable: boolean, readonly retryAfterMs = 0) {
        super(retryable || ["email_quota_exceeded", "email_provider_unavailable"].includes(code) ? 503 : 502, message, code);
    }
}
export class EmailProviderBudget {
    constructor(private readonly client?: any, private readonly sleep: (ms: number) => Promise<unknown> = delay) { }
    async acquire() {
        const { data, error } = await (this.client ?? requireSupabaseServiceRole()).rpc("reserve_provider_request", {
            p_provider: "resend", p_interval_ms: env.emailIntervalMs, p_max_wait_ms: 5000,
        });
        if (error || !data || typeof data.allowed !== "boolean" || !Number.isFinite(data.waitMs) || data.waitMs < 0)
            throw new EmailProviderError("No se pudo reservar el envío de correo.", "email_budget_unavailable", true, 5000);
        if (!data.allowed)
            throw new EmailProviderError("El correo está ocupado. Intenta nuevamente en unos segundos.", "email_rate_limited", true, data.waitMs);
        if (data.waitMs > 0)
            await this.sleep(data.waitMs);
    }
    async defer(ms: number) {
        const { error } = await (this.client ?? requireSupabaseServiceRole()).rpc("defer_provider_requests", { p_provider: "resend", p_delay_ms: Math.min(86400000, Math.max(0, Math.ceil(ms))) });
        if (error)
            throw new EmailProviderError("No se pudo actualizar el cupo de correo.", "email_budget_unavailable", true, 5000);
    }
}
