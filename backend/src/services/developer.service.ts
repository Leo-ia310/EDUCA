import { HttpError } from "../lib/errors";
import {
  asList,
  asRecord,
  optionalId,
  optionalString,
  requiredId,
  requiredNumber,
  requiredString,
} from "../validators/common.validators";
import {
  developerRepository,
  DeveloperRepository,
  DeveloperTable,
} from "../repositories/developer.repository";
import type { AppContext } from "../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "./permissions.service";

type ResourceConfig = {
  table: DeveloperTable;
  entity: string;
};

const RESOURCES = {
  modules: {
    table: "developer_dashboard_modules",
    entity: "module",
  },
  apis: {
    table: "developer_api_registry",
    entity: "api",
  },
  tasks: {
    table: "developer_tasks",
    entity: "task",
  },
  featureFlags: {
    table: "developer_feature_flags",
    entity: "featureFlag",
  },
  systemChecks: {
    table: "developer_system_checks",
    entity: "systemCheck",
  },
} satisfies Record<string, ResourceConfig>;

export class DeveloperService {
  constructor(
    private readonly repository: DeveloperRepository = developerRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async summary(ctx: AppContext) {
    this.ensureDeveloper(ctx);
    const [counts, pendingTasks, recentAuditEvents] = await Promise.all([
      this.repository.summaryCounts(),
      this.repository.listPendingTasks(),
      this.repository.listRecentAuditEvents(),
    ]);
    return { counts, pendingTasks, recentAuditEvents };
  }

  async institutions(ctx: AppContext) {
    this.ensureDeveloper(ctx);
    return this.repository.listInstitutions();
  }

  async users(ctx: AppContext) {
    this.ensureDeveloper(ctx);
    return this.repository.listUsers();
  }

  async auditEvents(ctx: AppContext) {
    this.ensureDeveloper(ctx);
    return this.repository.listRecentAuditEvents(100);
  }

  async list(
    ctx: AppContext,
    resource: keyof typeof RESOURCES,
    query: Record<string, unknown>,
  ) {
    this.ensureDeveloper(ctx);
    return this.repository.list(
      RESOURCES[resource].table,
      this.filtersFor(resource, query),
    );
  }

  async create(
    ctx: AppContext,
    resource: keyof typeof RESOURCES,
    payload: Record<string, unknown>,
  ) {
    this.ensureDeveloper(ctx);
    const config = RESOURCES[resource];
    const record = await this.repository.create(
      config.table,
      this.payloadFor(ctx, resource, payload, "create"),
    );
    await this.log(ctx, config.table, record.id, "create", null, record);
    return { [config.entity]: record };
  }

  async update(
    ctx: AppContext,
    resource: keyof typeof RESOURCES,
    idValue: unknown,
    payload: Record<string, unknown>,
  ) {
    this.ensureDeveloper(ctx);
    const id = requiredId(idValue, "Registro");
    const config = RESOURCES[resource];
    const before = await this.repository.findById(config.table, id);
    const record = await this.repository.update(
      config.table,
      id,
      this.payloadFor(ctx, resource, payload, "update"),
    );
    await this.log(ctx, config.table, id, "update", before, record);
    return { [config.entity]: record };
  }

  async archive(
    ctx: AppContext,
    resource: keyof typeof RESOURCES,
    idValue: unknown,
  ) {
    this.ensureDeveloper(ctx);
    const id = requiredId(idValue, "Registro");
    const config = RESOURCES[resource];
    const before = await this.repository.findById(config.table, id);
    const record = await this.repository.archive(config.table, id, ctx.userId);
    await this.log(ctx, config.table, id, "archive", before, record);
    return { [config.entity]: record };
  }

  private ensureDeveloper(ctx: AppContext) {
    if (!this.permissions.isAdmin(ctx)) {
      throw new HttpError(
        403,
        "Solo administración puede usar el dashboard de desarrollador.",
        "forbidden",
      );
    }
  }

  private resolveInstitutionId(ctx: AppContext, payload: Record<string, unknown>) {
    const requested = optionalId(payload.institutionId ?? payload.institution_id);
    const wantsGlobal = payload.global === true || payload.institutionId === null;
    if (this.permissions.isAdmin(ctx) && ctx.roles.has("super_admin")) {
      if (wantsGlobal) return null;
      return requested ?? ctx.institutionId;
    }
    if (requested != null && requested !== ctx.institutionId) {
      throw new HttpError(
        403,
        "No puedes gestionar otra institución desde este dashboard.",
        "forbidden",
      );
    }
    return ctx.institutionId;
  }

  private institutionIdForPayload(
    ctx: AppContext,
    payload: Record<string, unknown>,
    mode: "create" | "update",
  ) {
    const hasInstitutionField =
      "institutionId" in payload ||
      "institution_id" in payload ||
      "global" in payload;
    if (mode === "update" && !hasInstitutionField) return undefined;
    return this.resolveInstitutionId(ctx, payload);
  }

  private payloadFor(
    ctx: AppContext,
    resource: keyof typeof RESOURCES,
    payload: Record<string, unknown>,
    mode: "create" | "update",
  ) {
    switch (resource) {
      case "modules":
        return this.clean({
          institution_id: this.institutionIdForPayload(ctx, payload, mode),
          module_key: mode === "create"
            ? requiredString(this.value(payload, "moduleKey", "module_key"), "Clave del módulo", 80)
            : this.optionalText(payload, ["moduleKey", "module_key"], 80),
          title: mode === "create"
            ? requiredString(payload.title, "Título", 120)
            : this.optionalText(payload, ["title"], 120),
          description: this.optionalText(payload, ["description"], 4000),
          category: this.optionalText(payload, ["category"], 50),
          icon: this.optionalText(payload, ["icon"], 50),
          frontend_route: this.optionalText(payload, ["frontendRoute", "frontend_route"], 150),
          required_roles: this.stringListField(payload, ["requiredRoles", "required_roles"]),
          enabled: this.optionalBooleanField(payload, ["enabled"]),
          display_order: this.optionalIntegerField(payload, ["displayOrder", "display_order"]),
          metadata: this.optionalRecordField(payload, ["metadata"]),
          [mode === "create" ? "created_by" : "updated_by"]: ctx.userId,
        });
      case "apis":
        return this.clean({
          institution_id: this.institutionIdForPayload(ctx, payload, mode),
          module_key: mode === "create"
            ? requiredString(this.value(payload, "moduleKey", "module_key"), "Módulo", 80)
            : this.optionalText(payload, ["moduleKey", "module_key"], 80),
          method: mode === "create"
            ? this.method(payload.method)
            : this.hasAny(payload, ["method"]) ? this.method(payload.method) : undefined,
          path: mode === "create"
            ? requiredString(payload.path, "Ruta", 200)
            : this.optionalText(payload, ["path"], 200),
          action: this.optionalText(payload, ["action"], 120),
          summary: mode === "create"
            ? requiredString(payload.summary, "Resumen", 180)
            : this.optionalText(payload, ["summary"], 180),
          description: this.optionalText(payload, ["description"], 4000),
          auth_required: this.optionalBooleanField(payload, ["authRequired", "auth_required"]),
          required_roles: this.stringListField(payload, ["requiredRoles", "required_roles"]),
          backend_status: this.optionalEnumField(
            payload,
            ["backendStatus", "backend_status"],
            ["planned", "implemented", "blocked", "deprecated"],
          ),
          frontend_status: this.optionalEnumField(
            payload,
            ["frontendStatus", "frontend_status"],
            ["pending", "connected", "blocked", "not_needed"],
          ),
          request_schema: this.optionalRecordField(payload, ["requestSchema", "request_schema"]),
          response_schema: this.optionalRecordField(payload, ["responseSchema", "response_schema"]),
          source_file: this.optionalText(payload, ["sourceFile", "source_file"], 250),
          owner: this.optionalText(payload, ["owner"], 120),
          priority: this.optionalEnumField(payload, ["priority"], ["low", "medium", "high", "critical"]),
          notes: this.optionalText(payload, ["notes"], 4000),
          active: this.optionalBooleanField(payload, ["active"]),
          metadata: this.optionalRecordField(payload, ["metadata"]),
          [mode === "create" ? "created_by" : "updated_by"]: ctx.userId,
        });
      case "tasks":
        return this.clean({
          institution_id: this.institutionIdForPayload(ctx, payload, mode),
          api_registry_id: this.optionalIdField(payload, ["apiRegistryId", "api_registry_id"]),
          module_key: this.optionalText(payload, ["moduleKey", "module_key"], 80),
          title: mode === "create"
            ? requiredString(payload.title, "Título", 180)
            : this.optionalText(payload, ["title"], 180),
          description: this.optionalText(payload, ["description"], 4000),
          status: this.optionalEnumField(
            payload,
            ["status"],
            ["pending", "ready", "in_progress", "blocked", "done", "cancelled"],
          ),
          priority: this.optionalEnumField(payload, ["priority"], ["low", "medium", "high", "critical"]),
          owner: this.optionalText(payload, ["owner"], 120),
          frontend_required: this.optionalBooleanField(payload, ["frontendRequired", "frontend_required"]),
          backend_ready: this.optionalBooleanField(payload, ["backendReady", "backend_ready"]),
          due_at: this.optionalDateField(payload, ["dueAt", "due_at"]),
          completed_at: this.optionalDateField(payload, ["completedAt", "completed_at"]),
          notes: this.optionalText(payload, ["notes"], 4000),
          metadata: this.optionalRecordField(payload, ["metadata"]),
          [mode === "create" ? "created_by" : "updated_by"]: ctx.userId,
        });
      case "featureFlags":
        return this.clean({
          institution_id: this.institutionIdForPayload(ctx, payload, mode),
          flag_key: mode === "create"
            ? requiredString(this.value(payload, "flagKey", "flag_key"), "Clave del flag", 100)
            : this.optionalText(payload, ["flagKey", "flag_key"], 100),
          title: mode === "create"
            ? requiredString(payload.title, "Título", 150)
            : this.optionalText(payload, ["title"], 150),
          description: this.optionalText(payload, ["description"], 4000),
          enabled: this.optionalBooleanField(payload, ["enabled"]),
          rollout_percent: this.optionalIntegerField(payload, ["rolloutPercent", "rollout_percent"]),
          config: this.optionalRecordField(payload, ["config"]),
          metadata: this.optionalRecordField(payload, ["metadata"]),
          [mode === "create" ? "created_by" : "updated_by"]: ctx.userId,
        });
      case "systemChecks":
        return this.clean({
          institution_id: this.institutionIdForPayload(ctx, payload, mode),
          check_key: mode === "create"
            ? requiredString(this.value(payload, "checkKey", "check_key"), "Clave del check", 100)
            : this.optionalText(payload, ["checkKey", "check_key"], 100),
          title: mode === "create"
            ? requiredString(payload.title, "Título", 150)
            : this.optionalText(payload, ["title"], 150),
          description: this.optionalText(payload, ["description"], 4000),
          check_type: this.optionalEnumField(payload, ["checkType", "check_type"], ["manual", "sql", "http", "script"]),
          target: this.optionalText(payload, ["target"], 4000),
          severity: this.optionalEnumField(payload, ["severity"], ["low", "medium", "high", "critical"]),
          status: this.optionalEnumField(payload, ["status"], ["unknown", "passing", "warning", "failing", "disabled"]),
          enabled: this.optionalBooleanField(payload, ["enabled"]),
          last_result: this.optionalRecordField(payload, ["lastResult", "last_result"]),
          last_checked_at: this.optionalDateField(payload, ["lastCheckedAt", "last_checked_at"]),
          metadata: this.optionalRecordField(payload, ["metadata"]),
          [mode === "create" ? "created_by" : "updated_by"]: ctx.userId,
        });
    }
  }

  private filtersFor(
    resource: keyof typeof RESOURCES,
    query: Record<string, unknown>,
  ) {
    const filters: Record<string, unknown> = {};
    const moduleKey = query.moduleKey ?? query.module_key;
    if (moduleKey) filters.module_key = moduleKey;

    if (resource === "apis") {
      if (query.frontendStatus) filters.frontend_status = query.frontendStatus;
      if (query.backendStatus) filters.backend_status = query.backendStatus;
    }
    if (resource === "tasks" && query.status) filters.status = query.status;
    if (resource === "featureFlags" && query.enabled != null) {
      filters.enabled = String(query.enabled) === "true";
    }
    if (resource === "systemChecks") {
      if (query.status) filters.status = query.status;
      if (query.severity) filters.severity = query.severity;
    }
    return filters;
  }

  private async log(
    ctx: AppContext,
    table: string,
    entityId: unknown,
    action: string,
    before: unknown,
    after: unknown,
  ) {
    await this.repository.audit({
      institution_id: ctx.institutionId,
      actor_user_id: ctx.userId,
      entity_table: table,
      entity_id: entityId == null ? null : String(entityId),
      action,
      data_before: before ?? null,
      data_after: after ?? null,
    });
  }

  private clean(payload: Record<string, unknown>) {
    return Object.fromEntries(
      Object.entries(payload).filter(([, value]) => value !== undefined),
    );
  }

  private method(value: unknown) {
    const method = requiredString(value, "Método", 10).toUpperCase();
    if (!["GET", "POST", "PUT", "PATCH", "DELETE"].includes(method)) {
      throw new HttpError(400, "Método HTTP inválido.", "validation_error");
    }
    return method;
  }

  private value(payload: Record<string, unknown>, ...keys: string[]) {
    for (const key of keys) {
      if (key in payload) return payload[key];
    }
    return undefined;
  }

  private hasAny(payload: Record<string, unknown>, keys: string[]) {
    return keys.some((key) => key in payload);
  }

  private optionalText(
    payload: Record<string, unknown>,
    keys: string[],
    max: number,
  ) {
    if (!this.hasAny(payload, keys)) return undefined;
    return optionalString(this.value(payload, ...keys), max);
  }

  private optionalIdField(payload: Record<string, unknown>, keys: string[]) {
    if (!this.hasAny(payload, keys)) return undefined;
    return optionalId(this.value(payload, ...keys));
  }

  private optionalEnumField(
    payload: Record<string, unknown>,
    keys: string[],
    allowed: string[],
  ) {
    if (!this.hasAny(payload, keys)) return undefined;
    return this.optionalEnum(this.value(payload, ...keys), allowed);
  }

  private optionalBooleanField(
    payload: Record<string, unknown>,
    keys: string[],
  ) {
    if (!this.hasAny(payload, keys)) return undefined;
    return this.optionalBoolean(this.value(payload, ...keys));
  }

  private optionalIntegerField(
    payload: Record<string, unknown>,
    keys: string[],
  ) {
    if (!this.hasAny(payload, keys)) return undefined;
    return this.optionalInteger(this.value(payload, ...keys));
  }

  private optionalDateField(
    payload: Record<string, unknown>,
    keys: string[],
  ) {
    if (!this.hasAny(payload, keys)) return undefined;
    return this.optionalDateString(this.value(payload, ...keys));
  }

  private optionalRecordField(
    payload: Record<string, unknown>,
    keys: string[],
  ) {
    if (!this.hasAny(payload, keys)) return undefined;
    return this.optionalRecord(this.value(payload, ...keys));
  }

  private stringListField(payload: Record<string, unknown>, keys: string[]) {
    if (!this.hasAny(payload, keys)) return undefined;
    return this.stringList(this.value(payload, ...keys));
  }

  private optionalEnum(value: unknown, allowed: string[]) {
    if (value == null || value === "") return undefined;
    const text = requiredString(value, "Valor", 40);
    if (!allowed.includes(text)) {
      throw new HttpError(400, "Valor fuera de catálogo.", "validation_error");
    }
    return text;
  }

  private optionalBoolean(value: unknown) {
    if (value == null || value === "") return undefined;
    return value === true || value === "true";
  }

  private optionalInteger(value: unknown) {
    if (value == null || value === "") return undefined;
    return Math.trunc(requiredNumber(value, "Número"));
  }

  private optionalDateString(value: unknown) {
    if (value == null || value === "") return undefined;
    const date = new Date(String(value));
    if (Number.isNaN(date.getTime())) {
      throw new HttpError(400, "Fecha inválida.", "validation_error");
    }
    return date.toISOString();
  }

  private optionalRecord(value: unknown) {
    if (value == null) return undefined;
    return asRecord(value);
  }

  private stringList(value: unknown) {
    if (value == null) return undefined;
    return asList(value).map((item) => requiredString(item, "Rol", 80));
  }
}

export const developerService = new DeveloperService();
