import assert from "node:assert/strict";
import { EventsRepository } from "../src/modules/events/events.repository";
import { EventsService } from "../src/modules/events/events.service";
import { PermissionsService } from "../src/services/permissions.service";
import { announcementDeliveryQueue } from "../src/modules/events/announcement-delivery.worker";
import type { AppContext } from "../src/types/app-context";

const admin = { institutionId: 2, userId: 5, personId: 5, roles: new Set(["admin"]), adminPermissions: null } as AppContext;
let failSave = false;

let deliveries = 0;
const rows: Array<Record<string, unknown>> = [];
const repository = {
  async publishAnnouncement(params: Record<string, unknown>) {
    assert.equal(params.p_institution_id, admin.institutionId);
    assert.equal(params.p_created_by, admin.userId);
    if (failSave) throw new Error("database unavailable");
    const event = { id: 10, start_at: params.p_start_at, title: params.p_title, description: params.p_content, audience: params.p_audience };
    const announcement = { id: rows.length + 1, institution_id: 2, created_by: 5, title: params.p_title, content: params.p_content, audience: params.p_audience, published_at: new Date().toISOString(), calendar_events: { start_at: params.p_start_at } };
    rows.push(announcement);
    return { event, announcement, delivery: { status: "queued", phase: "queued" } };
  },
  async listPublishedAnnouncements(institutionId: number) {
    return rows.filter((row) => row.institution_id === institutionId);
  },
  async groupIdsForPerson() { return new Set([7]); },
} as unknown as EventsRepository;
const notifier: typeof announcementDeliveryQueue = {
  assertConfigured() {},
  wake() { deliveries++; },
  async retry() { return {}; },
};

async function main() {
  const service = new EventsService(repository, new PermissionsService(), notifier);
  const payload = { institutionId: 999, createdBy: 999, title: "Aviso", description: "Contenido", date: "2000-01-01T00:00:00Z", audience: "Padres y tutores" };
  const created = await service.createEvent(admin, payload);
  assert.equal(created.announcement.audience, "parents");
  assert.equal(created.announcement.createdBy, "5");
  assert.equal(created.notificationWarning, null);
  assert.equal((await service.listAnnouncements(admin)).announcements[0].id, created.announcement.id, "Past events remain visible in announcements");
  failSave = true;
  await assert.rejects(service.createEvent(admin, payload), /database unavailable/);
  assert.equal(deliveries, 1, "Do not notify for failed saves");
  failSave = false;
  // Delivery runs outside the publication request.
  const originalError = console.error;
  console.error = () => {};
  try {
    const saved = await service.createEvent(admin, payload);
    assert.equal(saved.notificationWarning, null);
    assert.equal(saved.notifications.status, "queued");
    assert.equal((await service.listAnnouncements(admin)).announcements.length, 2, "Delivery failures do not lose saved announcements");
  } finally { console.error = originalError; }
  await assert.rejects(service.createEvent(admin, { ...payload, audience: "unknown" }), /Destinatarios/);
  const student = { ...admin, userId: 30, roles: new Set(["student"]) };
  await assert.rejects(service.createEvent(student, payload), /No tienes permiso/);
  rows.push(
    { id: 3, institution_id: 2, audience: "all", created_by: 5 },
    { id: 4, institution_id: 2, audience: "students", created_by: 5 },
    { id: 5, institution_id: 2, audience: "all", group_id: 7, created_by: 5 },
    { id: 6, institution_id: 2, audience: "all", group_id: 8, created_by: 5 },
    { id: 7, institution_id: 999, audience: "all", created_by: 5 },
  );
  assert.deepEqual((await service.listAnnouncements(student)).announcements.map((row) => row.id), ["3", "4", "5"]);
  assert.equal((await service.listAnnouncements(admin)).announcements.length, 6);

  // Query contract: the API filters by the session institution and published,
  // propagates DB errors and never applies the upcoming-calendar date cutoff.
  const filters: Array<[string, unknown]> = [];
  const query = {
    select() { return this; }, eq(key: string, value: unknown) { filters.push([key, value]); return this; },
    order() { return this; },
    then(resolve: (value: unknown) => unknown) { return Promise.resolve({ data: [], error: null }).then(resolve); },
  };
  const actualRepository = new EventsRepository({ from(table: string) { assert.equal(table, "announcements"); return query; } });
  assert.deepEqual(await actualRepository.listPublishedAnnouncements(2), []);
  assert.deepEqual(filters, [["institution_id", 2], ["published", true]]);
  console.log("Announcement checks passed: persistence, past dates, institution, author, audience/group visibility, validation and delivery failures.");
}
void main();
