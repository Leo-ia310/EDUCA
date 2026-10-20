import { HttpError } from "../../lib/errors";
import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";
const db = supabaseAdmin as any;
export class EventsRepository {
    constructor(private readonly client: any = db) { }
    async publishAnnouncement(payload: Record<string, unknown>) {
        return expectSingle<{
            event: Record<string, unknown>;
            announcement: Record<string, unknown>;
            delivery: Record<string, unknown>;
        }>(this.client.rpc("publish_school_announcement", payload), "No se pudo guardar el anuncio.");
    }
    async listPublishedAnnouncements(beforeId: string | null, limit: number) {
        return this.readRpc("announcement_feed", { p_before_id: beforeId, p_limit: limit });
    }
    async deliveryStates(ids: string[]) {
        return this.readRpc("announcement_delivery_state", { p_ids: ids });
    }
    private async readRpc(name: string, args: Record<string, unknown>) {
        const { data, error } = await this.client.rpc(name, args);
        if (error)
            throw new HttpError(error.code === "42501" ? 403 : error.code === "22023" ? 400 : 503, error.code === "42501" ? "Acceso denegado." : "No se pudieron consultar los anuncios.", "announcement_query_error");
        if (data == null)
            throw new HttpError(503, "No se pudieron consultar los anuncios.", "announcement_query_error");
        return data;
    }
    async findDeliveryJob(institutionId: number, announcementId: string) {
        const { data, error } = await this.client.from("announcement_delivery_jobs").select("id, created_by")
            .eq("institution_id", institutionId).eq("announcement_id", announcementId).maybeSingle();
        assertNoDbError(error);
        return data;
    }
}
export const eventsRepository = new EventsRepository();
