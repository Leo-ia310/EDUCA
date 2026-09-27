import { HttpError } from "../lib/errors";
import type { AppContext } from "../types/app-context";
import { asList, asRecord, optionalId, optionalString, requiredId, requiredString } from "../validators/common.validators";
import {
  adminRepository,
  AdminRepository,
} from "../repositories/admin.repository";
import { permissionsService, PermissionsService } from "./permissions.service";

type PeopleResource = "students" | "teachers" | "parents";

export class AdminService {
  constructor(
    private readonly repository: AdminRepository = adminRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async listInstitutions(ctx: AppContext, query: Record<string, unknown> = {}) {
    this.ensurePlatformAdmin(ctx);
    if (ctx.roles.has("super_admin")) {
      return this.repository.listInstitutions(this.listFilters(query));
    }
    return [await this.repository.findInstitution(ctx.institutionId)];
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
    this.ensurePlatformAdmin(ctx);
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
    this.ensurePlatformAdmin(ctx);
    return this.repository.listUsers(
      this.targetInstitutionFilter(ctx, query),
      this.listFilters(query),
    );
  }

  async createUser(ctx: AppContext, payload: Record<string, unknown>) {
    this.ensurePlatformAdmin(ctx);
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
    this.ensurePlatformAdmin(ctx);
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
    this.ensurePlatformAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    return { user: await this.repository.archiveUser(institutionId, requiredId(idValue, "Usuario")) };
  }

  async listRoles(ctx: AppContext, query: Record<string, unknown> = {}) {
    this.ensurePlatformAdmin(ctx);
    return this.repository.listRoles(
      this.targetInstitutionFilter(ctx, query),
    );
  }

  async createRole(ctx: AppContext, payload: Record<string, unknown>) {
    this.ensurePlatformAdmin(ctx);
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
    this.ensurePlatformAdmin(ctx);
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
    this.ensurePlatformAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    return { role: await this.repository.archiveRole(institutionId, requiredId(idValue, "Rol")) };
  }

  async listPeople(ctx: AppContext, resource: PeopleResource, query: Record<string, unknown> = {}) {
    this.ensurePlatformAdmin(ctx);
    return this.repository.listPeopleResource(
      resource,
      this.targetInstitutionFilter(ctx, query),
      this.listFilters(query),
    );
  }

  async createPeople(ctx: AppContext, resource: PeopleResource, payload: Record<string, unknown>) {
    this.ensurePlatformAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, payload);
    const personPayload = this.personPayload(ctx, payload, "create");
    personPayload.institution_id = institutionId;
    const person = await this.repository.createPerson(personPayload);
    const row = await this.repository.createPeopleResource(resource, {
      ...this.peoplePayload(resource, payload),
      institution_id: institutionId,
      person_id: person.id,
    });
    return { [this.entityName(resource)]: row };
  }

  async updatePeople(
    ctx: AppContext,
    resource: PeopleResource,
    idValue: unknown,
    payload: Record<string, unknown>,
  ) {
    this.ensurePlatformAdmin(ctx);
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
    return { [this.entityName(resource)]: row };
  }

  async archivePeople(ctx: AppContext, resource: PeopleResource, idValue: unknown, query: Record<string, unknown> = {}) {
    this.ensurePlatformAdmin(ctx);
    const institutionId = this.targetInstitutionId(ctx, query);
    const id = requiredId(idValue, "Registro");
    const current = await this.repository.findPeopleResource(resource, institutionId, id);
    if (resource === "students" || resource === "teachers") {
      await this.repository.archivePeopleResource(resource, institutionId, id);
    }
    await this.repository.archivePerson(institutionId, Number(current.person_id));
    return { ok: true };
  }

  private ensurePlatformAdmin(ctx: AppContext) {
    if (!this.permissions.isPlatformAdmin(ctx)) {
      throw new HttpError(403, "Solo admin o super admin puede gestionar catálogos institucionales.", "forbidden");
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
      const role = await this.repository.findRoleForAssignment(institutionId, code);
      if (role == null) {
        throw new HttpError(400, `Rol no existe o no pertenece a la institución: ${code}`, "validation_error");
      }
      roleIds.push(Number(role.id));
    }
    await this.repository.replaceUserRoles(institutionId, userId, roleIds);
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

  private clean(payload: Record<string, unknown>) {
    return Object.fromEntries(
      Object.entries(payload).filter(([, value]) => value !== undefined),
    );
  }
}

export const adminService = new AdminService();
