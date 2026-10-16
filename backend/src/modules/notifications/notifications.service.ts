import { createHash } from "node:crypto";

import webpush from "web-push";

import { assertNoDbError } from "../../lib/db";
import { env } from "../../lib/env";
import { HttpError } from "../../lib/errors";
import { emailService } from "../auth/email.service";
import { requiredString } from "../../validators/common.validators";
import {
  notificationsRepository,
  NotificationsRepository,
} from "./notifications.repository";
import type { AppContext } from "../../types/app-context";

export class NotificationsService {
  constructor(
    private readonly repository: NotificationsRepository =
      notificationsRepository,
  ) {}

  async saveWebPushDevice(
    ctx: AppContext,
    payload: Record<string, unknown>,
  ) {
    const endpoint = requiredString(payload.endpoint, "Endpoint push", 2000);
    const pushToken = requiredString(payload.pushToken, "Token push", 5000);
    // Los endpoints de push superan los 150 caracteres de `device_uuid`: se
    // guarda su huella SHA-256 como identificador del dispositivo.
    const deviceKey = createHash("sha256").update(endpoint).digest("hex");
    const existing = await this.repository.findDevice(ctx.userId, deviceKey);
    if (existing == null) {
      await this.repository.insertDevice({
        user_id: ctx.userId,
        device_uuid: deviceKey,
        platform: "web",
        push_token: pushToken,
        active: true,
        last_synced_at: new Date().toISOString(),
      });
    } else {
      const { error } = await this.repository.updateDevice(existing.id, {
        push_token: pushToken,
        active: true,
        last_synced_at: new Date().toISOString(),
      });
      assertNoDbError(error);
    }
    return { ok: true };
  }

  /** Notificaciones reales del usuario autenticado (su cuenta e institución). */
  async listMine(ctx: AppContext) {
    const rows = await this.repository.listForUser(
      ctx.userId,
      ctx.institutionId,
    );
    return rows.map((row) => {
      const type = row.catalog_notification_types as
        | { code?: string }
        | null;
      return {
        id: String(row.id),
        channel: this.channelForCatalogCode(type?.code),
        title: row.title ?? "",
        body: row.message ?? "",
        data: row.data ?? {},
        read: row.read === true,
        receivedAt: row.created_at,
      };
    });
  }

  private channelForCatalogCode(code?: string) {
    switch (code) {
      case "MSG":
        return "message";
      case "TASK":
        return "task";
      case "GRADE":
        return "grade";
      case "ATT":
        return "attendance";
      case "ANN":
        return "announcement";
      case "PAY":
        return "payment";
      default:
        return "system";
    }
  }

  async markRead(ctx: AppContext, id?: number) {
    const { error } = await this.repository.markRead(
      ctx.userId,
      ctx.institutionId,
      id,
    );
    assertNoDbError(error);
    return { ok: true };
  }

  async remove(ctx: AppContext, id?: number) {
    const { error } = await this.repository.deleteForUser(
      ctx.userId,
      ctx.institutionId,
      id,
    );
    assertNoDbError(error);
    return { ok: true };
  }

  async getPreferences(ctx: AppContext) {
    const row = await this.repository.getPreferences(
      ctx.userId,
      ctx.institutionId,
    );
    return {
      emailEnabled: row.email_notifications_enabled !== false,
    };
  }

  async updatePreferences(
    ctx: AppContext,
    payload: Record<string, unknown>,
  ) {
    const update: Record<string, unknown> = {};
    // Acepta el nombre canónico y sus equivalentes para no ignorar en silencio
    // un valor mandado con otro nombre.
    const email = payload.emailEnabled ??
      payload.emailNotifications ??
      payload.email_notifications_enabled ??
      payload.email;
    if (email != null) {
      if (typeof email !== "boolean") {
        throw new HttpError(
          400,
          "Preferencia de correo inválida: debe ser true o false.",
          "validation_error",
        );
      }
      update.email_notifications_enabled = email;
    }
    if (Object.keys(update).length === 0) {
      throw new HttpError(
        400,
        "Indica la preferencia a guardar (emailEnabled: true/false).",
        "validation_error",
      );
    }
    const row = await this.repository.updatePreferences(
      ctx.userId,
      ctx.institutionId,
      update,
    );
    return {
      emailEnabled: row.email_notifications_enabled !== false,
    };
  }

  /**
   * Crea una notificación real para cada usuario indicado (y envía el push si
   * está configurado). Un fallo aquí nunca debe romper la acción que la origina.
   */
  async notifyUsers(
    ctx: AppContext,
    userIds: number[],
    notification: {
      typeCode: string;
      title: string;
      message: string;
      data?: Record<string, unknown>;
    },
  ) {
    if (userIds.length === 0) return { created: 0, pushed: 0 };
    const notificationTypeId = await this.repository.findNotificationTypeId(
      notification.typeCode,
    );
    let created = 0;
    let pushed = 0;
    for (const userId of userIds) {
      const row = await this.repository.insertNotification({
        institution_id: ctx.institutionId,
        user_id: userId,
        notification_type_id: notificationTypeId,
        title: notification.title,
        message: notification.message,
        data: notification.data ?? {},
        read: false,
      });
      created += 1;
      if (await this.sendPush(Number(row.id))) pushed += 1;
    }
    return { created, pushed };
  }

  /** Marca como leídas las notificaciones de una conversación de chat. */
  async markConversationRead(ctx: AppContext, conversationId: number, readAt = new Date().toISOString()) {
    const { error } = await this.repository.markConversationRead(
      ctx.userId,
      ctx.institutionId,
      conversationId,
      readAt,
    );
    assertNoDbError(error);
  }

  async notifyAudience(
    ctx: AppContext,
    audience: string,
    title: string,
    message: string,
    data: Record<string, unknown> = {},
  ) {
    const roleCodes = this.roleCodesForAudience(audience);
    if (roleCodes.length === 0) {
      return { created: 0, pushed: 0, emailed: 0, emailFailed: 0 };
    }
    const users = await this.repository.listUsersByRoleCodes(
      ctx.institutionId,
      roleCodes,
    );
    const notificationTypeId = await this.repository.findNotificationTypeId(
      "ANN",
    );
    const emailChannelId = await this.repository.findChannelId("EMAIL");
    let pushed = 0;
    let emailed = 0;
    let emailFailed = 0;
    for (const user of users) {
      const notification = await this.repository.insertNotification({
        institution_id: ctx.institutionId,
        user_id: user.id,
        notification_type_id: notificationTypeId,
        title,
        message,
        data,
        read: false,
      });
      if (await this.sendPush(Number(notification.id))) pushed += 1;
      const delivery = await this.sendEmailNotification(
        Number(notification.id),
        emailChannelId,
        user,
        title,
        message,
      );
      if (delivery === "sent") emailed += 1;
      if (delivery === "failed") emailFailed += 1;
    }
    return { created: users.length, pushed, emailed, emailFailed };
  }

  private roleCodesForAudience(audience: string) {
    switch (audience) {
      case "all":
        return ["student", "parent", "teacher", "admin", "coordinator", "director"];
      case "students":
      case "student":
        return ["student"];
      case "parents":
      case "parent":
        return ["parent"];
      case "teachers":
      case "teacher":
        return ["teacher"];
      case "admins":
      case "staff":
        return ["admin", "coordinator", "director"];
      default:
        return [];
    }
  }

  private async sendEmailNotification(
    notificationId: number,
    channelId: number | null,
    user: Record<string, unknown>,
    title: string,
    message: string,
  ) {
    if (user.email_notifications_enabled === false) return "skipped";
    const destination = typeof user.email === "string" ? user.email.trim() : "";
    if (!destination) return "skipped";
    try {
      const response = await emailService.sendAnnouncement(
        destination,
        String(user.full_name ?? "usuario"),
        title,
        message,
      );
      await this.recordDelivery({
        notification_id: notificationId,
        channel_id: channelId,
        destination,
        status: "sent",
        provider: "resend",
        external_ref: String(response.id ?? ""),
        sent_at: new Date().toISOString(),
      });
      return "sent";
    } catch (error) {
      await this.recordDelivery({
        notification_id: notificationId,
        channel_id: channelId,
        destination,
        status: "failed",
        provider: "resend",
        error: error instanceof Error ? error.message : String(error),
      });
      console.error({
        level: "warn",
        event: "announcement_email_failed",
        notificationId,
        destination,
        error,
      });
      return "failed";
    }
  }

  private async recordDelivery(payload: Record<string, unknown>) {
    try {
      await this.repository.insertDelivery(payload);
    } catch (error) {
      console.error({
        level: "warn",
        event: "notification_delivery_log_failed",
        payload,
        error,
      });
    }
  }

  private webPushReady = false;

  private webPushConfigured() {
    return Boolean(env.vapidPublicKey && env.vapidPrivateKey);
  }

  /**
   * Web Push estándar (VAPID) directo desde el backend: llega al navegador
   * aunque la app esté cerrada. Desactiva las suscripciones que el servicio de
   * push reporta como vencidas (404/410) y registra cada entrega.
   */
  private async sendWebPush(notificationId: number) {
    if (!this.webPushReady) {
      webpush.setVapidDetails(
        env.vapidSubject,
        env.vapidPublicKey,
        env.vapidPrivateKey,
      );
      this.webPushReady = true;
    }
    const notification = await this.repository.findNotification(notificationId);
    if (notification == null) return false;
    const devices = await this.repository.listActiveWebDevices(
      Number(notification.user_id),
    );
    if (devices.length === 0) return false;

    const data = (notification.data ?? {}) as Record<string, unknown>;
    const payload = JSON.stringify({
      title: notification.title ?? "Nivra",
      body: notification.message ?? "",
      deepLink: data.deepLink ?? "/",
      // Un mismo chat reemplaza su aviso anterior en lugar de apilarse.
      tag: data.conversationId != null
        ? `chat-${data.conversationId}`
        : `notification-${notificationId}`,
    });
    const channelId = await this.repository.findChannelId("PUSH");

    let delivered = 0;
    for (const device of devices) {
      let status = "sent";
      let failure: string | null = null;
      try {
        await webpush.sendNotification(JSON.parse(device.push_token), payload, {
          TTL: 60 * 60,
          urgency: "high",
          timeout: 10000,
        });
        delivered += 1;
      } catch (error) {
        status = "failed";
        const code = (error as { statusCode?: number }).statusCode;
        failure = String((error as Error).message ?? error).slice(0, 300);
        if (code === 404 || code === 410) {
          await this.repository.deactivateDevice(device.id);
        }
      }
      await this.recordDelivery({
        notification_id: notificationId,
        channel_id: channelId,
        destination: String(device.id),
        status,
        provider: "webpush",
        error: failure,
        sent_at: new Date().toISOString(),
      });
    }
    return delivered > 0;
  }

  async sendStoredPush(notificationId: number) {
    return this.sendPush(notificationId);
  }

  private async sendPush(notificationId: number) {
    if (this.webPushConfigured()) {
      try {
        return await this.sendWebPush(notificationId);
      } catch (error) {
        console.error({
          level: "warn",
          event: "send_web_push_failed",
          notificationId,
          error,
        });
        return false;
      }
    }
    if (!env.internalApiSecret) return false;
    const url = env.sendPushUrl ||
      `${env.supabaseUrl.replace(/\/$/, "")}/functions/v1/send-push`;
    try {
      const response = await fetch(url, {
        signal: AbortSignal.timeout(10000),
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${env.internalApiSecret}`,
        },
        body: JSON.stringify({ notificationId }),
      });
      return response.ok;
    } catch (error) {
      console.error({
        level: "warn",
        event: "send_push_failed",
        notificationId,
        error,
      });
      return false;
    }
  }
}

export const notificationsService = new NotificationsService();

