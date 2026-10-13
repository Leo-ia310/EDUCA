import { expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class EventsRepository {
  async insertEvent(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("calendar_events")
        .insert(payload)
        .select("id, title, description, start_at, audience")
        .single(),
      "No se pudo crear el evento.",
    );
  }

  async insertAnnouncement(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("announcements")
        .insert(payload)
        .select("id, title, content, audience, published_at")
        .single(),
      "No se pudo crear el anuncio.",
    );
  }
}

export const eventsRepository = new EventsRepository();

