import { Router } from "express";

import {
  getClassRoster,
  getGroupDetail,
  getSummary,
  saveClassAttendance,
  upsertAttendance,
  upsertClassSession,
} from "./attendance.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import { requireRoles } from "../../middleware/permissions.middleware";

export const attendanceRoutes = Router();

attendanceRoutes.use(authMiddleware);
attendanceRoutes.post(
  "/class-sessions/upsert",
  requireRoles(["teacher"]),
  asyncHandler(upsertClassSession),
);
attendanceRoutes.post("/upsert", requireRoles(["teacher"]), asyncHandler(upsertAttendance));
attendanceRoutes.get("/class/:classId", requireRoles(["teacher"]), asyncHandler(getClassRoster));
attendanceRoutes.post("/class/:classId", requireRoles(["teacher"]), asyncHandler(saveClassAttendance));
attendanceRoutes.get("/summary", asyncHandler(getSummary));
attendanceRoutes.get("/groups/:groupId", asyncHandler(getGroupDetail));

