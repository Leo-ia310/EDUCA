import { assertNoDbError } from "../lib/db";
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
}

export const notificationsService = new NotificationsService();
