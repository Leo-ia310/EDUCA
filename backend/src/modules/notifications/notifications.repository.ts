import { expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class NotificationsRepository {
  constructor(private readonly client: any = db) {}

  private isOptionalNotificationsSchemaError(error: unknown) {
    if (error == null || typeof error !== "object") return false;
    const record = error as Record<string, unknown>;
    const code = String(record.code ?? "");
    const message = String(record.message ?? record.details ?? "");
    return (
      code === "42P01" ||
      code === "PGRST200" ||
      message.includes('relation "notifications" does not exist') ||
      message.includes("Could not find a relationship") ||
      message.includes("catalog_notification_types")
    );
  }

  async listUsersByRoleCodes(institutionId: number, roleCodes: string[]) {
    const { data, error } = await this.client
      .from("users")
      .select(
        "id, email, full_name, email_notifications_enabled, user_roles(roles(code))",
      )
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
      this.client.from("notifications").insert(payload).select("id").single(),
      "No se pudo crear la notificación.",
    );
  }

  async insertDelivery(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      this.client.from("notification_deliveries").insert(payload).select("id").single(),
      "No se pudo registrar la entrega de la notificación.",
    );
  }

  async findNotificationTypeId(code: string) {
    const { data, error } = await this.client
      .from("catalog_notification_types")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (error) throw error;
    return data == null ? null : Number(data.id);
  }

  async findNotification(id: number) {
    const { data, error } = await this.client
      .from("notifications")
      .select("id, user_id, title, message, data")
      .eq("id", id)
      .maybeSingle();
    if (error) throw error;
    return data as Record<string, unknown> | null;
  }

  /** Suscripciones Web Push activas del usuario (devices.push_token = JSON). */
  async listActiveWebDevices(userId: number) {
    const { data, error } = await this.client
      .from("devices")
      .select("id, push_token")
      .eq("user_id", userId)
      .eq("platform", "web")
      .eq("active", true);
    if (error) throw error;
    return (data ?? []) as Array<{ id: number; push_token: string }>;
  }

  async deactivateDevice(id: number) {
    return this.client.from("devices").update({ active: false }).eq("id", id);
  }

  async findChannelId(code: string) {
    const { data, error } = await this.client
      .from("catalog_notification_channels")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (error) throw error;
    return data == null ? null : Number(data.id);
  }

  async listForUser(userId: number, institutionId: number, limit = 100) {
    const { data, error } = await this.client
      .from("notifications")
      .select(
        "id, title, message, data, read, read_at, created_at, catalog_notification_types(code)",
      )
      .eq("user_id", userId)
      .eq("institution_id", institutionId)
      .order("created_at", { ascending: false })
      .limit(limit);
    if (error) {
      if (this.isOptionalNotificationsSchemaError(error)) return [];
      throw error;
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
    if (id != null) query = query.eq("id", id);
    return query;
  }

  /** Marca como leídas las notificaciones de chat de una conversación. */
  async markConversationRead(
    userId: number,
    institutionId: number,
    conversationId: number,
    readAt: string,
  ) {
    return this.client
      .from("notifications")
      .update({ read: true, read_at: readAt })
      .eq("user_id", userId)
      .eq("institution_id", institutionId)
      .eq("read", false)
      .filter("data->>conversationId", "eq", String(conversationId))
      .lte("created_at", readAt);
  }

  async deleteForUser(userId: number, institutionId: number, id?: number) {
    let query = this.client
      .from("notifications")
      .delete()
      .eq("user_id", userId)
      .eq("institution_id", institutionId);
    if (id != null) query = query.eq("id", id);
    return query;
  }

  async findDevice(userId: number, endpoint: string) {
    const { data } = await this.client
      .from("devices")
      .select("id")
      .eq("user_id", userId)
      .eq("device_uuid", endpoint)
      .maybeSingle();
    return data;
  }

  async insertDevice(payload: Record<string, unknown>) {
    return expectSingle(
      this.client.from("devices").insert(payload).select("id").single(),
      "No se pudo guardar el dispositivo.",
    );
  }

  async updateDevice(id: unknown, payload: Record<string, unknown>) {
    return this.client.from("devices").update(payload).eq("id", id);
  }

  async getPreferences(userId: number, institutionId: number) {
    return expectSingle<Record<string, unknown>>(
      this.client
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
      this.client
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
