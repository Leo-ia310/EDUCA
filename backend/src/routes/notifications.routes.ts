import { Router } from "express";

import { saveWebPushDevice } from "../controllers/notifications.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";

export const notificationsRoutes = Router();

notificationsRoutes.use(authMiddleware);
notificationsRoutes.post("/web-push-device", asyncHandler(saveWebPushDevice));
