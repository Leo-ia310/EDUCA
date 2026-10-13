import type { Response } from "express";

import { requireAppContext } from "../../middleware/auth.middleware";
import { notificationsService } from "../notifications/notifications.service";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";

export async function saveWebPushDevice(req: AppRequest, res: Response) {
  const data = await notificationsService.saveWebPushDevice(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}


function notificationId(req: AppRequest) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id <= 0) {
    throw new Error("Id de notificación inválido.");
  }
  return id;
}

export async function listNotifications(req: AppRequest, res: Response) {
  const data = await notificationsService.listMine(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function markNotificationRead(req: AppRequest, res: Response) {
  const data = await notificationsService.markRead(
    requireAppContext(req),
    notificationId(req),
  );
  return res.json({ ok: true, data });
}

export async function markAllNotificationsRead(req: AppRequest, res: Response) {
  const data = await notificationsService.markRead(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function deleteNotification(req: AppRequest, res: Response) {
  const data = await notificationsService.remove(
    requireAppContext(req),
    notificationId(req),
  );
  return res.json({ ok: true, data });
}

export async function clearNotifications(req: AppRequest, res: Response) {
  const data = await notificationsService.remove(requireAppContext(req));
  return res.json({ ok: true, data });
}
