import { requireSupabaseServiceRole, supabaseServiceRole } from "../../lib/supabase";
import { EmailService, emailService } from "../auth/email.service";
import { NotificationsRepository } from "../notifications/notifications.repository";
import { NotificationsService } from "../notifications/notifications.service";
import { AnnouncementDeliveryRepository, DeliveryJob } from "./announcement-delivery.repository";

// The database owns the queue and recipient checkpoints. No request JWT or
// in-memory task is needed to resume after a server restart.
export class AnnouncementDeliveryWorker {
  private running = false;
  private stopped = false;
  private timer?: NodeJS.Timeout;
  private lastEmailAt = 0;
  constructor(private readonly repository: AnnouncementDeliveryRepository,
    private readonly emails: Pick<EmailService, "sendAnnouncement">,
    private readonly pushes: Pick<NotificationsService, "sendStoredPush">,
    private readonly emailIntervalMs = 600) {}

  start() { this.timer = setInterval(() => this.wake(), 2000); this.timer.unref(); this.wake(); }
  stop() { this.stopped = true; clearInterval(this.timer); }
  wake() { void this.runOnce().catch(() => console.error({ event: "announcement_worker_unavailable" })); }
  async runOnce() {
    if (this.running || this.stopped) return;
    this.running = true;
    try { const job = await this.repository.claim(); if (job) await this.process(job); }
    finally { this.running = false; }
  }
  private async process(job: DeliveryJob) {
    let leaseLost = false;
    const heartbeat = setInterval(() => {
      void this.repository.heartbeat(job).catch(() => { leaseLost = true; });
    }, 30000);
    heartbeat.unref();
    try {
      await this.repository.prepare(job);
      while (!this.stopped && !leaseLost) {
        const recipients = await this.repository.pending(job);
        if (!recipients.length) {
          await this.repository.finish(job);
          console.log({ event: "announcement_delivery_finished", announcementId: job.announcement_id });
          return;
        }
        for (const recipient of recipients) {
          if (this.stopped || leaseLost) return;
          const active = recipient.users?.active && !recipient.users.deleted_at;
          let email = recipient.email_status, push = recipient.push_status, emailId: string | null = null, error: string | null = null;
          if (push === "pending") {
            try { push = active && await this.pushes.sendStoredPush(Number(recipient.notification_id)) ? "sent" : "skipped"; }
            catch { push = "failed"; }
          }
          if (email === "pending") {
            if (!active || !recipient.email || recipient.users?.email_notifications_enabled === false) email = "skipped";
            else {
              const wait = Math.max(0, this.emailIntervalMs - (Date.now() - this.lastEmailAt));
              if (wait) await new Promise((resolve) => setTimeout(resolve, wait));
              if (this.stopped || leaseLost) return;
              this.lastEmailAt = Date.now();
              try {
                const sent = await this.emails.sendAnnouncement(recipient.email, recipient.full_name,
                  job.payload.title, job.payload.description, `announcement/${job.announcement_id}/recipient/${recipient.user_id}`);
                emailId = sent.id == null ? null : String(sent.id); email = "sent";
              } catch { email = "failed"; error = "No se pudo enviar el correo. Reintenta el envío."; }
            }
          }
          await this.repository.record(job, recipient, email, push, emailId, error);
        }
      }
    } catch (error) {
      if (leaseLost || String(error).includes("delivery_lease_lost")) return;
      if (job.attempts >= 3) await this.repository.finish(job, "No se pudo completar el envío. Puedes reintentarlo.");
      else await this.repository.release(job);
    } finally { clearInterval(heartbeat); }
  }
}

let worker: AnnouncementDeliveryWorker | undefined;
export const announcementDeliveryQueue = {
  assertConfigured() { requireSupabaseServiceRole(); },
  wake() { worker?.wake(); },
  retry(id: number) { return new AnnouncementDeliveryRepository(requireSupabaseServiceRole()).retry(id); },
};
export function startAnnouncementDeliveryWorker() {
  if (!supabaseServiceRole) { console.warn({ event: "announcement_worker_disabled", reason: "service_role_required" }); return; }
  worker = new AnnouncementDeliveryWorker(new AnnouncementDeliveryRepository(supabaseServiceRole), emailService,
    new NotificationsService(new NotificationsRepository(supabaseServiceRole)));
  worker.start();
  process.once("SIGTERM", () => worker?.stop());
  process.once("SIGINT", () => worker?.stop());
}
