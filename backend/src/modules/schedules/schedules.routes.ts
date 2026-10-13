import { Router } from "express";

import {
  createSchedule,
  deleteSchedule,
  listSchedules,
  mySchedules,
  updateSchedule,
} from "./schedules.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import {
  requireAdmin,
  requireAdminPermission as can,
} from "../../middleware/permissions.middleware";

export const schedulesRoutes = Router();

schedulesRoutes.use(authMiddleware);

// Alumno, padre (de sus hijos) y maestro: solo lo que les corresponde.
schedulesRoutes.get("/mine", asyncHandler(mySchedules));

// Administración de horarios (por persona: schedules.*).
schedulesRoutes.get("/", requireAdmin, can("schedules.view"), asyncHandler(listSchedules));
schedulesRoutes.post("/", requireAdmin, can("schedules.create"), asyncHandler(createSchedule));
schedulesRoutes.patch("/:id", requireAdmin, can("schedules.edit"), asyncHandler(updateSchedule));
schedulesRoutes.delete("/:id", requireAdmin, can("schedules.delete"), asyncHandler(deleteSchedule));
