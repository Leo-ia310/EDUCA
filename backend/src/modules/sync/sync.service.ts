import { randomUUID } from "node:crypto";
import { HttpError } from "../../lib/errors";
import { paginationFromQuery } from "../../lib/pagination";
import type { AppContext } from "../../types/app-context";
import { asRecord, optionalString, requiredString, requiredDate, requiredId } from "../../validators/common.validators";
import { syncRepository, SyncRepository, } from "./sync.repository";
const ALLOWED_TABLES = new Set([
    "attendances",
    "class_sessions",
]);
const ALLOWED_OPERATIONS = new Set(["insert", "update", "upsert"]);
const ALLOWED_STATUSES = new Set(["queued", "processing", "synced", "failed"]);
export class SyncService {
    constructor(private readonly repository: SyncRepository = syncRepository) { }
    async list(ctx: AppContext, query: Record<string, unknown>) {
        this.requireTeacher(ctx);
        const status = optionalString(query.status, 20);
        if (status != null && !ALLOWED_STATUSES.has(status)) {
            throw new HttpError(400, "Estado de sync inválido.", "validation_error");
        }
        return this.repository.listQueue(ctx.institutionId, ctx.userId, status, paginationFromQuery(query, { pageSize: 100, maxPageSize: 200 }));
    }
    async enqueue(ctx: AppContext, payload: Record<string, unknown>) {
        this.requireTeacher(ctx);
        const tableName = requiredString(payload.tableName ?? payload.table_name, "Tabla", 80);
        if (!ALLOWED_TABLES.has(tableName)) {
            throw new HttpError(400, "La sincronización offline solo está habilitada para asistencia de profesores.", "validation_error");
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
    async batch(ctx: AppContext, payload: Record<string, unknown>) {
        this.requireTeacher(ctx);
        const sessions = array(payload.sessions ?? [], "sesiones").map(raw => {
            const row = asRecord(raw);
            return { classId: safeId(row.classId), date: day(row.date) };
        });
        const marks = array(payload.marks ?? [], "marcas").map(raw => {
            const row = asRecord(raw), version = Number(row.expectedVersion);
            if ((typeof row.expectedVersion !== "number" && typeof row.expectedVersion !== "string") || row.expectedVersion == null || !Number.isSafeInteger(version) || version < 0 || version > 2147483646)
                throw new HttpError(400, "Versión de asistencia inválida.", "validation_error");
            return { operationId: uuid(row.operationId), uuid: uuid(row.uuid), classId: safeId(row.classId), date: day(row.date),
                studentId: safeId(row.studentId), statusId: safeId(row.statusId), expectedVersion: version,
                recordedAt: requiredDate(row.recordedAt, "Fecha de marcado").toISOString(), notes: optionalString(row.notes, 500) };
        });
        return this.repository.batch(sessions, marks);
    }
    async pull(ctx: AppContext, query: Record<string, unknown>) {
        this.requireTeacher(ctx);
        if (query.page != null && String(query.page) !== '1')
            throw new HttpError(400, "Usa nextCursor para continuar la sincronización.", "validation_error");
        if (query.since != null && typeof query.since !== "string")
            throw new HttpError(400, "Fecha inicial inválida.", "validation_error");
        let at = typeof query.since === 'string' ? query.since : '1970-01-01T00:00:00Z', id = '0';
        if (query.cursor != null) {
            try {
                if (typeof query.cursor !== 'string' || query.cursor.length > 512)
                    throw Error();
                const cursor = JSON.parse(Buffer.from(query.cursor, 'base64url').toString('utf8'));
                at = cursor.updatedAt;
                id = cursor.id;
            }
            catch {
                throw new HttpError(400, "Cursor de sincronización inválido.", "validation_error");
            }
        }
        if (typeof at !== 'string' || at.length > 80 || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:\d\d)$/.test(at) || !Number.isFinite(Date.parse(at)) || typeof id !== 'string' || !/^\d{1,19}$/.test(id) || BigInt(id) > 9223372036854775807n)
            throw new HttpError(400, "Cursor de sincronización inválido.", "validation_error");
        const limit = Number(query.limit ?? query.pageSize ?? 100);
        if (!Number.isSafeInteger(limit) || limit < 1 || limit > 500)
            throw new HttpError(400, "El límite debe estar entre 1 y 500.", "validation_error");
        const result = await this.repository.changesSince(at, id, limit);
        return { serverTime: new Date().toISOString(), changes: { items: result.items, hasMore: result.hasMore,
                nextCursor: Buffer.from(JSON.stringify(result.cursor)).toString('base64url') },
            conflictPolicy: 'optimistic_version', scope: 'teacher_attendance_offline' };
    }
    private requireTeacher(ctx: AppContext) {
        if (!ctx.roles.has("teacher")) {
            throw new HttpError(403, "La sincronización offline solo aplica para profesores tomando asistencia.", "forbidden");
        }
    }
    private dateOrNow(value: string | null) {
        if (value == null)
            return new Date().toISOString();
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) {
            throw new HttpError(400, "Fecha cliente inválida.", "validation_error");
        }
        return date.toISOString();
    }
}
export const syncService = new SyncService();
function array(value: unknown, label: string): unknown[] {
    if (!Array.isArray(value) || value.length > 100)
        throw new HttpError(400, `Máximo 100 ${label} por lote.`, "validation_error");
    return value;
}
function uuid(value: unknown): string {
    if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))
        throw new HttpError(400, "UUID de sincronización inválido.", "validation_error");
    return value.toLowerCase();
}
function safeId(value: unknown): number {
    if (typeof value !== "number" && !(typeof value === "string" && /^[1-9]\d*$/.test(value)))
        throw new HttpError(400, "Identificador inválido.", "validation_error");
    const result = requiredId(value, "Identificador");
    if (!Number.isSafeInteger(result))
        throw new HttpError(400, "Identificador inválido.", "validation_error");
    return result;
}
function day(value: unknown): string {
    if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\d$/.test(value) || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value)
        throw new HttpError(400, "Fecha de clase inválida.", "validation_error");
    return value;
}
