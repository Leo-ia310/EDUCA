import type { AppContext } from "../../types/app-context";
import { HttpError } from "../../lib/errors";
import { requiredDate, requiredString } from "../../validators/common.validators";
import { eventsRepository, EventsRepository, } from "./events.repository";
import { permissionsService, PermissionsService, } from "../../services/permissions.service";
import { paginationFromQuery } from "../../lib/pagination";
import { randomUUID } from "node:crypto";
import { announcementDeliveryQueue } from "./announcement-delivery.worker";
export class EventsService {
    constructor(private readonly repository: EventsRepository = eventsRepository, private readonly permissions: PermissionsService = permissionsService, private readonly queue: typeof announcementDeliveryQueue = announcementDeliveryQueue) { }
    async listAnnouncements(_ctx: AppContext, query: Record<string, unknown> = {}) {
        const beforeId = eventId(query.beforeId, true), limit = paginationFromQuery({ pageSize: query.limit ?? 50 }).pageSize;
        const result = await this.repository.listPublishedAnnouncements(beforeId, limit);
        return { ...result, announcements: result.announcements.map(mapAnnouncement) };
    }
    async deliveryStates(_ctx: AppContext, query: Record<string, unknown>) {
        if (typeof query.ids !== "string" || query.ids.length > 2100)
            throw new HttpError(400, "Selecciona hasta 100 anuncios.", "validation_error");
        const values = query.ids.split(",");
        if (values.length < 1 || values.length > 100)
            throw new HttpError(400, "Selecciona hasta 100 anuncios.", "validation_error");
        const ids = [...new Set(values.map(value => eventId(value, false)!))];
        const result = await this.repository.deliveryStates(ids);
        return { deliveries: result.deliveries.map((row: any) => ({ announcementId: row.announcementId, delivery: mapDelivery(row.delivery) })) };
    }
    async createEvent(ctx: AppContext, payload: Record<string, unknown>) {
        this.permissions.requireRole(ctx, ["teacher"]);
        const title = requiredString(payload.title, "Título", 150);
        const description = requiredString(payload.description, "Descripción", 2000);
        const date = requiredDate(payload.date, "Fecha");
        const audience = normalizeAudience(requiredString(payload.audience, "Audiencia", 50));
        const requestId = payload.requestId == null ? randomUUID() : String(payload.requestId);
        if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestId)) {
            throw new HttpError(400, "Solicitud de publicación inválida.", "validation_error");
        }
        this.queue.assertConfigured();
        const { event: row, announcement, delivery } = await this.repository.publishAnnouncement({
            p_institution_id: ctx.institutionId,
            p_created_by: ctx.userId,
            p_title: title,
            p_content: description,
            p_start_at: date.toISOString(),
            p_audience: audience,
            p_request_id: requestId,
        });
        this.queue.wake();
        return {
            event: {
                id: String(row.id),
                title: String(row.title ?? ""),
                description: String(row.description ?? ""),
                date: String(row.start_at ?? date.toISOString()),
                audience: String(row.audience ?? ""),
            },
            announcement: mapAnnouncement({ ...announcement, calendar_events: { start_at: row.start_at }, announcement_delivery_jobs: delivery }),
            notifications: { status: "queued" },
            notificationWarning: null,
        };
    }
    async retryDelivery(ctx: AppContext, announcementId: string) {
        this.permissions.requireRole(ctx, ["teacher"]);
        if (!/^\d+$/.test(announcementId))
            throw new HttpError(400, "Anuncio inválido.", "validation_error");
        const job = await this.repository.findDeliveryJob(ctx.institutionId, announcementId);
        if (!job)
            throw new HttpError(404, "No hay un envío pendiente para este anuncio.", "not_found");
        if (!this.permissions.isAdmin(ctx) && Number(job.created_by) !== ctx.userId) {
            throw new HttpError(403, "No tienes permiso para reintentar este envío.", "forbidden");
        }
        const delivery = await this.queue.retry(Number(job.id));
        this.queue.wake();
        return { delivery: mapDelivery(delivery) };
    }
}
export const eventsService = new EventsService();
function normalizeAudience(value: string) {
    const key = value
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "")
        .trim()
        .toLowerCase();
    switch (key) {
        case "all":
        case "toda la institucion":
            return "all";
        case "parents":
        case "parent":
        case "padres":
        case "padres y tutores":
            return "parents";
        case "students":
        case "student":
        case "estudiantes":
            return "students";
        case "teachers":
        case "teacher":
        case "docentes":
            return "teachers";
        case "admins":
        case "staff":
        case "administracion":
            return "staff";
        default:
            throw new HttpError(400, "Destinatarios de anuncio inválidos.", "validation_error");
    }
}
function mapAnnouncement(row: Record<string, unknown>) {
    const calendar = row.calendar_events as Record<string, unknown> | null;
    return {
        id: String(row.id),
        requestId: row.publication_key ?? null,
        delivery: mapDelivery(Array.isArray(row.announcement_delivery_jobs) ? row.announcement_delivery_jobs[0] : row.announcement_delivery_jobs),
        title: String(row.title ?? ""),
        content: String(row.content ?? ""),
        description: String(row.content ?? ""),
        audience: String(row.audience ?? "all"),
        date: String(calendar?.start_at ?? row.published_at ?? row.created_at),
        publishedAt: row.published_at ?? null,
        createdBy: row.created_by == null ? null : String(row.created_by),
        groupId: row.group_id == null ? null : String(row.group_id),
    };
}
function mapDelivery(value: unknown) {
    if (!value || typeof value !== "object")
        return null;
    const row = value as Record<string, unknown>;
    return { status: row.status, phase: row.phase, total: Number(row.total ?? 0),
        processed: Number(row.processed ?? 0), notified: Number(row.notified ?? 0),
        emailed: Number(row.emailed ?? 0), emailFailed: Number(row.email_failed ?? 0), emailReview: Number(row.email_review ?? 0),
        emailSkipped: Number(row.email_skipped ?? 0), pushFailed: Number(row.push_failed ?? 0),
        error: row.last_error ?? null, completedAt: row.completed_at ?? null, updatedAt: row.updated_at ?? null };
}
function eventId(value: unknown, optional: boolean): string | null {
    if (optional && (value == null || value === ""))
        return null;
    if (typeof value !== "string" && !(typeof value === "number" && Number.isSafeInteger(value)))
        throw new HttpError(400, "ID inválido.", "validation_error");
    const text = String(value).trim();
    if (!/^[1-9]\d{0,18}$/.test(text) || BigInt(text) > 9223372036854775807n)
        throw new HttpError(400, "ID inválido.", "validation_error");
    return text;
}
