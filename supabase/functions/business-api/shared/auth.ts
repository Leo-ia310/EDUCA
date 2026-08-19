import { expectSingle } from "./db.ts";
import { HttpError } from "./http.ts";
import { db } from "./supabase.ts";
import { asList, optionalId } from "./validators.ts";

export type AppContext = {
  authUserId: string;
  userId: number;
  institutionId: number;
  personId: number | null;
  fullName: string;
  roles: Set<string>;
  teacherId?: number | null;
  studentId?: number | null;
  parentId?: number | null;
};

export function isAdmin(ctx: AppContext) {
  return ["admin", "super_admin", "coordinator", "director"].some((role) =>
    ctx.roles.has(role)
  );
}

export function hasAnyRole(ctx: AppContext, roles: string[]) {
  return roles.some((role) => ctx.roles.has(role)) || isAdmin(ctx);
}

export function requireRole(ctx: AppContext, roles: string[]) {
  if (!hasAnyRole(ctx, roles)) {
    throw new HttpError(
      403,
      "No tienes permiso para realizar esta acción.",
      "forbidden",
    );
  }
}

export async function loadContext(req: Request): Promise<AppContext> {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    throw new HttpError(401, "Sesión requerida.", "unauthorized");
  }

  const { data: authData, error: authError } = await db.auth.getUser(token);
  if (authError || !authData.user) {
    throw new HttpError(401, "Sesión inválida o expirada.", "unauthorized");
  }

  const appUser = await expectSingle<Record<string, unknown>>(
    db
      .from("users")
      .select(
        "id, institution_id, person_id, full_name, user_roles(roles(code))",
      )
      .eq("auth_user_id", authData.user.id)
      .eq("active", true)
      .is("deleted_at", null)
      .single(),
    "Usuario de aplicación no encontrado.",
  );

  const roles = new Set(
    asList(appUser.user_roles).map((entry) =>
      ((entry as Record<string, unknown>).roles as
        | Record<string, unknown>
        | null)?.code
    ).filter((code): code is string => typeof code === "string"),
  );
  if (roles.size === 0) {
    throw new HttpError(403, "Usuario sin roles asignados.", "forbidden");
  }

  return {
    authUserId: authData.user.id,
    userId: Number(appUser.id),
    institutionId: Number(appUser.institution_id),
    personId: appUser.person_id == null ? null : Number(appUser.person_id),
    fullName: String(appUser.full_name ?? "Usuario"),
    roles,
  };
}

export async function currentTeacherId(ctx: AppContext) {
  if (ctx.teacherId !== undefined) return ctx.teacherId;
  if (ctx.personId == null) return ctx.teacherId = null;
  const { data } = await db
    .from("teachers")
    .select("id")
    .eq("person_id", ctx.personId)
    .eq("institution_id", ctx.institutionId)
    .eq("active", true)
    .maybeSingle();
  return ctx.teacherId = data == null ? null : Number(data.id);
}

export async function currentStudentId(ctx: AppContext) {
  if (ctx.studentId !== undefined) return ctx.studentId;
  if (ctx.personId == null) return ctx.studentId = null;
  const { data } = await db
    .from("students")
    .select("id")
    .eq("person_id", ctx.personId)
    .eq("institution_id", ctx.institutionId)
    .eq("active", true)
    .maybeSingle();
  return ctx.studentId = data == null ? null : Number(data.id);
}

export async function currentParentId(ctx: AppContext) {
  if (ctx.parentId !== undefined) return ctx.parentId;
  if (ctx.personId == null) return ctx.parentId = null;
  const { data } = await db
    .from("parents")
    .select("id")
    .eq("person_id", ctx.personId)
    .eq("institution_id", ctx.institutionId)
    .maybeSingle();
  return ctx.parentId = data == null ? null : Number(data.id);
}

export async function assertTeacherCanUseClass(
  ctx: AppContext,
  classId: number,
) {
  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("classes")
      .select("id, group_id, teacher_id, institution_id")
      .eq("id", classId)
      .eq("institution_id", ctx.institutionId)
      .eq("active", true)
      .single(),
    "Clase no encontrada.",
  );

  if (isAdmin(ctx)) return row;

  requireRole(ctx, ["teacher"]);
  const teacherId = await currentTeacherId(ctx);
  if (teacherId == null || Number(row.teacher_id) !== teacherId) {
    throw new HttpError(
      403,
      "No puedes modificar una clase que no impartes.",
      "forbidden",
    );
  }
  return row;
}

export async function assertTeacherCanUseAssignment(
  ctx: AppContext,
  assignmentId: number,
) {
  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("assignments")
      .select("id, class_id, institution_id, classes(teacher_id, group_id)")
      .eq("id", assignmentId)
      .eq("institution_id", ctx.institutionId)
      .is("deleted_at", null)
      .single(),
    "Tarea no encontrada.",
  );
  const cls = row.classes as Record<string, unknown> | null;
  if (isAdmin(ctx)) return row;

  requireRole(ctx, ["teacher"]);
  const teacherId = await currentTeacherId(ctx);
  if (teacherId == null || Number(cls?.teacher_id) !== teacherId) {
    throw new HttpError(
      403,
      "No puedes modificar una tarea de otra clase.",
      "forbidden",
    );
  }
  return row;
}

export async function assertStudentEnrolledInClass(
  institutionId: number,
  studentId: number,
  classId: number,
  groupId?: number | null,
) {
  let gid = groupId ?? null;
  if (gid == null) {
    const cls = await expectSingle<Record<string, unknown>>(
      db.from("classes").select("group_id").eq("id", classId).single(),
      "Clase no encontrada.",
    );
    gid = Number(cls.group_id);
  }
  if (!Number.isFinite(gid)) {
    throw new HttpError(
      400,
      "La clase no tiene grupo académico asociado.",
      "validation_error",
    );
  }
  const { data } = await db
    .from("enrollments")
    .select("id")
    .eq("student_id", studentId)
    .eq("group_id", gid)
    .eq("institution_id", institutionId)
    .limit(1);
  if (!data || data.length === 0) {
    throw new HttpError(
      403,
      "El estudiante no pertenece a esta clase.",
      "forbidden",
    );
  }
}

export async function normalizeStudentId(
  ctx: AppContext,
  requested: unknown,
  label = "estudiante",
) {
  const requestedId = optionalId(requested);
  if (ctx.roles.has("student") && !isAdmin(ctx)) {
    const mine = await currentStudentId(ctx);
    if (mine == null) {
      throw new HttpError(
        403,
        "Tu usuario no está enlazado a un estudiante.",
        "forbidden",
      );
    }
    if (requestedId != null && requestedId !== mine) {
      throw new HttpError(
        403,
        `No puedes operar sobre otro ${label}.`,
        "forbidden",
      );
    }
    return mine;
  }
  if (ctx.roles.has("parent") && !isAdmin(ctx)) {
    const parentId = await currentParentId(ctx);
    if (parentId == null || requestedId == null) {
      throw new HttpError(
        403,
        "No se pudo validar el estudiante del acudiente.",
        "forbidden",
      );
    }
    const { data } = await db
      .from("parent_students")
      .select("id")
      .eq("parent_id", parentId)
      .eq("student_id", requestedId)
      .limit(1);
    if (!data || data.length === 0) {
      throw new HttpError(
        403,
        "No tienes acceso a este estudiante.",
        "forbidden",
      );
    }
    return requestedId;
  }
  if (requestedId == null) {
    throw new HttpError(400, `Falta ${label}.`, "validation_error");
  }
  return requestedId;
}
