import { Router } from "express";

import {
  archiveInstitution,
  createProfile,
  listPermissionCatalog,
  listProfiles,
  updateProfile,
  archiveClass,
  archiveGroup,
  archivePeople,
  archiveRole,
  archiveUser,
  createClass,
  createGroup,
  createInstitution,
  createPeople,
  createRole,
  createUser,
  directory,
  listInstitutions,
  listPeople,
  listRoles,
  listUsers,
  updateClass,
  updateGroup,
  updateInstitution,
  updatePeople,
  updateRole,
  updateUser,
} from "./admin.controller";
import { authMiddleware } from "../../middleware/auth.middleware";
import { asyncHandler } from "../../middleware/error.middleware";
import {
  requireAdmin,
  requireAdminPermission as can,
} from "../../middleware/permissions.middleware";

export const adminRoutes = Router();

adminRoutes.use(authMiddleware, requireAdmin);

adminRoutes.get("/institutions", can("settings.view"), asyncHandler(listInstitutions));
adminRoutes.post("/institutions", can("settings.edit"), asyncHandler(createInstitution));
adminRoutes.patch("/institutions/:id", can("settings.edit"), asyncHandler(updateInstitution));
adminRoutes.delete("/institutions/:id", can("settings.edit"), asyncHandler(archiveInstitution));

adminRoutes.get("/users", can("roles.view"), asyncHandler(listUsers));
adminRoutes.post("/users", can("roles.create"), asyncHandler(createUser));
adminRoutes.patch("/users/:id", can("roles.edit"), asyncHandler(updateUser));
adminRoutes.delete("/users/:id", can("roles.delete"), asyncHandler(archiveUser));

adminRoutes.get("/directory", can("dashboard.view", "students.view", "teachers.view", "classes.view", "roles.view", "reports.view", "payments.view"), asyncHandler(directory));

adminRoutes.post("/groups", can("classes.create"), asyncHandler(createGroup));
adminRoutes.patch("/groups/:id", can("classes.edit"), asyncHandler(updateGroup));
adminRoutes.delete("/groups/:id", can("classes.delete"), asyncHandler(archiveGroup));

adminRoutes.post("/classes", can("classes.create"), asyncHandler(createClass));
adminRoutes.patch("/classes/:id", can("classes.edit"), asyncHandler(updateClass));
adminRoutes.delete("/classes/:id", can("classes.delete"), asyncHandler(archiveClass));

adminRoutes.get("/roles", can("roles.view"), asyncHandler(listRoles));
adminRoutes.post("/roles", can("roles.create"), asyncHandler(createRole));
adminRoutes.patch("/roles/:id", can("roles.edit"), asyncHandler(updateRole));
adminRoutes.delete("/roles/:id", can("roles.delete"), asyncHandler(archiveRole));

for (const resource of ["students", "teachers", "parents"] as const) {
  // Padres y tutores se gestionan junto con los alumnos.
  const module = resource === "teachers" ? "teachers" : "students";
  adminRoutes.get(`/${resource}`, can(`${module}.view`), asyncHandler(listPeople(resource)));
  adminRoutes.post(`/${resource}`, can(`${module}.create`), asyncHandler(createPeople(resource)));
  adminRoutes.patch(`/${resource}/:id`, can(`${module}.edit`), asyncHandler(updatePeople(resource)));
  adminRoutes.delete(`/${resource}/:id`, can(`${module}.delete`), asyncHandler(archivePeople(resource)));
}

// Perfiles administrativos (rol + permisos por persona).
adminRoutes.get("/permissions/catalog", asyncHandler(listPermissionCatalog));
adminRoutes.get("/profiles", can("roles.view"), asyncHandler(listProfiles));
adminRoutes.post("/profiles", can("roles.create"), asyncHandler(createProfile));
adminRoutes.patch("/profiles/:id", can("roles.edit"), asyncHandler(updateProfile));
