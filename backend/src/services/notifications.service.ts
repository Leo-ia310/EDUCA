import { assertNoDbError } from "../lib/db";
import { env } from "../lib/env";
import { requiredString } from "../validators/common.validators";
import {
  notificationsRepository,
  NotificationsRepository,
} from "../repositories/notifications.repository";
import type { AppContext } from "../types/app-context";

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

  async notifyAudience(
    ctx: AppContext,
    audience: string,
    title: string,
    message: string,
    data: Record<string, unknown> = {},
  ) {
    const roleCodes = this.roleCodesForAudience(audience);
    if (roleCodes.length === 0) return { created: 0, pushed: 0 };
    const users = await this.repository.listUsersByRoleCodes(
      ctx.institutionId,
      roleCodes,
    );
    let pushed = 0;
    for (const user of users) {
      const notification = await this.repository.insertNotification({
        institution_id: ctx.institutionId,
        user_id: user.id,
        title,
        message,
        data,
        read: false,
      });
      if (await this.sendPush(Number(notification.id))) pushed += 1;
    }
    return { created: users.length, pushed };
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
