import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class EventsRepository {
  constructor(private readonly client: any = db) {}

  async publishAnnouncement(payload: Record<string, unknown>) {
    return expectSingle<{
      event: Record<string, unknown>;
      announcement: Record<string, unknown>;
      delivery: Record<string, unknown>;
    }>(
      this.client.rpc("publish_school_announcement", payload),
      "No se pudo guardar el anuncio.",
    );
  }

  async listPublishedAnnouncements(institutionId: number) {
    const { data, error } = await this.client.from("announcements")
      .select("id, title, content, audience, group_id, published_at, created_at, created_by, publication_key, calendar_events(start_at), announcement_delivery_jobs(status, phase, total, processed, notified, emailed, email_failed, email_skipped, push_failed, last_error, completed_at)")
      .eq("institution_id", institutionId)
      .eq("published", true)
      .order("published_at", { ascending: false, nullsFirst: false })
      .order("id", { ascending: false });
    assertNoDbError(error);
    return (data ?? []) as Array<Record<string, unknown>>;
  }

  async findDeliveryJob(institutionId: number, announcementId: string) {
    const { data, error } = await this.client.from("announcement_delivery_jobs").select("id, created_by")
      .eq("institution_id", institutionId).eq("announcement_id", announcementId).maybeSingle();
    assertNoDbError(error);
    return data;
  }

  async groupIdsForPerson(institutionId: number, personId: number) {
    const groups = new Set<number>();
    const studentIds = new Set<number>();
    for (const table of ["students", "parents", "teachers"]) {
      const { data, error } = await this.client.from(table).select("id")
        .eq("institution_id", institutionId).eq("person_id", personId);
      assertNoDbError(error);
      const ids = (data ?? []).map((row: { id: number }) => Number(row.id));
      if (ids.length === 0) continue;
      if (table === "students") {
        ids.forEach((id: number) => studentIds.add(id));
      } else if (table === "parents") {
        const links = await this.client.from("parent_students").select("student_id").in("parent_id", ids);
        assertNoDbError(links.error);
        (links.data ?? []).forEach((row: { student_id: number }) => studentIds.add(Number(row.student_id)));
      } else {
        const classes = await this.client.from("classes").select("group_id")
          .eq("institution_id", institutionId).in("teacher_id", ids);
        assertNoDbError(classes.error);
        (classes.data ?? []).forEach((row: { group_id: number }) => groups.add(Number(row.group_id)));
      }
    }
    if (studentIds.size > 0) {
      const { data, error } = await this.client.from("enrollments").select("group_id")
        .eq("institution_id", institutionId).in("student_id", [...studentIds]);
      assertNoDbError(error);
      (data ?? []).forEach((row: { group_id: number }) => groups.add(Number(row.group_id)));
    }
    return groups;
  }
}

export const eventsRepository = new EventsRepository();

