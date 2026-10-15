import {
  ADMIN_PERMISSION_CODES,
  ADMIN_PERMISSION_MODULES,
  ADMIN_PROFILE_ROLES,
  isAdminProfileRole,
  normalizeAdminPermissions,
} from "../../lib/admin-permissions";
import { HttpError } from "../../lib/errors";
import { paginationFromQuery, singlePage } from "../../lib/pagination";
import { requireSupabaseServiceRole } from "../../lib/supabase";
import type { AppContext } from "../../types/app-context";
import { asList, asRecord, optionalId, optionalString, requiredId, requiredString } from "../../validators/common.validators";
import {
  adminRepository,
  AdminRepository,
} from "./admin.repository";
import { permissionsService, PermissionsService } from "../../services/permissions.service";

type PeopleResource = "students" | "teachers" | "parents";

export class AdminService {
  constructor(
    private readonly repository: AdminRepository = adminRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async listInstitutions(ctx: AppContext, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    if (ctx.roles.has("super_admin")) {
      return this.repository.listInstitutions(
        this.listFilters(query),
        paginationFromQuery(query),
      );
    }
    return singlePage([await this.repository.findInstitution(ctx.institutionId)]);
  }

  async createInstitution(ctx: AppContext, payload: Record<string, unknown>) {
    if (!ctx.roles.has("super_admin")) {
      throw new HttpError(403, "Solo super administración puede crear instituciones.", "forbidden");
    }
    return {
      institution: await this.repository.createInstitution({
        code: requiredString(payload.code, "Código", 50).toUpperCase(),
        name: requiredString(payload.name, "Nombre", 200),
        commercial_name: optionalString(payload.commercialName ?? payload.commercial_name, 200),
        subdomain: optionalString(payload.subdomain, 100),
        email: optionalString(payload.email, 150),
        phone: optionalString(payload.phone, 30),
        timezone: optionalString(payload.timezone, 50) ?? "America/Managua",
        active: this.optionalBoolean(payload.active, true),
      }),
    };
  }

  async updateInstitution(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const id = requiredId(idValue, "Institución");
    if (!ctx.roles.has("super_admin") && id !== ctx.institutionId) {
      throw new HttpError(403, "No puedes modificar otra institución.", "forbidden");
    }
    return {
      institution: await this.repository.updateInstitution(id, this.clean({
        code: this.optionalUpper(payload.code, 50),
        name: this.optionalText(payload.name, 200),
        commercial_name: this.optionalText(payload.commercialName ?? payload.commercial_name, 200),
        subdomain: this.optionalText(payload.subdomain, 100),
        email: this.optionalText(payload.email, 150),
        phone: this.optionalText(payload.phone, 30),
        timezone: this.optionalText(payload.timezone, 50),
        active: this.optionalBoolean(payload.active),
      })),
    };
  }

  async archiveInstitution(ctx: AppContext, idValue: unknown) {
    if (!ctx.roles.has("super_admin")) {
      throw new HttpError(403, "Solo super administración puede archivar instituciones.", "forbidden");
    }
    return { institution: await this.repository.archiveInstitution(requiredId(idValue, "Institución")) };
  }

  async listUsers(ctx: AppContext, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    return this.repository.listUsers(
      this.targetInstitutionFilter(ctx, query),
      this.listFilters(query),
      paginationFromQuery(query),
    );
  }

  async createUser(ctx: AppContext, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const personId = optionalId(payload.personId ?? payload.person_id);
    const user = await this.repository.createUser({
      institution_id: institutionId,
      person_id: personId,
      auth_user_id: optionalString(payload.authUserId ?? payload.auth_user_id, 80),
      username: optionalString(payload.username, 100),
      email: requiredString(payload.email, "Correo", 150),
      phone: optionalString(payload.phone, 30),
      full_name: requiredString(payload.fullName ?? payload.full_name, "Nombre completo", 200),
      avatar_url: optionalString(payload.avatarUrl ?? payload.avatar_url, 2000),
      active: this.optionalBoolean(payload.active, true),
    });
    await this.replaceRolesIfPresent(ctx, institutionId, Number(user.id), payload);
    return { user: await this.repository.findUser(institutionId, Number(user.id)) };
  }

  async updateUser(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const id = requiredId(idValue, "Usuario");
    const user = await this.repository.updateUser(institutionId, id, this.clean({
      person_id: this.optionalIdValue(payload.personId ?? payload.person_id),
      username: this.optionalText(payload.username, 100),
      email: this.optionalText(payload.email, 150),
      phone: this.optionalText(payload.phone, 30),
      full_name: this.optionalText(payload.fullName ?? payload.full_name, 200),
      avatar_url: this.optionalText(payload.avatarUrl ?? payload.avatar_url, 2000),
      active: this.optionalBoolean(payload.active),
    }));
    await this.replaceRolesIfPresent(ctx, institutionId, id, payload);
    return { user: await this.repository.findUser(institutionId, Number(user.id)) };
  }

  async archiveUser(ctx: AppContext, idValue: unknown, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    return { user: await this.repository.archiveUser(institutionId, requiredId(idValue, "Usuario")) };
  }

  async listRoles(ctx: AppContext, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    return this.repository.listRoles(
      this.targetInstitutionFilter(ctx, query),
      paginationFromQuery(query, { pageSize: 100, maxPageSize: 200 }),
    );
  }

  async createRole(ctx: AppContext, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    return {
      role: await this.repository.createRole({
        institution_id: institutionId,
        name: requiredString(payload.name, "Nombre", 50),
        code: requiredString(payload.code, "Código", 30),
        description: optionalString(payload.description, 2000),
        is_system: false,
        active: this.optionalBoolean(payload.active, true),
      }),
    };
  }

  async updateRole(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    return {
      role: await this.repository.updateRole(institutionId, requiredId(idValue, "Rol"), this.clean({
        name: this.optionalText(payload.name, 50),
        code: this.optionalText(payload.code, 30),
        description: this.optionalText(payload.description, 2000),
        active: this.optionalBoolean(payload.active),
      })),
    };
  }

  async archiveRole(ctx: AppContext, idValue: unknown, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    return { role: await this.repository.archiveRole(institutionId, requiredId(idValue, "Rol")) };
  }

  async listPeople(ctx: AppContext, resource: PeopleResource, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    return this.repository.listPeopleResource(
      resource,
      this.targetInstitutionFilter(ctx, query),
      this.listFilters(query),
      paginationFromQuery(query),
    );
  }

  async directory(ctx: AppContext, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    return this.repository.listDirectory(institutionId);
  }

  async createPeople(ctx: AppContext, resource: PeopleResource, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const personPayload = this.personPayload(ctx, payload, "create");
    personPayload.institution_id = institutionId;
    const email = requiredString(payload.email ?? asRecord(payload.person).email, "Correo", 150);
    const password = requiredString(payload.password, "Contraseña", 200);
    if (password.length < 6) {
      throw new HttpError(400, "La contraseña debe tener al menos 6 caracteres.", "validation_error");
    }
    const person = await this.repository.createPerson(personPayload);
    const row = await this.repository.createPeopleResource(resource, {
      ...this.peoplePayload(resource, payload),
      institution_id: institutionId,
      person_id: person.id,
    });
    const user = await this.createLoginForPeopleResource(
      institutionId,
      Number(person.id),
      resource,
      {
        email,
        password,
        username: optionalString(payload.username, 100),
        phone: optionalString(payload.phone ?? asRecord(payload.person).phone, 30),
        fullName: `${personPayload.first_name ?? ""} ${personPayload.last_name ?? ""}`.trim(),
        active: this.optionalBoolean(payload.active, true),
      },
    );
    await this.syncPeopleRelations(
      institutionId,
      resource,
      Number(row.id),
      payload,
    );
    return { [this.entityName(resource)]: { ...row, user } };
  }

  async updatePeople(
    ctx: AppContext,
    resource: PeopleResource,
    idValue: unknown,
    payload: Record<string, unknown>,
  ) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const id = requiredId(idValue, "Registro");
    const current = await this.repository.findPeopleResource(resource, institutionId, id);
    const personPayload = this.personPayload(ctx, payload, "update");
    if (Object.keys(personPayload).length > 0) {
      await this.repository.updatePerson(institutionId, Number(current.person_id), personPayload);
    }
    const resourcePayload = this.peoplePayload(resource, payload, "update");
    const row = Object.keys(resourcePayload).length > 0
      ? await this.repository.updatePeopleResource(resource, institutionId, id, resourcePayload)
      : await this.repository.findPeopleResource(resource, institutionId, id);
    await this.syncPeopleRelations(institutionId, resource, id, payload);
    return { [this.entityName(resource)]: row };
  }

  async createGroup(ctx: AppContext, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const name = requiredString(payload.name, "Salón", 80);
    const year = await this.repository.currentAcademicYear(institutionId);
    const grade = await this.repository.findOrCreateGradeLevel(institutionId, name);
    const section = await this.repository.findOrCreateSection(
      institutionId,
      optionalString(payload.section, 20) ?? "General",
    );
    const classroom = await this.repository.findOrCreateClassroom(
      institutionId,
      optionalString(payload.room ?? payload.classroomName ?? payload.classroom_name, 50),
    );
    return {
      group: await this.repository.createGroup({
        institution_id: institutionId,
        academic_year_id: year.id,
        grade_level_id: grade.id,
        section_id: section.id,
        classroom_id: classroom?.id ?? null,
        guide_teacher_id: optionalId(payload.guideTeacherId ?? payload.guide_teacher_id),
        name,
        max_capacity: this.optionalNumber(payload.maxCapacity ?? payload.max_capacity),
        active: this.optionalBoolean(payload.active, true),
      }),
    };
  }

  async updateGroup(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const classroom = await this.repository.findOrCreateClassroom(
      institutionId,
      optionalString(payload.room ?? payload.classroomName ?? payload.classroom_name, 50),
    );
    return {
      group: await this.repository.updateGroup(institutionId, requiredId(idValue, "Salón"), this.clean({
        name: this.optionalText(payload.name, 80),
        classroom_id: classroom === null ? undefined : classroom.id,
        guide_teacher_id: this.optionalIdValue(this.presentField(payload, "guideTeacherId", "guide_teacher_id")),
        max_capacity: this.optionalNumber(payload.maxCapacity ?? payload.max_capacity),
        active: this.optionalBoolean(payload.active),
      })),
    };
  }

  async archiveGroup(ctx: AppContext, idValue: unknown, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    return { group: await this.repository.archiveGroup(institutionId, requiredId(idValue, "Salón")) };
  }

  async createClass(ctx: AppContext, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const groupId = requiredId(payload.groupId ?? payload.group_id, "Salón");
    const subjectName = requiredString(payload.subject ?? payload.subjectName ?? payload.subject_name, "Materia", 100);
    const subject = await this.repository.findOrCreateSubject(institutionId, subjectName);
    await this.repository.findGroup(institutionId, groupId);
    const classroom = await this.repository.findOrCreateClassroom(
      institutionId,
      optionalString(payload.room ?? payload.classroomName ?? payload.classroom_name, 50),
    );
    if (classroom != null) {
      await this.repository.updateGroup(institutionId, groupId, { classroom_id: classroom.id });
    }
    const year = await this.repository.currentAcademicYear(institutionId);
    return {
      class: await this.repository.createClass({
        institution_id: institutionId,
        group_id: groupId,
        subject_id: subject.id,
        teacher_id: optionalId(payload.teacherId ?? payload.teacher_id),
        academic_year_id: year.id,
        active: this.optionalBoolean(payload.active, true),
      }),
    };
  }

  async updateClass(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const groupId = this.optionalIdValue(payload.groupId ?? payload.group_id);
    const classroom = await this.repository.findOrCreateClassroom(
      institutionId,
      optionalString(payload.room ?? payload.classroomName ?? payload.classroom_name, 50),
    );
    if (groupId != null) {
      await this.repository.findGroup(institutionId, groupId);
    }
    if (classroom != null && groupId != null) {
      await this.repository.updateGroup(institutionId, groupId, { classroom_id: classroom.id });
    }
    const subjectName = this.optionalText(payload.subject ?? payload.subjectName ?? payload.subject_name, 100);
    const subject = subjectName == null
      ? null
      : await this.repository.findOrCreateSubject(institutionId, subjectName);
    return {
      class: await this.repository.updateClass(institutionId, requiredId(idValue, "Clase"), this.clean({
        group_id: groupId,
        subject_id: subject?.id,
        teacher_id: this.optionalIdValue(this.presentField(payload, "teacherId", "teacher_id")),
        active: this.optionalBoolean(payload.active),
      })),
    };
  }

  async archiveClass(ctx: AppContext, idValue: unknown, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    return { class: await this.repository.archiveClass(institutionId, requiredId(idValue, "Clase")) };
  }

  async archivePeople(ctx: AppContext, resource: PeopleResource, idValue: unknown, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    const id = requiredId(idValue, "Registro");
    const current = await this.repository.findPeopleResource(resource, institutionId, id);
    if (resource === "students" || resource === "teachers") {
      await this.repository.archivePeopleResource(resource, institutionId, id);
    }
    await this.repository.archivePerson(institutionId, Number(current.person_id));
    return { ok: true };
  }

  private ensureInstitutionAdmin(ctx: AppContext) {
    if (!this.permissions.isAdmin(ctx)) {
      throw new HttpError(
        403,
        "Solo administracion institucional puede gestionar catalogos escolares.",
        "forbidden",
      );
    }
  }

  private targetInstitutionId(
    ctx: AppContext,
    payload: Record<string, unknown>,
  ) {
    const requested = optionalId(payload.institutionId ?? payload.institution_id);
    if (this.permissions.isSuperAdmin(ctx)) {
      return requested ?? ctx.institutionId;
    }
    if (requested != null && requested !== ctx.institutionId) {
      throw new HttpError(403, "No puedes gestionar otra institución.", "forbidden");
    }
    return ctx.institutionId;
  }

  private targetInstitutionFilter(
    ctx: AppContext,
    payload: Record<string, unknown>,
  ) {
    if (this.permissions.isSuperAdmin(ctx)) {
      return optionalId(payload.institutionId ?? payload.institution_id);
    }
    return this.targetInstitutionId(ctx, payload);
  }

  private listFilters(query: Record<string, unknown>) {
    return this.clean({
      search: optionalString(query.search, 120),
      active: this.optionalBoolean(query.active),
    });
  }

  // ---------- Perfiles administrativos (rol + permisos por persona) ----------

  async listPermissionCatalog(ctx: AppContext) {
    this.ensureInstitutionAdmin(ctx);
    return {
      modules: ADMIN_PERMISSION_MODULES,
      roles: ADMIN_PROFILE_ROLES,
      mine: this.effectivePermissions(ctx),
    };
  }

  async listProfiles(ctx: AppContext, query: Record<string, unknown> = {}) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    const rows = await this.repository.listAdminProfiles(
      institutionId,
      ADMIN_PROFILE_ROLES,
    );
    return { profiles: rows.map((row) => this.profileView(row)) };
  }

  async createProfile(ctx: AppContext, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const roleCode = this.profileRoleCode(payload.roleCode ?? payload.role);
    this.assertCanAssignRole(ctx, roleCode);
    const permissions = this.permissionsFromPayload(ctx, payload.permissions, [
      "dashboard.view",
    ]);
    const email = requiredString(payload.email, "Correo", 150);
    const password = requiredString(payload.password, "Contraseña", 200);
    if (password.length < 6) {
      throw new HttpError(400, "La contraseña debe tener al menos 6 caracteres.", "validation_error");
    }
    const fullName = requiredString(payload.fullName ?? payload.full_name, "Nombre completo", 200);

    const admin = requireSupabaseServiceRole();
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
      app_metadata: {
        institution_id: institutionId,
        roles: [roleCode],
        provider: "email",
        providers: ["email"],
      },
    });
    if (error || data?.user == null) {
      throw new HttpError(
        400,
        error?.message ?? "No se pudo crear la cuenta de acceso.",
        "auth_user_create_failed",
      );
    }
    try {
      const user = await this.repository.createProfileUser({
        institution_id: institutionId,
        auth_user_id: data.user.id,
        username: optionalString(payload.username, 100),
        email,
        phone: optionalString(payload.phone, 30),
        full_name: fullName,
        active: this.optionalBoolean(payload.active, true),
        admin_permissions: permissions,
      });
      await this.replaceRolesIfPresent(ctx, institutionId, Number(user.id), {
        roleCodes: [roleCode],
      });
      const created = await this.repository.findUser(institutionId, Number(user.id));
      return { profile: this.profileView(created) };
    } catch (failure) {
      await admin.auth.admin.deleteUser(data.user.id).catch(() => undefined);
      throw failure;
    }
  }

  async updateProfile(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    this.ensureInstitutionAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const id = requiredId(idValue, "Perfil");
    const current = await this.repository.findUser(institutionId, id);
    const currentRole = this.profileRoleOf(current);
    if (currentRole == null) {
      throw new HttpError(400, "El usuario no es un perfil administrativo.", "validation_error");
    }
    this.assertCanAssignRole(ctx, currentRole);

    const wantsRole = payload.roleCode !== undefined || payload.role !== undefined;
    const roleCode = wantsRole
      ? this.profileRoleCode(payload.roleCode ?? payload.role)
      : currentRole;
    if (roleCode !== currentRole) this.assertCanAssignRole(ctx, roleCode);

    const changesAccess = roleCode !== currentRole ||
      payload.permissions !== undefined ||
      this.optionalBoolean(payload.active) === false;
    if (id === ctx.userId && changesAccess) {
      throw new HttpError(
        400,
        "No puedes cambiar tu propio rol, permisos ni desactivar tu cuenta.",
        "validation_error",
      );
    }

    const changes = this.clean({
      full_name: this.optionalText(payload.fullName ?? payload.full_name, 200),
      phone: this.optionalText(payload.phone, 30),
      active: this.optionalBoolean(payload.active),
      admin_permissions: payload.permissions === undefined
        ? undefined
        : this.permissionsFromPayload(ctx, payload.permissions, []),
    });
    const user = Object.keys(changes).length > 0
      ? await this.repository.updateProfileUser(institutionId, id, changes)
      : current;

    if (roleCode !== currentRole) {
      await this.replaceRolesIfPresent(ctx, institutionId, id, { roleCodes: [roleCode] });
      const authUserId = String(current.auth_user_id ?? "");
      if (authUserId) {
        await requireSupabaseServiceRole()
          .auth.admin.updateUserById(authUserId, { app_metadata: { roles: [roleCode] } })
          .catch(() => undefined);
      }
    }
    const updated = await this.repository.findUser(institutionId, Number(user.id));
    return { profile: this.profileView(updated) };
  }

  private profileRoleCode(value: unknown) {
    const code = String(value ?? "").trim();
    if (!isAdminProfileRole(code)) {
      throw new HttpError(
        400,
        "El rol debe ser administrador, coordinador o director.",
        "validation_error",
      );
    }
    return code;
  }

  private profileRoleOf(row: Record<string, unknown>) {
    const roles = Array.isArray(row.user_roles) ? row.user_roles : [];
    for (const entry of roles as Record<string, unknown>[]) {
      const code = String((entry.roles as Record<string, unknown> | null)?.code ?? "");
      if (isAdminProfileRole(code)) return code;
    }
    return null;
  }

  /** Solo un administrador puede crear o editar perfiles con rol administrador. */
  private assertCanAssignRole(ctx: AppContext, roleCode: string) {
    if (roleCode === "admin" && !this.permissions.isPlatformAdmin(ctx)) {
      throw new HttpError(
        403,
        "Solo un administrador puede gestionar perfiles de administrador.",
        "forbidden",
      );
    }
  }

  /** Permisos efectivos de quien llama (null en el contexto = todos). */
  private effectivePermissions(ctx: AppContext) {
    if (ctx.roles.has("super_admin") || ctx.adminPermissions == null) {
      return [...ADMIN_PERMISSION_CODES];
    }
    return ctx.adminPermissions;
  }

  /** Valida la lista y evita conceder permisos que quien llama no tiene. */
  private permissionsFromPayload(
    ctx: AppContext,
    value: unknown,
    fallback: string[],
  ) {
    const permissions = value === undefined
      ? fallback
      : normalizeAdminPermissions(value);
    const own = this.effectivePermissions(ctx);
    const excess = permissions.filter((code) => !own.includes(code));
    if (excess.length > 0) {
      throw new HttpError(
        403,
        `No puedes conceder permisos que no tienes: ${excess.join(", ")}`,
        "forbidden",
      );
    }
    return permissions;
  }

  private profileView(row: Record<string, unknown>) {
    const customized = Array.isArray(row.admin_permissions);
    return {
      id: String(row.id),
      fullName: row.full_name,
      email: row.email,
      phone: row.phone ?? null,
      username: row.username ?? null,
      active: row.active !== false,
      roleCode: this.profileRoleOf(row),
      customized,
      permissions: customized
        ? (row.admin_permissions as unknown[]).map(String)
        : [...ADMIN_PERMISSION_CODES],
    };
  }

  private async replaceRolesIfPresent(
    ctx: AppContext,
    institutionId: number,
    userId: number,
    payload: Record<string, unknown>,
  ) {
    if (!("roleCodes" in payload) && !("roles" in payload)) return;
    const codes = asList(payload.roleCodes ?? payload.roles)
      .map((role) => requiredString(role, "Rol", 30));
    const roleIds: number[] = [];
    for (const code of codes) {
      if (code === "super_admin" && !ctx.roles.has("super_admin")) {
        throw new HttpError(
          403,
          "Solo un super administrador puede asignar ese rol.",
          "forbidden",
        );
      }
      const role = await this.repository.findRoleForAssignment(institutionId, code);
      if (role == null) {
        throw new HttpError(400, `Rol no existe o no pertenece a la institución: ${code}`, "validation_error");
      }
      roleIds.push(Number(role.id));
    }
    await this.repository.replaceUserRoles(institutionId, userId, roleIds);
  }

  private async syncPeopleRelations(
    institutionId: number,
    resource: PeopleResource,
    resourceId: number,
    payload: Record<string, unknown>,
  ) {
    if (resource === "students" && this.hasStudentEnrollmentPayload(payload)) {
      await this.repository.replaceStudentEnrollment(
        institutionId,
        resourceId,
        await this.resolveEnrollmentGroupId(institutionId, payload),
      );
    }
    if (resource === "teachers" && ("classIds" in payload || "class_ids" in payload)) {
      const classIds = asList(payload.classIds ?? payload.class_ids)
        .map((value) => requiredId(value, "Clase"));
      await this.repository.replaceTeacherClassAssignments(institutionId, resourceId, classIds);
    }
    if (resource === "parents" && ("childIds" in payload || "child_ids" in payload)) {
      const childIds = asList(payload.childIds ?? payload.child_ids)
        .map((value) => requiredId(value, "Estudiante"));
      await this.repository.replaceParentStudents(institutionId, resourceId, childIds);
    }
  }

  private hasStudentEnrollmentPayload(payload: Record<string, unknown>): boolean {
    return "groupId" in payload || "group_id" in payload ||
      "classId" in payload || "class_id" in payload ||
      "classIds" in payload || "class_ids" in payload;
  }

  private async resolveEnrollmentGroupId(
    institutionId: number,
    payload: Record<string, unknown>,
  ): Promise<number | null> {
    const explicitGroupId = optionalId(payload.groupId ?? payload.group_id) as number | null;
    const classIds: number[] = [
      ...asList(payload.classIds ?? payload.class_ids),
      ...(payload.classId !== undefined || payload.class_id !== undefined
        ? [payload.classId ?? payload.class_id]
        : []),
    ].map((value) => requiredId(value, "Clase"));
    if (classIds.length === 0) return explicitGroupId;
    const classes = await this.repository.findClasses(institutionId, classIds) as Record<string, unknown>[];
    if (classes.length !== [...new Set(classIds)].length) {
      throw new HttpError(400, "Una o más clases no existen o no pertenecen a la institución.", "validation_error");
    }
    const groupIds = [...new Set(classes.map((row) => Number(row.group_id)))];
    if (groupIds.length !== 1) {
      throw new HttpError(400, "Las clases seleccionadas deben pertenecer al mismo salón.", "validation_error");
    }
    if (explicitGroupId != null && explicitGroupId !== groupIds[0]) {
      throw new HttpError(400, "La clase seleccionada no pertenece al salón indicado.", "validation_error");
    }
    return groupIds[0];
  }

  private async createLoginForPeopleResource(
    institutionId: number,
    personId: number,
    resource: PeopleResource,
    account: {
      email: string;
      password: string;
      username: string | null;
      phone: string | null;
      fullName: string;
      active: boolean | undefined;
    },
  ) {
    const roleCode = this.roleCodeForResource(resource);
    const admin = requireSupabaseServiceRole();
    const { data, error } = await admin.auth.admin.createUser({
      email: account.email,
      password: account.password,
      email_confirm: true,
      user_metadata: { full_name: account.fullName },
      app_metadata: {
        institution_id: institutionId,
        roles: [roleCode],
        provider: "email",
        providers: ["email"],
      },
    });
    if (error || data?.user == null) {
      throw new HttpError(
        400,
        error?.message ?? "No se pudo crear la cuenta de acceso.",
        "auth_user_create_failed",
      );
    }

    const user = await this.repository.createUser({
      institution_id: institutionId,
      person_id: personId,
      auth_user_id: data.user.id,
      username: account.username,
      email: account.email,
      phone: account.phone,
      full_name: account.fullName,
      active: account.active,
    });
    await this.replaceRolesIfPresent(
      { institutionId, roles: new Set(["admin"]) } as AppContext,
      institutionId,
      Number(user.id),
      { roleCodes: [roleCode] },
    );
    return this.repository.findUser(institutionId, Number(user.id));
  }

  private roleCodeForResource(resource: PeopleResource) {
    switch (resource) {
      case "students":
        return "student";
      case "teachers":
        return "teacher";
      case "parents":
        return "parent";
    }
  }

  private personPayload(
    ctx: AppContext,
    payload: Record<string, unknown>,
    mode: "create" | "update",
  ) {
    const person = asRecord(payload.person);
    return this.clean({
      institution_id: mode === "create" ? ctx.institutionId : undefined,
      first_name: mode === "create"
        ? requiredString(payload.firstName ?? payload.first_name ?? person.firstName ?? person.first_name, "Nombre", 100)
        : this.optionalText(payload.firstName ?? payload.first_name ?? person.firstName ?? person.first_name, 100),
      last_name: mode === "create"
        ? requiredString(payload.lastName ?? payload.last_name ?? person.lastName ?? person.last_name, "Apellido", 100)
        : this.optionalText(payload.lastName ?? payload.last_name ?? person.lastName ?? person.last_name, 100),
      document_number: this.optionalText(payload.documentNumber ?? payload.document_number ?? person.documentNumber ?? person.document_number, 50),
      birth_date: this.optionalDate(payload.birthDate ?? payload.birth_date ?? person.birthDate ?? person.birth_date),
      email: this.optionalText(payload.email ?? person.email, 150),
      phone: this.optionalText(payload.phone ?? person.phone, 30),
      address: this.optionalText(payload.address ?? person.address, 2000),
      photo_url: this.optionalText(payload.photoUrl ?? payload.photo_url ?? person.photoUrl ?? person.photo_url, 2000),
    });
  }

  private peoplePayload(
    resource: PeopleResource,
    payload: Record<string, unknown>,
    mode: "create" | "update" = "create",
  ) {
    switch (resource) {
      case "students":
        return this.clean({
          student_code: mode === "create"
            ? requiredString(payload.studentCode ?? payload.student_code, "Código de estudiante", 50)
            : this.optionalText(payload.studentCode ?? payload.student_code, 50),
          enrollment_date: this.optionalDate(payload.enrollmentDate ?? payload.enrollment_date),
          blood_type: this.optionalText(payload.bloodType ?? payload.blood_type, 5),
          allergies: this.optionalText(payload.allergies, 2000),
          medical_notes: this.optionalText(payload.medicalNotes ?? payload.medical_notes, 2000),
          active: this.optionalBoolean(payload.active),
        });
      case "teachers":
        return this.clean({
          teacher_code: mode === "create"
            ? requiredString(payload.teacherCode ?? payload.teacher_code, "Código de docente", 50)
            : this.optionalText(payload.teacherCode ?? payload.teacher_code, 50),
          specialty: this.optionalText(payload.specialty, 100),
          academic_title: this.optionalText(payload.academicTitle ?? payload.academic_title, 100),
          hired_at: this.optionalDate(payload.hiredAt ?? payload.hired_at),
          active: this.optionalBoolean(payload.active),
        });
      case "parents":
        return this.clean({
          occupation: this.optionalText(payload.occupation, 100),
          workplace: this.optionalText(payload.workplace, 150),
          work_phone: this.optionalText(payload.workPhone ?? payload.work_phone, 30),
          is_emergency_contact: this.optionalBoolean(payload.isEmergencyContact ?? payload.is_emergency_contact),
        });
    }
  }

  private entityName(resource: PeopleResource) {
    return resource.slice(0, -1);
  }

  private optionalText(value: unknown, max: number) {
    return value === undefined ? undefined : optionalString(value, max);
  }

  private optionalUpper(value: unknown, max: number) {
    const text = this.optionalText(value, max);
    return text == null ? text : text.toUpperCase();
  }

  /** Valor de la primera clave presente en el payload; un `null` explícito cuenta (sirve para desasignar). */
  private presentField(payload: Record<string, unknown>, ...keys: string[]) {
    for (const key of keys) {
      if (key in payload) return payload[key];
    }
    return undefined;
  }

  private optionalIdValue(value: unknown) {
    return value === undefined ? undefined : optionalId(value);
  }

  private optionalDate(value: unknown) {
    if (value === undefined || value === null || value === "") return undefined;
    const date = new Date(String(value));
    if (Number.isNaN(date.getTime())) {
      throw new HttpError(400, "Fecha inválida.", "validation_error");
    }
    return date.toISOString().slice(0, 10);
  }

  private optionalBoolean(value: unknown, fallback?: boolean) {
    if (value === undefined || value === null || value === "") return fallback;
    return value === true || value === "true";
  }

  private optionalNumber(value: unknown) {
    if (value === undefined || value === null || value === "") return undefined;
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      throw new HttpError(400, "Número inválido.", "validation_error");
    }
    return parsed;
  }

  private clean(payload: Record<string, unknown>) {
    return Object.fromEntries(
      Object.entries(payload).filter(([, value]) => value !== undefined),
    );
  }
}

export const adminService = new AdminService();

