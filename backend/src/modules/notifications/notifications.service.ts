import { parsePushSubscription } from "../../lib/push-subscription";
import { assertNoDbError } from "../../lib/db";
import { requireSupabaseServiceRole } from "../../lib/supabase";
import { transactionRpc } from "../../lib/transaction-rpc";
import { HttpError } from "../../lib/errors";
import { requiredString } from "../../validators/common.validators";
import { notificationsRepository, NotificationsRepository, } from "./notifications.repository";
import type { AppContext } from "../../types/app-context";
export class NotificationsService {
    constructor(private readonly repository: NotificationsRepository = notificationsRepository) { }
    async saveWebPushDevice(ctx: AppContext, payload: Record<string, unknown>) {
        const endpoint = requiredString(payload.endpoint, "Endpoint push", 2000);
        const pushToken = requiredString(payload.pushToken, "Token push", 5000);
        let subscription;
        try {
            subscription = parsePushSubscription(pushToken);
        }
        catch {
            throw new HttpError(400, "Suscripción push inválida o proveedor no autorizado.", "validation_error");
        }
        let endpointUrl: string;
        try {
            endpointUrl = new URL(endpoint).href;
        }
        catch {
            throw new HttpError(400, "Endpoint push inválido.", "validation_error");
        }
        if (endpointUrl !== subscription.endpoint)
            throw new HttpError(400, "El endpoint no coincide con la suscripción.", "validation_error");
        await this.repository.saveDevice(subscription);
        return { ok: true };
    }
    /** Notificaciones reales del usuario autenticado (su cuenta e institución). */
    async listMine(ctx: AppContext) {
        const rows = await this.repository.listForUser(ctx.userId, ctx.institutionId);
        return rows.map((row) => {
            const type = row.catalog_notification_types as {
                code?: string;
            } | null;
            return {
                id: String(row.id),
                channel: this.channelForCatalogCode(type?.code),
                title: row.title ?? "",
                body: row.message ?? "",
                data: row.data ?? {},
                read: row.read === true,
                receivedAt: row.created_at,
            };
        });
    }
    private channelForCatalogCode(code?: string) {
        switch (code) {
            case "MSG":
                return "message";
            case "TASK":
                return "task";
            case "GRADE":
                return "grade";
            case "ATT":
                return "attendance";
            case "ANN":
                return "announcement";
            case "PAY":
                return "payment";
            default:
                return "system";
        }
    }
    async markRead(ctx: AppContext, id?: number) {
        const { error } = await this.repository.markRead(ctx.userId, ctx.institutionId, id);
        assertNoDbError(error);
        return { ok: true };
    }
    async remove(ctx: AppContext, id?: number) {
        const { error } = await this.repository.deleteForUser(ctx.userId, ctx.institutionId, id);
        assertNoDbError(error);
        return { ok: true };
    }
    async getPreferences(ctx: AppContext) {
        const row = await this.repository.getPreferences(ctx.userId, ctx.institutionId);
        return {
            emailEnabled: row.email_notifications_enabled !== false,
        };
    }
    async updatePreferences(ctx: AppContext, payload: Record<string, unknown>) {
        const update: Record<string, unknown> = {};
        // Acepta el nombre canónico y sus equivalentes para no ignorar en silencio
        // un valor mandado con otro nombre.
        const email = payload.emailEnabled ??
            payload.emailNotifications ??
            payload.email_notifications_enabled ??
            payload.email;
        if (email != null) {
            if (typeof email !== "boolean") {
                throw new HttpError(400, "Preferencia de correo inválida: debe ser true o false.", "validation_error");
            }
            update.email_notifications_enabled = email;
        }
        if (Object.keys(update).length === 0) {
            throw new HttpError(400, "Indica la preferencia a guardar (emailEnabled: true/false).", "validation_error");
        }
        const row = await this.repository.updatePreferences(ctx.userId, ctx.institutionId, update);
        return {
            emailEnabled: row.email_notifications_enabled !== false,
        };
    }
    async sendStoredPush(notificationId: number): Promise<'sent' | 'skipped' | 'failed' | 'pending'> {
        const result = await transactionRpc<{
            status: 'sent' | 'skipped' | 'failed' | 'pending';
        }>(requireSupabaseServiceRole(), 'notification_push_enqueue', { p_notification_id: notificationId });
        return result.status;
    }
}
export const notificationsService = new NotificationsService();
