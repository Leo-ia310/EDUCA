import { env } from "../lib/env";
import { HttpError } from "../lib/errors";

export type SendEmailPayload = {
  to: string;
  subject: string;
  html: string;
  text?: string;
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
      },
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

  private escape(value: string) {
    return value
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
}

export const emailService = new EmailService();
