import { env } from "../../lib/env";
import { HttpError } from "../../lib/errors";
import { EmailProviderBudget, EmailProviderError } from "../../lib/email-provider-budget";
export type SendEmailPayload = {
    to: string;
    subject: string;
    html: string;
    text?: string;
    idempotencyKey?: string;
};
export type AnnouncementEmailCheckpoint = {
    send: boolean;
    status: string;
    email?: string;
    fullName?: string;
    idempotencyKey?: string;
    validUntil?: string;
};
export class EmailService {
    constructor(private readonly budget: Pick<EmailProviderBudget, "acquire" | "defer"> = new EmailProviderBudget()) { }
    private sender() {
        if (env.emailProvider !== "resend") {
            throw new HttpError(503, "El envío de correos no está habilitado. Contacta a la administración.", "email_provider_unavailable");
        }
        if (!env.resendApiKey) {
            throw new HttpError(503, "El servicio de correo no está configurado. Contacta a la administración.", "email_provider_unavailable");
        }
        // Accept an email address or a complete display-name <address> pair.
        // A missing angle bracket is rejected before calling the mail provider.
        const sender = env.resendFromEmail.trim();
        const address = /^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/;
        const named = sender.match(/^[^<>\r\n]+<([^<>\s]+)>$/);
        if (!address.test(sender) && !(named && address.test(named[1]))) {
            throw new HttpError(503, "El remitente de correo está mal configurado. Contacta a la administración.", "email_sender_invalid");
        }
        return sender;
    }
    async send(payload: SendEmailPayload) {
        const sender = this.sender();
        await this.budget.acquire();
        return this.dispatch(payload, sender);
    }
    async sendPreparedAnnouncement(title: string, message: string, prepare: () => Promise<AnnouncementEmailCheckpoint>): Promise<{
        status: string;
        id?: string;
    }> {
        const sender = this.sender();
        await this.budget.acquire();
        const target = await prepare();
        if (!target.send)
            return { status: target.status };
        if (target.validUntil && (!Number.isFinite(Date.parse(target.validUntil)) || Date.parse(target.validUntil) <= Date.now()))
            return { status: "needs_review" };
        const result = await this.dispatch(this.announcementPayload(target.email!, target.fullName!, title, message, target.idempotencyKey), sender);
        return { status: "sent", id: result.id as string };
    }
    private async dispatch(payload: SendEmailPayload, sender: string) {
        let response: Response;
        try {
            response = await fetch("https://api.resend.com/emails", {
                method: "POST",
                headers: {
                    authorization: `Bearer ${env.resendApiKey}`,
                    "content-type": "application/json",
                    "user-agent": "Nivra/1.0",
                    ...(payload.idempotencyKey ? { "Idempotency-Key": payload.idempotencyKey } : {}),
                },
                signal: AbortSignal.timeout(15000),
                body: JSON.stringify({
                    from: sender,
                    to: [payload.to],
                    subject: payload.subject,
                    html: payload.html,
                    text: payload.text,
                }),
            });
        }
        catch {
            throw new EmailProviderError("No se pudo confirmar el envío de correo.", "email_provider_timeout", true, 5000);
        }
        if (!response.ok) {
            const body = await response.json().catch(() => ({})) as {
                name?: string;
            };
            if (response.status === 429) {
                const quota = ["daily_quota_exceeded", "monthly_quota_exceeded"].includes(body.name ?? "");
                const seconds = Number(response.headers.get("retry-after"));
                const retryMs = Number.isFinite(seconds) && seconds > 0 ? Math.min(86400000, Math.ceil(seconds * 1000)) : 5000;
                await this.budget.defer(retryMs);
                throw new EmailProviderError(quota ? "Se agotó el cupo del servicio de correo. Contacta a la administración." : "El servicio de correo está ocupado. Intenta nuevamente.", quota ? "email_quota_exceeded" : "email_rate_limited", !quota, retryMs);
            }
            if (response.status === 409 && body.name === "concurrent_idempotent_requests")
                throw new EmailProviderError("El envío anterior sigue en proceso.", "email_request_in_progress", true, 1000);
            if (response.status === 409)
                throw new EmailProviderError("El envío requiere revisión antes de volver a enviar el correo.", "email_idempotency_conflict", false);
            if (response.status === 401 || response.status === 403)
                throw new EmailProviderError("El servicio de correo necesita revisar su configuración.", "email_provider_unavailable", false);
            throw new EmailProviderError("No se pudo enviar el correo.", "email_send_failed", response.status >= 500, 5000);
        }
        const result = await response.json().catch(() => null) as Record<string, unknown> | null;
        if (!result || typeof result.id !== "string" || !result.id)
            throw new EmailProviderError("No se pudo confirmar el envío de correo.", "email_provider_response_invalid", true, 5000);
        return result;
    }
    async sendPasswordRecovery(to: string, fullName: string, recoveryUrl: string) {
        return this.send({
            to,
            subject: "Recupera tu contraseña de Nivra",
            html: [
                `<p>Hola ${this.escape(fullName || "usuario")},</p>`,
                "<p>Recibimos una solicitud para recuperar tu contraseña de Nivra.</p>",
                `<p><a href="${this.escape(recoveryUrl)}">Cambiar contraseña</a></p>`,
                "<p>Si no solicitaste este cambio, puedes ignorar este correo.</p>",
            ].join(""),
            text: `Recupera tu contraseña de Nivra: ${recoveryUrl}`,
        });
    }
    async sendTwoFactorCode(to: string, fullName: string, code: string, purpose = "login", id?: string) {
        const action = purpose === "setup" ? "activar la autenticación en dos pasos" : purpose === "disable" ? "desactivar la autenticación en dos pasos" : "completar tu inicio de sesión";
        return this.send({
            to,
            subject: "Código de seguridad de Nivra",
            idempotencyKey: id ? `2fa/${id}` : undefined,
            html: [
                `<p>Hola ${this.escape(fullName || "usuario")},</p>`,
                `<p>Usa este código para ${action}:</p>`,
                `<p style="font-size: 28px; font-weight: 700; letter-spacing: 4px;">${this.escape(code)}</p>`,
                "<p>El código vence en 5 minutos y solo se puede usar una vez. Si no solicitaste esta acción, protege tu cuenta.</p>",
            ].join(""),
            text: `Tu código de seguridad de Nivra es: ${code}. Vence en 5 minutos.`,
        });
    }
    async sendInvitation(to: string, fullName: string, invitationUrl: string) {
        return this.send({
            to,
            subject: "Invitación a Nivra",
            html: [
                `<p>Hola ${this.escape(fullName || "usuario")},</p>`,
                "<p>Te invitaron a activar tu cuenta en Nivra.</p>",
                `<p><a href="${this.escape(invitationUrl)}">Activar cuenta</a></p>`,
            ].join(""),
            text: `Activa tu cuenta de Nivra: ${invitationUrl}`,
        });
    }
    async sendAnnouncement(to: string, fullName: string, title: string, message: string, idempotencyKey?: string) {
        return this.send(this.announcementPayload(to, fullName, title, message, idempotencyKey));
    }
    private announcementPayload(to: string, fullName: string, title: string, message: string, idempotencyKey?: string): SendEmailPayload {
        const safeTitle = this.escape(title), safeMessage = this.escape(message).replace(/\n/g, "<br>");
        return { to, subject: `Nuevo anuncio: ${title}`, idempotencyKey,
            html: [`<p>Hola ${this.escape(fullName || "usuario")},</p>`, `<p><strong>${safeTitle}</strong></p>`, `<p>${safeMessage}</p>`, "<p>También puedes ver este aviso dentro de Nivra.</p>"].join(""),
            text: `Nuevo anuncio: ${title}\n\n${message}` };
    }
    private escape(value: string) {
        return value
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;");
    }
}
export const emailService = new EmailService();
