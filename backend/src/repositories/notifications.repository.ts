import { expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class NotificationsRepository {
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
