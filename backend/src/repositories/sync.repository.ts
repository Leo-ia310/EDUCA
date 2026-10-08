import { assertNoDbError, expectSingle } from "../lib/db";
import { PageOptions, paged } from "../lib/pagination";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class SyncRepository {
  async listQueue(
    institutionId: number,
    userId: number,
    status: string | null | undefined,
    page: PageOptions,
  ) {
    let query = db
      .from("sync_queue")
      .select("*", { count: "exact" })
      .eq("institution_id", institutionId)
      .eq("user_id", userId)
      .order("created_at", { ascending: false });
    if (status) query = query.eq("status", status);
    const { data, error, count } = await query.range(page.from, page.to);
    assertNoDbError(error);
    return paged(data ?? [], count, page);
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

  async changesSince(institutionId: number, since: string, page: PageOptions) {
    const { data, error, count } = await db
      .from("change_log")
      .select("*", { count: "exact" })
      .eq("institution_id", institutionId)
      .gt("changed_at", since)
      .order("changed_at", { ascending: true })
      .range(page.from, page.to);
    assertNoDbError(error);
    return paged(data ?? [], count, page);
  }
}

export const syncRepository = new SyncRepository();
