import { transactionRpc } from "../../lib/transaction-rpc";
import { databaseError } from "../../lib/database-error";
import { expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";
const db = supabaseAdmin as any;
export class NotificationsRepository {
    constructor(private readonly client: any = db) { }
    async saveDevice(subscription: Record<string, unknown>) {
        return transactionRpc(this.client, 'notification_device_save', { p_subscription: subscription });
    }
    async listForUser(userId: number, institutionId: number, limit = 100) {
        const { data, error } = await this.client
            .from("notifications")
            .select("id, title, message, data, read, read_at, created_at, catalog_notification_types(code)")
            .eq("user_id", userId)
            .eq("institution_id", institutionId)
            .order("created_at", { ascending: false })
            .limit(limit);
        if (error) {
            throw databaseError(error);
        }
        return (data ?? []) as Record<string, unknown>[];
    }
    async markRead(userId: number, institutionId: number, id?: number) {
        let query = this.client
            .from("notifications")
            .update({ read: true, read_at: new Date().toISOString() })
            .eq("user_id", userId)
            .eq("institution_id", institutionId)
            .eq("read", false);
        if (id != null)
            query = query.eq("id", id);
        return query;
    }
    async deleteForUser(userId: number, institutionId: number, id?: number) {
        let query = this.client
            .from("notifications")
            .delete()
            .eq("user_id", userId)
            .eq("institution_id", institutionId);
        if (id != null)
            query = query.eq("id", id);
        return query;
    }
    async getPreferences(userId: number, institutionId: number) {
        return expectSingle<Record<string, unknown>>(this.client
            .from("users")
            .select("email_notifications_enabled")
            .eq("id", userId)
            .eq("institution_id", institutionId)
            .single(), "No se pudieron cargar las preferencias de notificación.");
    }
    async updatePreferences(userId: number, institutionId: number, payload: Record<string, unknown>) {
        return expectSingle<Record<string, unknown>>(this.client
            .from("users")
            .update(payload)
            .eq("id", userId)
            .eq("institution_id", institutionId)
            .select("email_notifications_enabled")
            .single(), "No se pudieron actualizar las preferencias de notificación.");
    }
}
export const notificationsRepository = new NotificationsRepository();
