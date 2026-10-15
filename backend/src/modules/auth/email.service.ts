import { env } from "../../lib/env";
import { HttpError } from "../../lib/errors";

export type SendEmailPayload = {
  to: string;
  subject: string;
  html: string;
  text?: string;
  idempotencyKey?: string;
};

export class EmailService {
  async send(payload: SendEmailPayload) {
    if (env.emailProvider !== "resend") {
      throw new HttpError(
        503,
        "Proveedor de correo no configurado.",
        "email_provider_unavailable",
      );
    }
    if (!env.resendApiKey) {
      throw new HttpError(
        503,
        "RESEND_API_KEY no está configurada.",
        "email_provider_unavailable",
      );
    }

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${env.resendApiKey}`,
        "content-type": "application/json",
        ...(payload.idempotencyKey ? { "Idempotency-Key": payload.idempotencyKey } : {}),
      },
      signal: AbortSignal.timeout(15000),
      body: JSON.stringify({
        from: env.resendFromEmail,
        to: [payload.to],
        subject: payload.subject,
        html: payload.html,
        text: payload.text,
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new HttpError(
        502,
        `Resend no pudo enviar el correo: ${body}`,
        "email_send_failed",
      );
    }

    return response.json() as Promise<Record<string, unknown>>;
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

  async sendTwoFactorCode(to: string, fullName: string, code: string) {
    return this.send({
      to,
      subject: "Código de seguridad de Nivra",
      html: [
        `<p>Hola ${this.escape(fullName || "usuario")},</p>`,
        "<p>Usa este código para completar tu inicio de sesión:</p>",
        `<p style="font-size: 28px; font-weight: 700; letter-spacing: 4px;">${this.escape(code)}</p>`,
        "<p>El código vence en 5 minutos. Si no intentaste entrar, cambia tu contraseña.</p>",
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

  async sendAnnouncement(
    to: string,
    fullName: string,
    title: string,
    message: string,
    idempotencyKey?: string,
  ) {
    const safeTitle = this.escape(title);
    const safeMessage = this.escape(message).replace(/\n/g, "<br>");
    return this.send({
      to,
      subject: `Nuevo anuncio: ${title}`,
      idempotencyKey,
      html: [
        `<p>Hola ${this.escape(fullName || "usuario")},</p>`,
        `<p><strong>${safeTitle}</strong></p>`,
        `<p>${safeMessage}</p>`,
        "<p>También puedes ver este aviso dentro de Nivra.</p>",
      ].join(""),
      text: `Nuevo anuncio: ${title}\n\n${message}`,
    });
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

