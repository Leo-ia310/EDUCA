import { Router } from "express";
import { originalityReport, originalityRetry } from './originality/originality.controller';

import {
  assignmentSubmissions,
  deleteAssignment,
  gradeSubmission,
  listAssignments,
  studentAssignments,
  removeAssignmentAttachment,
  publishAssignment,
  submitAssignment,
  teacherClasses,
  upsertAssignment,
} from "./assignments.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import { requireRoles } from "../../middleware/permissions.middleware";

export const assignmentsRoutes = Router();

assignmentsRoutes.use(authMiddleware);
assignmentsRoutes.get('/submissions/:submissionId/originality', requireRoles(['teacher']), asyncHandler(originalityReport));
assignmentsRoutes.post('/submissions/:submissionId/originality/retry', requireRoles(['teacher']), asyncHandler(originalityRetry));
assignmentsRoutes.post(
  "/teacher-classes",
  requireRoles(["teacher"]),
  asyncHandler(teacherClasses),
);
assignmentsRoutes.get("/teacher", requireRoles(["teacher"]), asyncHandler(listAssignments));
assignmentsRoutes.get("/student", requireRoles(["parent", "student"]), asyncHandler(studentAssignments));
assignmentsRoutes.get("/:id/submissions", requireRoles(["teacher"]), asyncHandler(assignmentSubmissions));
assignmentsRoutes.post("/upsert", requireRoles(["teacher"]), asyncHandler(upsertAssignment));
assignmentsRoutes.post("/delete", requireRoles(["teacher"]), asyncHandler(deleteAssignment));
assignmentsRoutes.delete("/:id/attachments/:fileId", requireRoles(["teacher"]), asyncHandler(removeAssignmentAttachment));
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

