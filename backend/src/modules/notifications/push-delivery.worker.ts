import { parsePushSubscription } from "../../lib/push-subscription";
import { detached } from "../../lib/request-lifetime";
import webpush from "web-push";
import { env } from "../../lib/env";
import { supabaseServiceRole } from "../../lib/supabase";
type PushJob = {
    id: string;
    token: string;
    notificationId: string;
    deviceId: string;
    subscription: string;
    title: string;
    body: string;
    deepLink: string;
    tag: string;
};
type Outcome = "sent" | "retry" | "failed" | "gone";
export interface PushDeliveryQueue {
    claim(): Promise<PushJob | null>;
    finish(job: PushJob, outcome: Outcome, retryAfter: number): Promise<boolean>;
}
export type PushDeliveryTransport = (job: PushJob) => Promise<void>;
// A lost provider acknowledgement may repeat one device after its lease expires.
// Stable notification tags replace the visible card; Web Push offers no exactly-once guarantee.
export class PushDeliveryWorker {
    private stopped = false;
    private claiming = false;
    private timer?: NodeJS.Timeout;
    private active = new Set<Promise<void>>();
    constructor(private readonly queue: PushDeliveryQueue, private readonly send: PushDeliveryTransport) { }
    start() {
        if (this.timer)
            return;
        this.stopped = false;
        this.timer = setInterval(() => this.wake(), 2000);
        this.timer.unref();
        this.wake();
    }
    wake() { void detached(() => this.runOnce()).catch(() => console.error({ event: "notification_push_worker_unavailable" })); }
    async runOnce() {
        if (this.stopped || this.claiming)
            return;
        this.claiming = true;
        const started: Promise<void>[] = [];
        let admitted = 0;
        try {
            while (!this.stopped && this.active.size < 2 && admitted < 2) {
                const job = await this.queue.claim();
                if (!job)
                    break;
                admitted++;
                const task = this.process(job).catch(() => console.error({ event: "notification_push_checkpoint_unavailable" })).finally(() => { this.active.delete(task); });
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
    private async process(job: PushJob) {
        let outcome: Outcome = "sent", retryAfter = 0;
        try {
            await this.send(job);
        }
        catch (error) {
            const failure = error as {
                statusCode?: number;
                headers?: Record<string, string>;
            };
            const status = failure.statusCode;
            outcome = status === 404 || status === 410 ? "gone" : status == null || status === 408 || status === 429 || status >= 500 ? "retry" : "failed";
            const raw = failure.headers?.["retry-after"];
            const seconds = raw == null ? 0 : /^\d+$/.test(raw) ? Number(raw) : (Date.parse(raw) - Date.now()) / 1000;
            retryAfter = Number.isFinite(seconds) ? Math.max(0, Math.min(3600, Math.ceil(seconds))) : 0;
        }
        if (!await this.queue.finish(job, outcome, retryAfter))
            console.warn({ event: "notification_push_lease_lost", jobId: job.id });
    }
    async stop() {
        this.stopped = true;
        clearInterval(this.timer);
        this.timer = undefined;
        while (this.claiming || this.active.size) {
            await Promise.allSettled([...this.active]);
            if (this.claiming)
                await new Promise(resolve => setTimeout(resolve, 10));
        }
    }
}
let worker: PushDeliveryWorker | undefined;
export function startPushDeliveryWorker() {
    if (worker)
        return;
    if (!supabaseServiceRole || !env.vapidPublicKey || !env.vapidPrivateKey) {
        console.warn({ event: "notification_push_worker_disabled", reason: "backend_vapid_and_service_role_required" });
        return;
    }
    const client = supabaseServiceRole;
    webpush.setVapidDetails(env.vapidSubject, env.vapidPublicKey, env.vapidPrivateKey);
    worker = new PushDeliveryWorker({
        async claim() {
            const { data, error } = await client.rpc("notification_push_claim");
            if (error)
                throw Error("Push queue unavailable");
            return data as PushJob | null;
        },
        async finish(job, outcome, retryAfter) {
            const { data, error } = await client.rpc("notification_push_finish", { p_id: job.id, p_token: job.token, p_outcome: outcome, p_retry_after: retryAfter });
            if (error)
                throw Error("Push checkpoint unavailable");
            return data === true;
        },
    }, async (job) => {
        let subscription: webpush.PushSubscription;
        try {
            subscription = parsePushSubscription(job.subscription);
        }
        catch {
            throw { statusCode: 410 };
        }
        await webpush.sendNotification(subscription, JSON.stringify({ title: job.title, body: job.body, deepLink: job.deepLink, tag: job.tag }), { TTL: 3600, urgency: "high", timeout: 10000 });
    });
    worker.start();
}
export async function stopPushDeliveryWorker() { await worker?.stop(); worker = undefined; }
