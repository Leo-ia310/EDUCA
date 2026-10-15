import { Router } from "express";

import {
  getDefaultScale,
  setDefaultScale,
  setGrade,
  upsertScale,
} from "./grades.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import { requireAdmin, requireRoles } from "../../middleware/permissions.middleware";

export const gradesRoutes = Router();

gradesRoutes.use(authMiddleware);
gradesRoutes.get("/scales/default", asyncHandler(getDefaultScale));
gradesRoutes.post("/scales/upsert", requireAdmin, asyncHandler(upsertScale));
gradesRoutes.post("/scales/default", requireAdmin, asyncHandler(setDefaultScale));
gradesRoutes.patch("/scales/:id/default", requireAdmin, asyncHandler(setDefaultScale));
gradesRoutes.post("/set-grade", requireRoles(["teacher"]), asyncHandler(setGrade));

