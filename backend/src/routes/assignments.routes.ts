import { Router } from "express";

import {
  deleteAssignment,
  gradeSubmission,
  publishAssignment,
  submitAssignment,
  teacherClasses,
  upsertAssignment,
} from "../controllers/assignments.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";
import { requireRoles } from "../middleware/permissions.middleware";

export const assignmentsRoutes = Router();

assignmentsRoutes.use(authMiddleware);
assignmentsRoutes.post(
  "/teacher-classes",
  requireRoles(["teacher"]),
  asyncHandler(teacherClasses),
);
assignmentsRoutes.post("/upsert", requireRoles(["teacher"]), asyncHandler(upsertAssignment));
assignmentsRoutes.post("/delete", requireRoles(["teacher"]), asyncHandler(deleteAssignment));
assignmentsRoutes.delete("/:id", requireRoles(["teacher"]), asyncHandler(deleteAssignment));
assignmentsRoutes.post("/publish", requireRoles(["teacher"]), asyncHandler(publishAssignment));
assignmentsRoutes.patch("/:id/publish", requireRoles(["teacher"]), asyncHandler(publishAssignment));
assignmentsRoutes.post("/submit", requireRoles(["student"]), asyncHandler(submitAssignment));
assignmentsRoutes.post(
  "/grade-submission",
  requireRoles(["teacher"]),
  asyncHandler(gradeSubmission),
);
assignmentsRoutes.patch(
  "/submissions/:submissionId/grade",
  requireRoles(["teacher"]),
  asyncHandler(gradeSubmission),
);
