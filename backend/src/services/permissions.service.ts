import type { AppContext } from "../types/app-context";
import { authRepository, AuthRepository } from "../repositories/auth.repository";
import { HttpError } from "../lib/errors";
import { optionalId } from "../validators/common.validators";

export class PermissionsService {
  constructor(private readonly repository: AuthRepository = authRepository) {}

  isAdmin(ctx: AppContext) {
    return ["admin", "super_admin", "coordinator", "director"].some((role) =>
      ctx.roles.has(role)
    );
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

  async assertTeacherCanUseClass(ctx: AppContext, classId: number) {
    const row = await this.repository.findClassForPermission(
      ctx.institutionId,
      classId,
    );

    if (this.isAdmin(ctx)) return row;

    this.requireRole(ctx, ["teacher"]);
    const teacherId = await this.currentTeacherId(ctx);
    if (teacherId == null || Number(row.teacher_id) !== teacherId) {
      throw new HttpError(
        403,
        "No puedes modificar una clase que no impartes.",
        "forbidden",
      );
    }
    return row;
  }

  async assertTeacherCanUseAssignment(ctx: AppContext, assignmentId: number) {
    const row = await this.repository.findAssignmentForPermission(
      ctx.institutionId,
      assignmentId,
    );
    const cls = row.classes as Record<string, unknown> | null;
    if (this.isAdmin(ctx)) return row;

    this.requireRole(ctx, ["teacher"]);
    const teacherId = await this.currentTeacherId(ctx);
    if (teacherId == null || Number(cls?.teacher_id) !== teacherId) {
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
      const cls = await this.repository.findClassGroupId(classId);
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
