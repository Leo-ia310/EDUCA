import { detached } from "../../lib/request-lifetime";
import { env } from "../../lib/env";
import { EmailProviderError } from "../../lib/email-provider-budget";
import { requireSupabaseServiceRole, supabaseServiceRole } from "../../lib/supabase";
import { EmailService, emailService } from "../auth/email.service";
import { NotificationsRepository } from "../notifications/notifications.repository";
import { NotificationsService } from "../notifications/notifications.service";
import { AnnouncementDeliveryRepository, DeliveryJob } from "./announcement-delivery.repository";
type QueueRepository = Pick<AnnouncementDeliveryRepository, "claim" | "prepare" | "pending" | "heartbeat" | "beginEmail" | "record" | "finish" | "pause">;
type WorkerOptions = {
    concurrency?: number;
    recipientsPerSlice?: number;
    maxSliceMs?: number;
};
// PostgreSQL owns admission, leases, rate slots and recipient checkpoints.
export class AnnouncementDeliveryWorker {
    private stopped = false;
    private claiming = false;
    private timer?: NodeJS.Timeout;
    private readonly active = new Set<Promise<void>>();
    private readonly concurrency: number;
    private readonly sliceSize: number;
    private readonly maxSliceMs: number;
    constructor(private readonly repository: QueueRepository, private readonly emails: Pick<EmailService, "sendPreparedAnnouncement">, private readonly pushes: Pick<NotificationsService, "sendStoredPush">, options: WorkerOptions = {}) {
        this.concurrency = options.concurrency ?? env.announcementWorkers;
        this.sliceSize = options.recipientsPerSlice ?? 20;
        this.maxSliceMs = options.maxSliceMs ?? 10000;
        if (!Number.isInteger(this.concurrency) || this.concurrency < 1 || this.concurrency > 4
            || !Number.isInteger(this.sliceSize) || this.sliceSize < 1 || this.sliceSize > 100
            || !Number.isFinite(this.maxSliceMs) || this.maxSliceMs < 1 || this.maxSliceMs > 60000)
            throw new Error("Invalid announcement worker limits");
    }
    start() {
        if (this.timer)
            return;
        this.stopped = false;
        this.timer = setInterval(() => this.wake(), 2000);
        this.timer.unref();
        this.wake();
    }
    async stop() {
        this.stopped = true;
        clearInterval(this.timer);
        this.timer = undefined;
        // A provider request already started must be checkpointed before releasing
        // its lease. The server shutdown path can await this bounded drain.
        while (this.claiming || this.active.size) {
            await Promise.allSettled([...this.active]);
            if (this.claiming)
                await new Promise(resolve => setTimeout(resolve, 10));
        }
    }
    wake() { void detached(() => this.runOnce()).catch(() => console.error({ event: "announcement_worker_unavailable" })); }
    async runOnce() {
        if (this.stopped || this.claiming)
            return;
        const started: Promise<void>[] = [];
        let admitted = 0;
        this.claiming = true;
        try {
            while (!this.stopped && this.active.size < this.concurrency && admitted < this.concurrency) {
                const job = await this.repository.claim();
                if (!job)
                    break;
                admitted++;
                const task = this.process(job).catch(() => console.error({ event: "announcement_slice_unavailable" })).finally(() => { this.active.delete(task); });
                this.active.add(task);
                started.push(task);
            }
        }
        finally {
            this.claiming = false;
        }
        await Promise.all(started);
        if (!this.stopped && this.timer && started.length)
            setImmediate(() => this.wake());
    }
    private async process(job: DeliveryJob) {
        let leaseLost = false, heartbeatPending = false, finished = false, failed = false, retryDelay = 0;
        const heartbeat = setInterval(() => {
            if (heartbeatPending)
                return;
            heartbeatPending = true;
            void this.repository.heartbeat(job).catch(() => { leaseLost = true; }).finally(() => { heartbeatPending = false; });
        }, 30000);
        heartbeat.unref();
        try {
            await this.repository.prepare(job);
            const deadline = Date.now() + this.maxSliceMs;
            const recipients = await this.repository.pending(job, this.sliceSize);
            let completed = 0;
            for (const recipient of recipients) {
                if (this.stopped || leaseLost || (completed > 0 && Date.now() >= deadline))
                    break;
                const active = recipient.eligible && recipient.users?.active && !recipient.users.deleted_at;
                let email = recipient.email_status, push = recipient.push_status, emailId: string | null = null, error: string | null = null;
                if (push === "pending") {
                    try {
                        push = active ? await this.pushes.sendStoredPush(Number(recipient.notification_id)) : "skipped";
                        if (push === "pending")
                            retryDelay = 2000;
                    }
                    catch {
                        push = "failed";
                    }
                }
                if (email === "pending") {
                    if (!active || recipient.users?.email_notifications_enabled === false)
                        email = "skipped";
                    else {
                        try {
                            const sent = await this.emails.sendPreparedAnnouncement(job.payload.title, job.payload.description, async () => {
                                if (this.stopped || leaseLost)
                                    return { send: false, status: "pending" };
                                return this.repository.beginEmail(job, recipient);
                            });
                            email = sent.status;
                            emailId = sent.id ?? null;
                        }
                        catch (cause) {
                            if (String(cause).includes("delivery_lease_lost")) {
                                leaseLost = true;
                                return;
                            }
                            const provider = cause instanceof EmailProviderError ? cause : null;
                            if (!provider || provider.retryable) {
                                await this.repository.record(job, recipient, "pending", push, null, "No se pudo confirmar el envío. Se reintentará con la misma solicitud.");
                                failed = provider?.code !== "email_rate_limited";
                                retryDelay = Math.min(86400000, Math.max(5000 * job.attempts, provider?.retryAfterMs ?? 0));
                                if (failed && job.attempts >= 3) {
                                    await this.repository.finish(job, "No se pudo completar el envío. Puedes reintentarlo.");
                                    finished = true;
                                }
                                return;
                            }
                            if (["email_quota_exceeded", "email_provider_unavailable"].includes(provider.code)) {
                                await this.repository.record(job, recipient, "pending", push, null, provider.message);
                                await this.repository.finish(job, provider.message);
                                finished = true;
                                return;
                            }
                            email = "needs_review";
                            error = "El envío requiere revisión antes de volver a enviar el correo.";
                        }
                    }
                }
                await this.repository.record(job, recipient, email, push, emailId, error);
                completed++;
            }
            if (!this.stopped && !leaseLost && (await this.repository.pending(job, 1)).length === 0) {
                await this.repository.finish(job);
                finished = true;
                console.log({ event: "announcement_delivery_finished", announcementId: job.announcement_id });
            }
        }
        catch (cause) {
            if (leaseLost || String(cause).includes("delivery_lease_lost")) {
                leaseLost = true;
                return;
            }
            failed = true;
            retryDelay = Math.min(60000, 5000 * job.attempts);
            if (job.attempts >= 3) {
                await this.repository.finish(job, "No se pudo completar el envío. Puedes reintentarlo.");
                finished = true;
            }
        }
        finally {
            clearInterval(heartbeat);
            if (!finished && !leaseLost)
                await this.repository.pause(job, failed, retryDelay);
        }
    }
}
let worker: AnnouncementDeliveryWorker | undefined;
export const announcementDeliveryQueue = {
    assertConfigured() { requireSupabaseServiceRole(); },
    wake() { worker?.wake(); },
    retry(id: number) { return new AnnouncementDeliveryRepository(requireSupabaseServiceRole()).retry(id); },
};
export function startAnnouncementDeliveryWorker() {
    if (!supabaseServiceRole) {
        console.warn({ event: "announcement_worker_disabled", reason: "service_role_required" });
        return;
    }
    if (worker)
        return;
    worker = new AnnouncementDeliveryWorker(new AnnouncementDeliveryRepository(supabaseServiceRole), emailService, new NotificationsService(new NotificationsRepository(supabaseServiceRole)));
    worker.start();
}
export async function stopAnnouncementDeliveryWorker() { await worker?.stop(); worker = undefined; }
