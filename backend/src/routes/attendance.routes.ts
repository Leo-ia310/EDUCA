import { Router } from "express";

import {
  upsertAttendance,
  upsertClassSession,
} from "../controllers/attendance.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";
import { requireRoles } from "../middleware/permissions.middleware";

export const attendanceRoutes = Router();

attendanceRoutes.use(authMiddleware);
attendanceRoutes.post(
  "/class-sessions/upsert",
  requireRoles(["teacher"]),
  asyncHandler(upsertClassSession),
);
attendanceRoutes.post("/upsert", requireRoles(["teacher"]), asyncHandler(upsertAttendance));
