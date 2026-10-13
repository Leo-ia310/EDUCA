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
    const existing = await this.repository.findDevice(ctx.userId, endpoint);
    if (existing == null) {
      await this.repository.insertDevice({
        user_id: ctx.userId,
        device_uuid: endpoint,
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
    if (payload.emailEnabled != null) {
      if (typeof payload.emailEnabled !== "boolean") {
        throw new HttpError(
          400,
          "Preferencia de correo inválida.",
          "validation_error",
        );
      }
      update.email_notifications_enabled = payload.emailEnabled;
    }
    if (Object.keys(update).length === 0) return this.getPreferences(ctx);
    const row = await this.repository.updatePreferences(
      ctx.userId,
      ctx.institutionId,
      update,
    );
    return {
      emailEnabled: row.email_notifications_enabled !== false,
    };
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

  private async sendPush(notificationId: number) {
    if (!env.internalApiSecret) return false;
    const url = env.sendPushUrl ||
      `${env.supabaseUrl.replace(/\/$/, "")}/functions/v1/send-push`;
    try {
      const response = await fetch(url, {
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

