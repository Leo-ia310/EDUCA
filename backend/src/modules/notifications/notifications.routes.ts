import { Router } from "express";

import {
  clearNotifications,
  deleteNotification,
  listNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  saveWebPushDevice,
} from "./notifications.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";

export const notificationsRoutes = Router();

notificationsRoutes.use(authMiddleware);
notificationsRoutes.post("/web-push-device", asyncHandler(saveWebPushDevice));

notificationsRoutes.get("/", asyncHandler(listNotifications));
notificationsRoutes.post("/read-all", asyncHandler(markAllNotificationsRead));
notificationsRoutes.patch("/:id/read", asyncHandler(markNotificationRead));
notificationsRoutes.delete("/", asyncHandler(clearNotifications));
notificationsRoutes.delete("/:id", asyncHandler(deleteNotification));
