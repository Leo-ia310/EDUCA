import dotenv from "dotenv";
if (process.env.NODE_ENV !== "test")
    dotenv.config();
function required(name: string) {
    const value = process.env[name];
    if (value == null || value.trim().length === 0) {
        throw new Error(`Missing required environment variable: ${name}`);
    }
    return value.trim();
}
function optional(name: string, fallback = "") {
    const value = process.env[name];
    return value == null || value.trim().length === 0 ? fallback : value.trim();
}
function optionalNumber(name: string, fallback: number) {
    const raw = optional(name);
    if (!raw)
        return fallback;
    const parsed = Number(raw);
    if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new Error(`Invalid numeric environment variable: ${name}`);
    }
    return parsed;
}
function optionalBoolean(name: string, fallback = false) {
    const raw = optional(name);
    if (!raw)
        return fallback;
    if (["1", "true", "yes", "on"].includes(raw.toLowerCase()))
        return true;
    if (["0", "false", "no", "off"].includes(raw.toLowerCase()))
        return false;
    throw new Error(`Invalid boolean environment variable: ${name}`);
}
function optionalInteger(name: string, fallback: number, max = 2147483647, min = 1) {
    const value = optionalNumber(name, fallback);
    if (!Number.isInteger(value) || value > max || value < min)
        throw new Error(`Invalid integer environment variable: ${name}`);
    return value;
}
const nodeEnv = optional("NODE_ENV", "development");
export const env = {
    nodeEnv,
    isProduction: nodeEnv === "production",
    port: optionalInteger("PORT", 3000, 65535),
    dependencyTimeoutMs: optionalInteger("DEPENDENCY_TIMEOUT_MS", 15000, 60000),
    requestTimeoutMs: optionalInteger("REQUEST_TIMEOUT_MS", 60000, 180000),
    maxConcurrentRequests: optionalInteger("MAX_CONCURRENT_REQUESTS", 100, 2000),
    shutdownTimeoutMs: optionalInteger("SHUTDOWN_TIMEOUT_MS", 25000, 120000),
    corsOrigin: optional("CORS_ORIGIN", "*"),
    trustProxy: optionalBoolean("TRUST_PROXY", nodeEnv === "production"),
    jsonLimit: optional("JSON_BODY_LIMIT", "512kb"),
    rateLimitWindowMs: optionalInteger("RATE_LIMIT_WINDOW_MS", 15 * 60 * 1000, 86400000),
    rateLimitMax: optionalInteger("RATE_LIMIT_MAX", 300, 1000000),
    authRateLimitMax: optionalInteger("AUTH_RATE_LIMIT_MAX", 120, 1000000),
    /** Solicitudes por usuario autenticado y ventana (la web consulta cada pocos segundos). */
    userRateLimitMax: optionalInteger("USER_RATE_LIMIT_MAX", 1200, 1000000),
    fileUploadMaxBytes: optionalInteger("FILE_UPLOAD_MAX_BYTES", 10 * 1024 * 1024, 100 * 1024 * 1024),
    fileAllowedMimeTypes: optional("FILE_ALLOWED_MIME_TYPES", [
        "application/pdf",
        "image/jpeg",
        "image/png",
        "image/webp",
        "text/plain",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ].join(",")),
    passwordResetRedirectUrl: optional("PASSWORD_RESET_REDIRECT_URL", nodeEnv === "production" ? "" : "https://nivramop.com/reset-password"),
    emailProvider: optional("EMAIL_PROVIDER", "resend"),
    resendApiKey: optional("RESEND_API_KEY"),
    resendFromEmail: optional("RESEND_FROM_EMAIL", "no-reply@nivramop.com"),
    emailIntervalMs: optionalInteger("EMAIL_MIN_INTERVAL_MS", 600, 60000, 100),
    announcementWorkers: optionalInteger("ANNOUNCEMENT_WORKERS", 2, 4),
    supabaseUrl: required("SUPABASE_URL"),
    supabaseAnonKey: required("SUPABASE_ANON_KEY"),
    supabaseServiceRoleKey: optional("SUPABASE_SERVICE_ROLE_KEY"),
    internalApiSecret: optional("INTERNAL_API_SECRET"),
    // Web Push (VAPID) enviado directo desde este backend (sin Edge Function).
    vapidPublicKey: optional("VAPID_PUBLIC_KEY"),
    vapidPrivateKey: optional("VAPID_PRIVATE_KEY"),
    vapidSubject: optional("VAPID_SUBJECT", "mailto:soporte@nivramop.com"),
};
