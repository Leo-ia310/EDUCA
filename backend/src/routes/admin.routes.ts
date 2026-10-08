import { Router } from "express";

import {
  archiveInstitution,
  archivePeople,
  archiveRole,
  archiveUser,
  createInstitution,
  createPeople,
  createRole,
  createUser,
  listInstitutions,
  listPeople,
  listRoles,
  listUsers,
  updateInstitution,
  updatePeople,
  updateRole,
  updateUser,
} from "../controllers/admin.controller";
import { authMiddleware } from "../middleware/auth.middleware";
import { asyncHandler } from "../middleware/error.middleware";
import { requirePlatformAdmin } from "../middleware/permissions.middleware";

export const adminRoutes = Router();

adminRoutes.use(authMiddleware, requirePlatformAdmin);

adminRoutes.get("/institutions", asyncHandler(listInstitutions));
adminRoutes.post("/institutions", asyncHandler(createInstitution));
adminRoutes.patch("/institutions/:id", asyncHandler(updateInstitution));
adminRoutes.delete("/institutions/:id", asyncHandler(archiveInstitution));

adminRoutes.get("/users", asyncHandler(listUsers));
adminRoutes.post("/users", asyncHandler(createUser));
adminRoutes.patch("/users/:id", asyncHandler(updateUser));
adminRoutes.delete("/users/:id", asyncHandler(archiveUser));

adminRoutes.get("/roles", asyncHandler(listRoles));
adminRoutes.post("/roles", asyncHandler(createRole));
adminRoutes.patch("/roles/:id", asyncHandler(updateRole));
adminRoutes.delete("/roles/:id", asyncHandler(archiveRole));

for (const resource of ["students", "teachers", "parents"] as const) {
  adminRoutes.get(`/${resource}`, asyncHandler(listPeople(resource)));
  adminRoutes.post(`/${resource}`, asyncHandler(createPeople(resource)));
  adminRoutes.patch(`/${resource}/:id`, asyncHandler(updatePeople(resource)));
  adminRoutes.delete(`/${resource}/:id`, asyncHandler(archivePeople(resource)));
}
