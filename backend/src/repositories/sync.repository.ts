import { assertNoDbError, expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class SyncRepository {
  async listQueue(institutionId: number, userId: number, status?: string | null) {
    let query = db
      .from("sync_queue")
      .select("*")
      .eq("institution_id", institutionId)
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(100);
    if (status) query = query.eq("status", status);
    const { data, error } = await query;
    assertNoDbError(error);
    return data ?? [];
  }

  async enqueue(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("sync_queue").insert(payload).select("*").single(),
      "No se pudo registrar la operación offline.",
    );
  }

  async updateStatus(
    institutionId: number,
    userId: number,
    id: number,
    payload: Record<string, unknown>,
  ) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("sync_queue")
        .update(payload)
        .eq("institution_id", institutionId)
        .eq("user_id", userId)
        .eq("id", id)
        .select("*")
        .single(),
      "Operación offline no encontrada.",
    );
  }

  async changesSince(institutionId: number, since: string) {
    const { data, error } = await db
      .from("change_log")
      .select("*")
      .eq("institution_id", institutionId)
      .gt("changed_at", since)
      .order("changed_at", { ascending: true })
      .limit(500);
    assertNoDbError(error);
    return data ?? [];
  }
}

export const syncRepository = new SyncRepository();
