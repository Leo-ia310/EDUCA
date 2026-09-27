import { expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class NotificationsRepository {
  async listUsersByRoleCodes(institutionId: number, roleCodes: string[]) {
    const { data, error } = await db
      .from("users")
      .select("id, user_roles(roles(code))")
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
}

export const notificationsRepository = new NotificationsRepository();
