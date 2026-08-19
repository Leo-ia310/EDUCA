import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { notificationsService } from "../services/notifications.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function saveWebPushDevice(req: AppRequest, res: Response) {
  const data = await notificationsService.saveWebPushDevice(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}
