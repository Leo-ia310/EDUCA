import assert from 'node:assert/strict';
import { test } from 'node:test';
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
const { AnnouncementDeliveryWorker } = require('../src/modules/events/announcement-delivery.worker') as typeof import('../src/modules/events/announcement-delivery.worker');
const { EmailProviderError } = require('../src/lib/email-provider-budget') as typeof import('../src/lib/email-provider-budget');
function deferred() { let resolve!: (value?: any) => void; const promise = new Promise<any>(r => { resolve = r; }); return { promise, resolve }; }
class Queue {
    ready: any[] = [];
    rows = new Map<number, any[]>();
    paused: any[] = [];
    finished: any[] = [];
    begun = 0;
    claims = 0;
    add(id: number, count = 1) {
        const j = { id, announcement_id: id, institution_id: id, created_by: 1, attempts: 0, lock_token: `lock-${id}`, payload: { title: 'Title', description: 'Message', audience: 'students' } };
        this.ready.push(j);
        this.rows.set(id, Array.from({ length: count }, (_, i) => ({ user_id: id * 100 + i, notification_id: id * 100 + i, email: 'fixture@example.invalid', full_name: 'Fixture', email_status: 'pending', push_status: 'pending', eligible: true, users: { active: true, deleted_at: null, email_notifications_enabled: true } })));
        return j;
    }
    async claim() {
        this.claims++;
        const j = this.ready.shift();
        if (j)
            j.attempts++;
        return j ?? null;
    }
    async prepare(_j: any) { }
    async pending(j: any, limit = 50) { return this.rows.get(j.id)!.filter(r => r.email_status === 'pending' || r.push_status === 'pending').slice(0, limit); }
    async heartbeat(_j: any) { }
    async beginEmail(j: any, r: any) { this.begun++; return { send: true, status: 'pending', email: r.email, fullName: r.full_name, idempotencyKey: `stored-key-${j.id}-${r.user_id}` }; }
    async record(_j: any, r: any, email: string, push: string, _id: any, _error: any) { r.email_status = email; r.push_status = push; }
    async finish(j: any, error?: string | null) { this.finished.push({ id: j.id, error }); }
    async pause(j: any, failed = false, delay = 0) {
        this.paused.push({ id: j.id, failed, delay });
        if (!failed)
            j.attempts = 0;
        this.ready.push(j);
    }
}
const mail = { sendPreparedAnnouncement: async (_t: string, _m: string, prepare: () => Promise<any>) => { const target = await prepare(); return target.send ? { status: 'sent', id: 'fixture-id' } : { status: target.status }; } };
test('bounded slices yield to another institution instead of draining the first job', async () => {
    const queue = new Queue();
    queue.add(1, 3);
    queue.add(2, 1);
    const sent: number[] = [];
    const worker = new AnnouncementDeliveryWorker(queue, { sendPreparedAnnouncement: async (t, m, p) => { const attempt = await p(); sent.push(Number(attempt.idempotencyKey!.split('-')[2])); return { status: 'sent', id: 'fixture-id' }; } }, { sendStoredPush: async () => "sent" as const }, { concurrency: 1, recipientsPerSlice: 1 });
    await worker.runOnce();
    await worker.runOnce();
    await worker.stop();
    assert.deepEqual(sent, [1, 2]);
    assert.equal(queue.rows.get(1)!.filter(r => r.email_status === 'pending').length, 2);
    assert.equal(queue.paused[0].failed, false);
    assert.equal(queue.finished[0].id, 2);
});
test('overlapping wakes and stop do not duplicate an in-flight provider request; its checkpoint survives', async () => {
    const queue = new Queue();
    queue.add(1);
    const sending = deferred(), release = deferred();
    let requests = 0, pushes = 0, stopped = false;
    const worker = new AnnouncementDeliveryWorker(queue, { sendPreparedAnnouncement: async (_t, _m, p) => { await p(); requests++; sending.resolve(); await release.promise; return { status: 'sent', id: 'confirmed' }; } }, { sendStoredPush: async () => { pushes++; return "sent" as const; } }, { concurrency: 1 });
    const running = worker.runOnce();
    await sending.promise;
    await worker.runOnce();
    const stopping = worker.stop().then(() => { stopped = true; });
    await Promise.resolve();
    assert.equal(stopped, false);
    release.resolve();
    await Promise.all([running, stopping]);
    assert.equal(requests, 1);
    assert.equal(pushes, 1);
    assert.equal(queue.rows.get(1)![0].email_status, 'sent');
    const resumed = new AnnouncementDeliveryWorker(queue, mail, { sendStoredPush: async () => { pushes++; return "sent" as const; } }, { concurrency: 1 });
    await resumed.runOnce();
    await resumed.stop();
    assert.equal(pushes, 1);
    assert.equal(queue.finished.length, 1);
});
test('a lost provider response keeps the same key and does not replay a confirmed push', async () => {
    const queue = new Queue();
    queue.add(1);
    const keys: string[] = [];
    let pushes = 0;
    const worker = new AnnouncementDeliveryWorker(queue, { sendPreparedAnnouncement: async (_t, _m, p) => {
            const attempt = await p();
            keys.push(attempt.idempotencyKey!);
            if (keys.length === 1)
                throw new EmailProviderError('Unknown outcome', 'email_provider_timeout', true, 5000);
            return { status: 'sent', id: 'original-provider-id' };
        } }, { sendStoredPush: async () => { pushes++; return "sent" as const; } }, { concurrency: 1 });
    await worker.runOnce();
    assert.equal(queue.paused[0].failed, true);
    await worker.runOnce();
    await worker.stop();
    assert.equal(keys.length, 2);
    assert.equal(keys[0], keys[1]);
    assert.equal(pushes, 1);
    assert.equal(queue.rows.get(1)![0].email_status, 'sent');
});
test('rate backpressure yields without starting an email attempt or exhausting retries', async () => {
    const queue = new Queue();
    queue.add(1);
    const worker = new AnnouncementDeliveryWorker(queue, { sendPreparedAnnouncement: async () => { throw new EmailProviderError('Busy', 'email_rate_limited', true, 9000); } }, { sendStoredPush: async () => "sent" as const }, { concurrency: 1 });
    for (let i = 0; i < 4; i++)
        await worker.runOnce();
    await worker.stop();
    assert.equal(queue.begun, 0);
    assert.equal(queue.finished.length, 0);
    assert.ok(queue.paused.every(p => !p.failed && p.delay === 9000));
});
test('revoked recipients never reach providers and invalid idempotency payloads require review', async () => {
    const queue = new Queue();
    queue.add(1);
    queue.rows.get(1)![0].eligible = false;
    let sends = 0, pushes = 0;
    const skipped = new AnnouncementDeliveryWorker(queue, { sendPreparedAnnouncement: async () => { sends++; throw new Error('Should not send'); } }, { sendStoredPush: async () => { pushes++; return "sent" as const; } }, { concurrency: 1 });
    await skipped.runOnce();
    await skipped.stop();
    assert.equal(sends, 0);
    assert.equal(pushes, 0);
    queue.add(2);
    const review = new AnnouncementDeliveryWorker(queue, { sendPreparedAnnouncement: async (_t, _m, p) => { await p(); throw new EmailProviderError('Review', 'email_idempotency_conflict', false); } }, { sendStoredPush: async () => "sent" as const }, { concurrency: 1 });
    await review.runOnce();
    await review.stop();
    assert.equal(queue.rows.get(2)![0].email_status, 'needs_review');
});
test('pending device delivery yields without failing or blocking other recipient emails', async () => {
    const queue = new Queue();
    queue.add(1, 3);
    let emails = 0, ready = false;
    const worker = new AnnouncementDeliveryWorker(queue, { sendPreparedAnnouncement: async () => { emails++; return { status: 'sent', id: 'mail-id' }; } }, { sendStoredPush: async () => ready ? 'sent' : 'pending' }, { concurrency: 1, recipientsPerSlice: 3 });
    await worker.runOnce();
    assert.equal(emails, 3);
    assert.equal(queue.finished.length, 0);
    assert.equal(queue.paused[0].failed, false);
    assert.equal(queue.paused[0].delay, 2000);
    ready = true;
    await worker.runOnce();
    assert.equal(emails, 3);
    assert.equal(queue.finished.length, 1);
    await worker.stop();
});
