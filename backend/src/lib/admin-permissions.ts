import { HttpError } from "./errors";

/**
 * Catálogo de permisos del panel administrativo. Cada perfil con rol admin,
 * coordinator o director puede tener su propia lista (users.admin_permissions).
 * Código = "<modulo>.<accion>".
 */
export const ADMIN_PERMISSION_MODULES = [
  { key: "dashboard", label: "Dashboard", actions: ["view"] },
  { key: "students", label: "Alumnos", actions: ["view", "create", "edit", "delete"] },
  { key: "teachers", label: "Maestros", actions: ["view", "create", "edit", "delete"] },
  { key: "classes", label: "Clases", actions: ["view", "create", "edit", "delete"] },
  { key: "payments", label: "Pagos", actions: ["view", "create", "edit", "cancel"] },
  { key: "reports", label: "Reportes", actions: ["view", "generate", "download"] },
  { key: "roles", label: "Roles y permisos", actions: ["view", "create", "edit", "delete"] },
  { key: "settings", label: "Configuración", actions: ["view", "edit"] },
] as const;

export const ADMIN_PERMISSION_CODES: readonly string[] =
  ADMIN_PERMISSION_MODULES.flatMap((m) =>
    m.actions.map((action) => `${m.key}.${action}`)
  );

/** Roles que pueden entrar al dashboard admin. */
export const ADMIN_PROFILE_ROLES = ["admin", "coordinator", "director"] as const;
export type AdminProfileRole = (typeof ADMIN_PROFILE_ROLES)[number];

export function isAdminProfileRole(code: unknown): code is AdminProfileRole {
  return ADMIN_PROFILE_ROLES.includes(code as AdminProfileRole);
}

/** Valida y normaliza una lista de permisos recibida del cliente. */
export function normalizeAdminPermissions(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new HttpError(400, "Los permisos deben ser una lista.", "validation_error");
  }
  const codes = [...new Set(value.map((code) => String(code).trim()))];
  const unknown = codes.filter((code) => !ADMIN_PERMISSION_CODES.includes(code));
  if (unknown.length > 0) {
    throw new HttpError(
      400,
      `Permisos no válidos: ${unknown.join(", ")}`,
      "validation_error",
    );
  }
  // Editar/crear/eliminar sin poder ver no tiene sentido: se añade "view".
  const withView = new Set(codes);
  for (const code of codes) {
    const [module] = code.split(".");
    if (module !== "dashboard" && code !== `${module}.view`) {
      withView.add(`${module}.view`);
    }
  }
  return [...withView].sort();
}
