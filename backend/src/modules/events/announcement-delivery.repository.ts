import { assertNoDbError } from "../../lib/db";

export type DeliveryJob = {
  id: number; announcement_id: number; institution_id: number; created_by: number;
  lock_token: string; attempts: number;
  payload: { title: string; description: string; audience: string };
};
export type DeliveryRecipient = {
  user_id: number; email: string | null; full_name: string; notification_id: number;
  email_status: string; push_status: string;
  users: { active: boolean; deleted_at: string | null; email_notifications_enabled: boolean } | null;
};

export class AnnouncementDeliveryRepository {
  constructor(private readonly client: any) {}
  private async rpc(name: string, args: Record<string, unknown> = {}) {
    const { data, error } = await this.client.rpc(name, args);
    assertNoDbError(error);
    return data;
  }
  claim(): Promise<DeliveryJob | null> { return this.rpc("claim_announcement_delivery"); }
  prepare(job: DeliveryJob) {
    return this.rpc("prepare_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token });
  }
  async pending(job: DeliveryJob): Promise<DeliveryRecipient[]> {
    const { data, error } = await this.client.from("announcement_delivery_recipients")
      .select("*, users(active, deleted_at, email_notifications_enabled)")
      .eq("job_id", job.id).or("email_status.eq.pending,push_status.eq.pending")
      .order("user_id").limit(50);
    assertNoDbError(error);
    return data ?? [];
  }
  async heartbeat(job: DeliveryJob) {
    const { data, error } = await this.client.from("announcement_delivery_jobs")
      .update({ lease_until: new Date(Date.now() + 120000).toISOString() })
      .eq("id", job.id).eq("lock_token", job.lock_token).eq("status", "processing").select("id").maybeSingle();
    assertNoDbError(error);
    if (!data) throw new Error("delivery_lease_lost");
  }
  record(job: DeliveryJob, recipient: DeliveryRecipient, email: string, push: string, emailId: string | null, error: string | null) {
    return this.rpc("record_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token,
      p_user_id: recipient.user_id, p_email_status: email, p_push_status: push, p_email_id: emailId, p_error: error });
  }
  finish(job: DeliveryJob, error: string | null = null) {
    return this.rpc("finish_announcement_delivery", { p_job_id: job.id, p_lock: job.lock_token, p_error: error });
  }
  async release(job: DeliveryJob) {
    const { error } = await this.client.from("announcement_delivery_jobs").update({ status: "queued", phase: "queued",
      lock_token: null, lease_until: null, next_attempt_at: new Date(Date.now() + 5000 * job.attempts).toISOString() })
      .eq("id", job.id).eq("lock_token", job.lock_token);
    assertNoDbError(error);
  }
  retry(id: number) { return this.rpc("retry_announcement_delivery", { p_job_id: id }); }
}
