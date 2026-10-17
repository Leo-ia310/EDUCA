// Provider requests are intercepted; this check never sends email.
import assert from "node:assert/strict";
import { createRequire } from "node:module";
// Match the backend's CommonJS module cache when mutating its test config.
const require = createRequire(import.meta.url);
const { env } = require("../src/lib/env.ts") as typeof import("../src/lib/env");
const { HttpError } = require("../src/lib/errors.ts") as typeof import("../src/lib/errors");
const { EmailService } = require("../src/modules/auth/email.service.ts") as typeof import("../src/modules/auth/email.service");

async function main() {
  const originalFetch = globalThis.fetch;
  const original = { sender: env.resendFromEmail, key: env.resendApiKey, provider: env.emailProvider };
  const requests: Array<{ body: Record<string, unknown>; headers: Headers }> = [];
  globalThis.fetch = async (_url, options) => {
    requests.push({ body: JSON.parse(String(options?.body)), headers: new Headers(options?.headers) });
    return Response.json({ id: "fixture-email" });
  };
  try {
    env.emailProvider = "resend";
    env.resendApiKey = "re_fixture";
    const service = new EmailService();
    const payload = { to: "fixture@example.com", subject: "Fixture", html: "<p>Fixture</p>" };
    for (const sender of ["Nivra <no-reply@nivramop.com", "no-reply@nivramop.com>", "Nivra <not-an-email>", ""]) {
      env.resendFromEmail = sender;
      await assert.rejects(service.send(payload), error => error instanceof HttpError && error.status === 503 && error.code === "email_sender_invalid", `Must reject malformed sender: ${sender}`);
    }
    assert.equal(requests.length, 0, "Malformed senders must never reach Resend");
    for (const sender of ["Nivra <no-reply@nivramop.com>", "no-reply@nivramop.com"]) {
      env.resendFromEmail = ` ${sender} `;
      await service.sendTwoFactorCode(payload.to, "Fixture", "123456", "setup", "fixture-challenge");
      assert.equal(requests.at(-1)!.body.from, sender);
      assert.equal(requests.at(-1)!.headers.get("Idempotency-Key"), "2fa/fixture-challenge");
      assert.match(String(requests.at(-1)!.body.text), /5 minutos/);
    }
    env.resendApiKey = "";
    await assert.rejects(service.send(payload), error => error instanceof HttpError && error.status === 503 && error.code === "email_provider_unavailable");
    assert.equal(requests.length, 2);
    console.log("Email checks passed: sender validation, correct Resend payload, 2FA template/idempotency and missing credentials. No email sent.");
  } finally {
    globalThis.fetch = originalFetch;
    env.resendFromEmail = original.sender;
    env.resendApiKey = original.key;
    env.emailProvider = original.provider;
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
