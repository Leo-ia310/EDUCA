import { randomUUID } from "node:crypto";

import { HttpError } from "../lib/errors";
import type { AppContext } from "../types/app-context";
import { asRecord, optionalString, requiredString } from "../validators/common.validators";
import {
  syncRepository,
  SyncRepository,
} from "../repositories/sync.repository";

const ALLOWED_TABLES = new Set([
  "attendances",
  "class_sessions",
]);

const ALLOWED_OPERATIONS = new Set(["insert", "update", "upsert"]);
const ALLOWED_STATUSES = new Set(["queued", "processing", "synced", "failed"]);

export class SyncService {
  constructor(
    private readonly repository: SyncRepository = syncRepository,
  ) {}

  async list(ctx: AppContext, query: Record<string, unknown>) {
    this.requireTeacher(ctx);
    const status = optionalString(query.status, 20);
    if (status != null && !ALLOWED_STATUSES.has(status)) {
      throw new HttpError(400, "Estado de sync inválido.", "validation_error");
    }
    return this.repository.listQueue(ctx.institutionId, ctx.userId, status);
  }

  async enqueue(ctx: AppContext, payload: Record<string, unknown>) {
    this.requireTeacher(ctx);
    const tableName = requiredString(payload.tableName ?? payload.table_name, "Tabla", 80);
    if (!ALLOWED_TABLES.has(tableName)) {
      throw new HttpError(
        400,
        "La sincronización offline solo está habilitada para asistencia de profesores.",
        "validation_error",
      );
    }
    const operation = requiredString(payload.operation, "Operación", 20);
    if (!ALLOWED_OPERATIONS.has(operation)) {
      throw new HttpError(400, "Operación offline inválida.", "validation_error");
    }
    const recordUuid = optionalString(payload.recordUuid ?? payload.record_uuid, 80) ?? randomUUID();
    const clientTimestamp = optionalString(payload.clientTimestamp ?? payload.client_timestamp, 80);
    return {
      item: await this.repository.enqueue({
        institution_id: ctx.institutionId,
        user_id: ctx.userId,
        table_name: tableName,
        record_uuid: recordUuid,
        operation,
        payload: asRecord(payload.payload),
        status: "queued",
        attempts: 0,
        client_timestamp: this.dateOrNow(clientTimestamp),
        server_timestamp: new Date().toISOString(),
      }),
    };
  }

  async retry(ctx: AppContext, idValue: unknown) {
    this.requireTeacher(ctx);
    const id = Number(idValue);
    if (!Number.isInteger(id) || id <= 0) {
      throw new HttpError(400, "Operación offline inválida.", "validation_error");
    }
    return {
      item: await this.repository.updateStatus(ctx.institutionId, ctx.userId, id, {
        status: "queued",
        error: null,
        server_timestamp: new Date().toISOString(),
      }),
    };
  }

  async markFailed(ctx: AppContext, idValue: unknown, payload: Record<string, unknown>) {
    this.requireTeacher(ctx);
    const id = Number(idValue);
    if (!Number.isInteger(id) || id <= 0) {
      throw new HttpError(400, "Operación offline inválida.", "validation_error");
    }
    return {
      item: await this.repository.updateStatus(ctx.institutionId, ctx.userId, id, {
        status: "failed",
        error: optionalString(payload.error, 2000),
        server_timestamp: new Date().toISOString(),
      }),
    };
  }

  async pull(ctx: AppContext, query: Record<string, unknown>) {
    this.requireTeacher(ctx);
    const since = optionalString(query.since, 80) ?? "1970-01-01T00:00:00.000Z";
    const date = new Date(since);
    if (Number.isNaN(date.getTime())) {
      throw new HttpError(400, "Fecha since inválida.", "validation_error");
    }
    return {
      serverTime: new Date().toISOString(),
      changes: await this.repository.changesSince(ctx.institutionId, date.toISOString()),
      conflictPolicy: "teacher_attendance_upload_only",
      scope: "teacher_attendance_offline",
    };
  }

  private requireTeacher(ctx: AppContext) {
    if (!ctx.roles.has("teacher")) {
      throw new HttpError(
        403,
        "La sincronización offline solo aplica para profesores tomando asistencia.",
        "forbidden",
      );
    }
  }

  private dateOrNow(value: string | null) {
    if (value == null) return new Date().toISOString();
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      throw new HttpError(400, "Fecha cliente inválida.", "validation_error");
    }
    return date.toISOString();
  }
}

export const syncService = new SyncService();
