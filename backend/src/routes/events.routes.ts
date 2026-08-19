import { Router } from "express";

import { createEvent } from "../controllers/events.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";
import { requireRoles } from "../middleware/permissions.middleware";

export const eventsRoutes = Router();

eventsRoutes.use(authMiddleware);
eventsRoutes.post("/", requireRoles(["teacher"]), asyncHandler(createEvent));
