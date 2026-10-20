import { HttpError } from "../../lib/errors";
import { assertNoDbError, expectSingle } from "../../lib/db";
import { PageOptions, paged } from "../../lib/pagination";
import { supabaseAdmin } from "../../lib/supabase";
const db = supabaseAdmin as any;
export class SyncRepository {
    constructor(private readonly client: any = db) { }
    async listQueue(institutionId: number, userId: number, status: string | null | undefined, page: PageOptions) {
        let query = db
            .from("sync_queue")
            .select("*", { count: "exact" })
            .eq("institution_id", institutionId)
            .eq("user_id", userId)
            .order("created_at", { ascending: false });
        if (status)
            query = query.eq("status", status);
        const { data, error, count } = await query.range(page.from, page.to);
        assertNoDbError(error);
        return paged(data ?? [], count, page);
    }
    async enqueue(payload: Record<string, unknown>) {
        return expectSingle<Record<string, unknown>>(db.from("sync_queue").insert(payload).select("*").single(), "No se pudo registrar la operación offline.");
    }
    async updateStatus(institutionId: number, userId: number, id: number, payload: Record<string, unknown>) {
        return expectSingle<Record<string, unknown>>(db
            .from("sync_queue")
            .update(payload)
            .eq("institution_id", institutionId)
            .eq("user_id", userId)
            .eq("id", id)
            .select("*")
            .single(), "Operación offline no encontrada.");
    }
    async batch(sessions: Record<string, unknown>[], marks: Record<string, unknown>[]) {
        return this.rpc("sync_attendance_batch", { p_sessions: sessions, p_marks: marks });
    }
    async changesSince(at: string, id: string, limit: number) {
        return this.rpc("attendance_changes", { p_after_at: at, p_after_id: id, p_limit: limit });
    }
    private async rpc(name: string, args: Record<string, unknown>) {
        const { data, error } = await this.client.rpc(name, args);
        if (error || data == null) {
            const status = error?.code === '42501' ? 403 : error?.code === '23505' ? 409 : ['22023', '22007', '22008', '22P02'].includes(error?.code) ? 400 : 503;
            throw new HttpError(status, status === 409 ? 'La operación ya tiene otro contenido.' : status === 403 ? 'No tienes permiso para sincronizar esta clase.' : status === 400 ? 'Datos de sincronización inválidos.' : 'No se pudo sincronizar la asistencia.', 'attendance_sync_error');
        }
        return data;
    }
}
export const syncRepository = new SyncRepository();
