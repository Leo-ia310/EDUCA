import type { AppContext } from "../types/app-context";
import { authRepository, AuthRepository } from "../modules/auth/auth.repository";
import { HttpError } from "../lib/errors";
import { optionalId } from "../validators/common.validators";

export class PermissionsService {
  constructor(private readonly repository: AuthRepository = authRepository) {}

  isAdmin(ctx: AppContext) {
    return ["admin", "super_admin", "coordinator", "director"].some((role) =>
      ctx.roles.has(role)
    );
  }

  /**
   * Permiso administrativo por persona. super_admin siempre puede; un perfil
   * admin/coordinator/director con lista explícita solo puede lo que figura
   * en ella; sin lista (null) conserva el acceso histórico de su rol.
   */
  hasAdminPermission(ctx: AppContext, code: string) {
    if (ctx.roles.has("super_admin")) return true;
    if (!this.isAdmin(ctx)) return false;
    return ctx.adminPermissions == null || ctx.adminPermissions.includes(code);
  }

  /**
   * Para servicios que también atienden a otros roles: si quien llama actúa
   * como administrador (y no por otro rol de [exceptRoles]), exige el permiso.
   */
  enforceAdminPermission(
    ctx: AppContext,
    code: string,
    exceptRoles: string[] = [],
  ) {
    if (!this.isAdmin(ctx)) return;
    if (exceptRoles.some((role) => ctx.roles.has(role))) return;
    this.requireAdminPermission(ctx, code);
  }

  requireAdminPermission(ctx: AppContext, codes: string | string[]) {
    const list = Array.isArray(codes) ? codes : [codes];
    if (!list.some((code) => this.hasAdminPermission(ctx, code))) {
      throw new HttpError(
        403,
        "No tienes permiso para realizar esta acción.",
        "forbidden",
      );
    }
  }

  isPlatformAdmin(ctx: AppContext) {
    return ctx.roles.has("admin") || ctx.roles.has("super_admin");
  }

  isSuperAdmin(ctx: AppContext) {
    return ctx.roles.has("super_admin");
  }

  hasAnyRole(ctx: AppContext, roles: string[]) {
    return roles.some((role) => ctx.roles.has(role)) || this.isAdmin(ctx);
  }

  requireRole(ctx: AppContext, roles: string[]) {
    if (!this.hasAnyRole(ctx, roles)) {
      throw new HttpError(
        403,
        "No tienes permiso para realizar esta acción.",
        "forbidden",
      );
    }
  }

  async currentTeacherId(ctx: AppContext) {
    if (ctx.teacherId !== undefined) return ctx.teacherId;
    if (ctx.personId == null) return ctx.teacherId = null;
    return ctx.teacherId = await this.repository.findTeacherIdByPerson(
      ctx.institutionId,
      ctx.personId,
    );
  }

  async currentStudentId(ctx: AppContext) {
    if (ctx.studentId !== undefined) return ctx.studentId;
    if (ctx.personId == null) return ctx.studentId = null;
    return ctx.studentId = await this.repository.findStudentIdByPerson(
      ctx.institutionId,
      ctx.personId,
    );
  }

  async currentParentId(ctx: AppContext) {
    if (ctx.parentId !== undefined) return ctx.parentId;
    if (ctx.personId == null) return ctx.parentId = null;
    return ctx.parentId = await this.repository.findParentIdByPerson(
      ctx.institutionId,
      ctx.personId,
    );
  }

  async assertTeacherCanUseClass(ctx: AppContext, classId: number, permission = "collaborators.manage") {
    const row = await this.repository.findClassForPermission(
      ctx.institutionId,
      classId,
    );

    if (this.isAdmin(ctx)) return row;

    this.requireRole(ctx, ["teacher"]);
    const teacherId = await this.currentTeacherId(ctx);
    if (teacherId == null || (Number(row.teacher_id) !== teacherId && !await this.repository.classPermission(classId, permission))) {
      throw new HttpError(
        403,
        "No tienes el permiso necesario en esta clase.",
        "forbidden",
      );
    }
    return row;
  }

  async assertTeacherCanUseAssignment(ctx: AppContext, assignmentId: number, permission = "assignments.create") {
    const row = await this.repository.findAssignmentForPermission(
      ctx.institutionId,
      assignmentId,
    );
    const cls = row.classes as Record<string, unknown> | null;
    if (this.isAdmin(ctx)) return row;

    this.requireRole(ctx, ["teacher"]);
    const teacherId = await this.currentTeacherId(ctx);
    if (teacherId == null || (Number(cls?.teacher_id) !== teacherId && !await this.repository.classPermission(Number(row.class_id), permission))) {
      throw new HttpError(
        403,
        "No puedes modificar una tarea de otra clase.",
        "forbidden",
      );
    }
    return row;
  }

  async assertStudentEnrolledInClass(
    institutionId: number,
    studentId: number,
    classId: number,
    groupId?: number | null,
  ) {
    let gid = groupId ?? null;
    if (gid == null) {
      const cls = await this.repository.findClassGroupId(institutionId, classId);
      gid = Number(cls.group_id);
    }
    if (!Number.isFinite(gid)) {
      throw new HttpError(
        400,
        "La clase no tiene grupo académico asociado.",
        "validation_error",
      );
    }
    const exists = await this.repository.studentEnrollmentExists(
      institutionId,
      studentId,
      gid,
    );
    if (!exists) {
      throw new HttpError(
        403,
        "El estudiante no pertenece a esta clase.",
        "forbidden",
      );
    }
  }

  async normalizeStudentId(
    ctx: AppContext,
    requested: unknown,
    label = "estudiante",
  ) {
    const requestedId = optionalId(requested);
    if (ctx.roles.has("student") && !this.isAdmin(ctx)) {
      const mine = await this.currentStudentId(ctx);
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
    if (ctx.roles.has("parent") && !this.isAdmin(ctx)) {
      const parentId = await this.currentParentId(ctx);
      if (parentId == null || requestedId == null) {
        throw new HttpError(
          403,
          "No se pudo validar el estudiante del acudiente.",
          "forbidden",
        );
      }
      const exists = await this.repository.parentStudentLinkExists(
        ctx.institutionId,
        parentId,
        requestedId,
      );
      if (!exists) {
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
}

export const permissionsService = new PermissionsService();
