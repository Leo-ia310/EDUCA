import { Router } from "express";

import {
  archive,
  auditEvents,
  create,
  institutions,
  list,
  summary,
  update,
  users,
} from "../controllers/developer.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";
import { requireAdmin } from "../middleware/permissions.middleware";

export const developerRoutes = Router();

developerRoutes.use(authMiddleware, requireAdmin);

developerRoutes.get("/summary", asyncHandler(summary));
developerRoutes.get("/institutions", asyncHandler(institutions));
developerRoutes.get("/users", asyncHandler(users));
developerRoutes.get("/audit-events", asyncHandler(auditEvents));

developerRoutes.get("/modules", asyncHandler(list("modules")));
developerRoutes.post("/modules", asyncHandler(create("modules")));
developerRoutes.patch("/modules/:id", asyncHandler(update("modules")));
developerRoutes.delete("/modules/:id", asyncHandler(archive("modules")));

developerRoutes.get("/apis", asyncHandler(list("apis")));
developerRoutes.post("/apis", asyncHandler(create("apis")));
developerRoutes.patch("/apis/:id", asyncHandler(update("apis")));
developerRoutes.delete("/apis/:id", asyncHandler(archive("apis")));

developerRoutes.get("/tasks", asyncHandler(list("tasks")));
developerRoutes.post("/tasks", asyncHandler(create("tasks")));
developerRoutes.patch("/tasks/:id", asyncHandler(update("tasks")));
developerRoutes.delete("/tasks/:id", asyncHandler(archive("tasks")));

developerRoutes.get("/feature-flags", asyncHandler(list("featureFlags")));
developerRoutes.post("/feature-flags", asyncHandler(create("featureFlags")));
developerRoutes.patch("/feature-flags/:id", asyncHandler(update("featureFlags")));
developerRoutes.delete("/feature-flags/:id", asyncHandler(archive("featureFlags")));

developerRoutes.get("/system-checks", asyncHandler(list("systemChecks")));
developerRoutes.post("/system-checks", asyncHandler(create("systemChecks")));
developerRoutes.patch("/system-checks/:id", asyncHandler(update("systemChecks")));
developerRoutes.delete("/system-checks/:id", asyncHandler(archive("systemChecks")));
