import assert from "node:assert/strict";
import { performance } from "node:perf_hooks";
import { AnnouncementDeliveryWorker } from "../src/modules/events/announcement-delivery.worker";
import { AnnouncementDeliveryRepository, DeliveryJob, DeliveryRecipient } from "../src/modules/events/announcement-delivery.repository";
import { EventsService } from "../src/modules/events/events.service";
import { EventsRepository } from "../src/modules/events/events.repository";
import { PermissionsService } from "../src/services/permissions.service";
import type { AppContext } from "../src/types/app-context";

async function main() {
  const job = { id: 1, announcement_id: 12, attempts: 1, lock_token: "lease", payload: { title: "Test", description: "Content" } } as DeliveryJob;
  const recipients: DeliveryRecipient[] = [1, 2, 3].map((id) => ({ user_id: id, email: `test${id}@invalid.test`,
    full_name: "Test", notification_id: id, email_status: "pending", push_status: "pending",
    users: { active: true, deleted_at: null, email_notifications_enabled: id !== 3 } }));
  let finished = 0, release = 0, claim = true;
  const repository = {
    async claim() { if (!claim) return null; claim = false; return job; },
    async prepare() {},
    async pending() { return recipients.filter((r) => r.email_status === "pending" || r.push_status === "pending"); },
    async heartbeat() {},
    async record(_job: DeliveryJob, r: DeliveryRecipient, email: string, push: string) { r.email_status = email; r.push_status = push; },
    async finish() { finished++; }, async release() { release++; },
  } as unknown as AnnouncementDeliveryRepository;
  const calls: string[] = [];
  const worker = new AnnouncementDeliveryWorker(repository, {
    async sendAnnouncement(_to, _name, _title, _text, key) {
      calls.push(key!);
      if (key!.endsWith("/2")) throw new Error("Provider unavailable");
      return { id: "fake-id" };
    },
  }, { async sendStoredPush() { return false; } }, 0);
  await worker.runOnce();
  assert.deepEqual(calls, ["announcement/12/recipient/1", "announcement/12/recipient/2"]);
  assert.deepEqual(recipients.map((r) => r.email_status), ["sent", "failed", "skipped"]);
  assert.equal(finished, 1); assert.equal(release, 0);
  // Resume never resends successful or failed recipients until explicit retry.
  claim = true; await worker.runOnce(); assert.equal(calls.length, 2);
  worker.stop();

  let woke = 0;
  const service = new EventsService({ async publishAnnouncement(params: Record<string, unknown>) {
    await new Promise((r) => setTimeout(r, 5));
    return { event: { id: 1, start_at: params.p_start_at }, announcement: { id: 1, publication_key: params.p_request_id },
      delivery: { status: "queued", phase: "queued" } };
  } } as unknown as EventsRepository, new PermissionsService(), {
    assertConfigured() {}, wake() { woke++; }, async retry() { return {}; },
  });
  const context = { institutionId: 2, userId: 5, roles: new Set(["admin"]), adminPermissions: null } as AppContext;
  const start = performance.now();
  const response = await service.createEvent(context, { title: "Test", description: "Test body", audience: "all", date: "2026-10-15" });
  const elapsed = performance.now() - start;
  assert.equal(response.announcement.delivery?.status, "queued");
  assert.equal(woke, 1);
  assert.ok(elapsed < 150, `Publication took ${elapsed}ms despite a 5ms database; should never wait for delivery`);
  console.log(`Worker checks passed: preferences, isolated failures, stable provider keys, checkpoint resume; create returned in ${elapsed.toFixed(1)}ms (5ms persistence, no delivery wait).`);
}
void main();
