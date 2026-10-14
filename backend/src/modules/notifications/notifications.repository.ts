import { expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class NotificationsRepository {
  async listUsersByRoleCodes(institutionId: number, roleCodes: string[]) {
    const { data, error } = await db
      .from("users")
      .select("id, email, full_name, email_notifications_enabled, user_roles(roles(code))")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .is("deleted_at", null);
    if (error) throw error;
    return (data ?? []).filter((user: Record<string, unknown>) => {
      const roles = Array.isArray(user.user_roles) ? user.user_roles : [];
      return roles.some((entry: Record<string, unknown>) => {
        const role = entry.roles as Record<string, unknown> | null;
        return roleCodes.includes(String(role?.code ?? ""));
      });
    });
  }

  async insertNotification(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("notifications").insert(payload).select("id").single(),
      "No se pudo crear la notificación.",
    );
  }

  async insertDelivery(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("notification_deliveries").insert(payload).select("id").single(),
      "No se pudo registrar la entrega de la notificación.",
    );
  }

  async findNotificationTypeId(code: string) {
    const { data, error } = await db
      .from("catalog_notification_types")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (error) throw error;
    return data == null ? null : Number(data.id);
  }

  async findChannelId(code: string) {
    const { data, error } = await db
      .from("catalog_notification_channels")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (error) throw error;
    return data == null ? null : Number(data.id);
  }

  async listForUser(userId: number, institutionId: number, limit = 100) {
    const { data, error } = await db
      .from("notifications")
      .select(
        "id, title, message, data, read, read_at, created_at, catalog_notification_types(code)",
      )
      .eq("user_id", userId)
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false })
      .limit(limit);
    if (error) throw error;
    return (data ?? []) as Record<string, unknown>[];
  }

  async markRead(userId: number, institutionId: number, id?: number) {
    let query = db
      .from("notifications")
      .update({ read: true, read_at: new Date().toISOString() })
      .eq("user_id", userId)
      .eq("institution_id", institutionId)
      .eq("read", false);
    if (id != null) query = query.eq("id", id);
    return query;
  }

  async deleteForUser(userId: number, institutionId: number, id?: number) {
    let query = db
      .from("notifications")
      .delete()
      .eq("user_id", userId)
      .eq("institution_id", institutionId);
    if (id != null) query = query.eq("id", id);
    return query;
  }

  async findDevice(userId: number, endpoint: string) {
    const { data } = await db
      .from("devices")
      .select("id")
      .eq("user_id", userId)
      .eq("device_uuid", endpoint)
      .maybeSingle();
    return data;
  }

  async insertDevice(payload: Record<string, unknown>) {
    return expectSingle(
      db.from("devices").insert(payload).select("id").single(),
      "No se pudo guardar el dispositivo.",
    );
  }

  async updateDevice(id: unknown, payload: Record<string, unknown>) {
    return db.from("devices").update(payload).eq("id", id);
  }

  async getPreferences(userId: number, institutionId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("users")
        .select("email_notifications_enabled")
        .eq("id", userId)
        .eq("institution_id", institutionId)
        .single(),
      "No se pudieron cargar las preferencias de notificación.",
    );
  }

  async updatePreferences(
    userId: number,
    institutionId: number,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("users")
        .update(payload)
        .eq("id", userId)
        .eq("institution_id", institutionId)
        .select("email_notifications_enabled")
        .single(),
      "No se pudieron actualizar las preferencias de notificación.",
    );
  }
}

export const notificationsRepository = new NotificationsRepository();

