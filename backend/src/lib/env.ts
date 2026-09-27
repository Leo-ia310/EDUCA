import dotenv from "dotenv";

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
  if (!raw) return fallback;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`Invalid numeric environment variable: ${name}`);
  }
  return parsed;
}

function optionalBoolean(name: string, fallback = false) {
  const raw = optional(name);
  if (!raw) return fallback;
  return ["1", "true", "yes", "on"].includes(raw.toLowerCase());
}

const nodeEnv = optional("NODE_ENV", "development");

export const env = {
  nodeEnv,
  isProduction: nodeEnv === "production",
  port: optionalNumber("PORT", 3000),
  corsOrigin: optional("CORS_ORIGIN", "*"),
  trustProxy: optionalBoolean("TRUST_PROXY", nodeEnv === "production"),
  jsonLimit: optional("JSON_BODY_LIMIT", "512kb"),
  rateLimitWindowMs: optionalNumber("RATE_LIMIT_WINDOW_MS", 15 * 60 * 1000),
  rateLimitMax: optionalNumber("RATE_LIMIT_MAX", 300),
  authRateLimitMax: optionalNumber("AUTH_RATE_LIMIT_MAX", 120),
  fileUploadMaxBytes: optionalNumber("FILE_UPLOAD_MAX_BYTES", 10 * 1024 * 1024),
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
  passwordResetRedirectUrl: optional("PASSWORD_RESET_REDIRECT_URL"),
  emailProvider: optional("EMAIL_PROVIDER", "resend"),
  resendApiKey: optional("RESEND_API_KEY"),
  resendFromEmail: optional("RESEND_FROM_EMAIL", "no-reply@nivramop.com"),
  supabaseUrl: required("SUPABASE_URL"),
  supabaseAnonKey: required("SUPABASE_ANON_KEY"),
  supabaseServiceRoleKey: optional("SUPABASE_SERVICE_ROLE_KEY"),
  internalApiSecret: optional("INTERNAL_API_SECRET"),
  sendPushUrl: optional("SEND_PUSH_URL"),
};
