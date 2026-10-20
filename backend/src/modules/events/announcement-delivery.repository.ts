import { assertNoDbError } from "../../lib/db";
export type DeliveryJob = {
    id: number;
    announcement_id: number;
    institution_id: number;
    created_by: number;
    lock_token: string;
    attempts: number;
    payload: {
        title: string;
        description: string;
        audience: string;
    };
};
export type DeliveryRecipient = {
    user_id: number;
    email: string | null;
    full_name: string;
    notification_id: number;
    email_status: string;
    push_status: string;
    eligible: boolean;
    users: {
        active: boolean;
        deleted_at: string | null;
        email_notifications_enabled: boolean;
    } | null;
};
export class AnnouncementDeliveryRepository {
    constructor(private readonly client: any) { }
    private async rpc(name: string, args: Record<string, unknown> = {}) {
        const { data, error } = await this.client.rpc(name, args);
        assertNoDbError(error);
        return data;
    }
    claim(): Promise<DeliveryJob | null> { return this.rpc("claim_announcement_delivery"); }
    prepare(job: DeliveryJob) {
        return this.rpc("prepare_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token });
    }
    pending(job: DeliveryJob, limit = 50): Promise<DeliveryRecipient[]> {
        return this.rpc("announcement_pending_page", { p_job_id: job.id, p_lock: job.lock_token, p_limit: limit });
    }
    heartbeat(job: DeliveryJob) {
        return this.rpc("heartbeat_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token });
    }
    beginEmail(job: DeliveryJob, recipient: DeliveryRecipient): Promise<{
        send: boolean;
        status: string;
        email?: string;
        fullName?: string;
        idempotencyKey?: string;
        validUntil?: string;
    }> {
        return this.rpc("begin_announcement_email", { p_job_id: job.id, p_lock: job.lock_token, p_user_id: recipient.user_id });
    }
    record(job: DeliveryJob, recipient: DeliveryRecipient, email: string, push: string, emailId: string | null, error: string | null) {
        return this.rpc("record_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token,
            p_user_id: recipient.user_id, p_email_status: email, p_push_status: push, p_email_id: emailId, p_error: error });
    }
    finish(job: DeliveryJob, error: string | null = null) {
        return this.rpc("finish_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token, p_error: error });
    }
    pause(job: DeliveryJob, failed = false, delayMs = 0) {
        return this.rpc("pause_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token, p_failed: failed, p_delay_ms: delayMs });
    }
    retry(id: number) { return this.rpc("retry_announcement_delivery", { p_job_id: id }); }
}
