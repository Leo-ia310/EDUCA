// Verifica la lógica pura de permisos administrativos (sin red ni base de datos).
// Uso: cd backend && npx tsx scripts/admin_permissions_check.ts
import assert from "node:assert/strict";

import {
  ADMIN_PERMISSION_CODES,
  normalizeAdminPermissions,
} from "../src/lib/admin-permissions";
import { PermissionsService } from "../src/services/permissions.service";
import type { AppContext } from "../src/types/app-context";

const service = new PermissionsService({} as never);
const ctx = (roles: string[], adminPermissions: string[] | null): AppContext => ({
  authUserId: "a",
  userId: 1,
  institutionId: 1,
  personId: null,
  fullName: "Test",
  roles: new Set(roles),
  adminPermissions,
});

// Sin lista explícita se conserva el acceso histórico del rol.
assert.equal(service.hasAdminPermission(ctx(["admin"], null), "roles.edit"), true);
assert.equal(service.hasAdminPermission(ctx(["coordinator"], null), "students.view"), true);

// Con lista explícita solo lo concedido, incluso siendo admin.
const juan = ctx(["coordinator"], ["students.view", "students.edit", "payments.view"]);
assert.equal(service.hasAdminPermission(juan, "students.edit"), true);
assert.equal(service.hasAdminPermission(juan, "teachers.view"), false);
assert.equal(service.hasAdminPermission(juan, "roles.view"), false);
assert.equal(service.hasAdminPermission(juan, "settings.view"), false);
assert.throws(() => service.requireAdminPermission(juan, "roles.view"));
assert.doesNotThrow(() =>
  service.requireAdminPermission(juan, ["teachers.view", "payments.view"])
);

const maria = ctx(["admin"], [...ADMIN_PERMISSION_CODES]);
assert.equal(service.hasAdminPermission(maria, "settings.edit"), true);

// Un perfil con lista vacía no puede nada; no-admin tampoco aunque tenga lista.
assert.equal(service.hasAdminPermission(ctx(["director"], []), "dashboard.view"), false);
assert.equal(service.hasAdminPermission(ctx(["teacher"], null), "students.view"), false);
assert.equal(service.hasAdminPermission(ctx(["super_admin"], []), "roles.edit"), true);

// Normalización: valida códigos y añade "view" cuando falta.
assert.deepEqual(normalizeAdminPermissions(["students.edit", "payments.view"]), [
  "payments.view",
  "students.edit",
  "students.view",
]);
assert.deepEqual(normalizeAdminPermissions(["dashboard.view", "dashboard.view"]), [
  "dashboard.view",
]);
assert.throws(() => normalizeAdminPermissions(["foo.bar"]));
assert.throws(() => normalizeAdminPermissions("students.view"));

console.log("admin permissions: OK");
