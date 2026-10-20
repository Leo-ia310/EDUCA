import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
process.env.RESEND_API_KEY = 're_fixture';
process.env.RESEND_FROM_EMAIL = 'Nivra <fixture@example.invalid>';
const { EmailProviderBudget, EmailProviderError } = require('../src/lib/email-provider-budget') as typeof import('../src/lib/email-provider-budget');
const { EmailService } = require('../src/modules/auth/email.service') as typeof import('../src/modules/auth/email.service');
const originalFetch = globalThis.fetch;
afterEach(() => { globalThis.fetch = originalFetch; });
const payload = { to: 'fixture@example.invalid', subject: 'Fixture', html: '<p>Fixture</p>', idempotencyKey: 'fixture-key' };
test('provider backpressure bounds waits and never falls back to an unshared local quota', async () => {
    const calls: any[] = [], slept: number[] = [];
    const budget = new EmailProviderBudget({ rpc: async (name: string, args: any) => { calls.push({ name, args }); return { data: { allowed: false, waitMs: 9000 }, error: null }; } }, async (ms) => { slept.push(ms); });
    await assert.rejects(budget.acquire(), (e: any) => e.status === 503 && e.retryable && e.retryAfterMs === 9000);
    assert.equal(calls[0].name, 'reserve_provider_request');
    assert.equal(calls[0].args.p_max_wait_ms, 5000);
    assert.deepEqual(slept, []);
    const unavailable = new EmailProviderBudget({ rpc: async () => ({ data: null, error: { message: 'private schema details' } }) });
    await assert.rejects(unavailable.acquire(), (e: any) => e.code === 'email_budget_unavailable' && !e.message.includes('private'));
});
test('a shared slot is awaited before the fenced email checkpoint and provider dispatch', async () => {
    const order: string[] = [];
    const budget = new EmailProviderBudget({ rpc: async () => ({ data: { allowed: true, waitMs: 250 }, error: null }) }, async (ms) => { assert.equal(ms, 250); order.push('slot'); });
    globalThis.fetch = async (_url, options) => {
        order.push('provider');
        const body = JSON.parse(String(options?.body)), headers = options?.headers as Record<string, string>;
        assert.equal(headers['Idempotency-Key'], 'checkpoint-key');
        assert.equal(headers['user-agent'], 'Nivra/1.0');
        assert.equal(body.to[0], payload.to);
        assert.ok(body.html.includes('&lt;Fixture&gt;'));
        return new Response(JSON.stringify({ id: 'provider-id' }), { status: 200 });
    };
    const result = await new EmailService(budget).sendPreparedAnnouncement('Title', 'Message', async () => {
        order.push('checkpoint');
        return { send: true, status: 'pending', email: payload.to, fullName: '<Fixture>', idempotencyKey: 'checkpoint-key' };
    });
    assert.deepEqual(order, ['slot', 'checkpoint', 'provider']);
    assert.deepEqual(result, { status: 'sent', id: 'provider-id' });
});
test('budget rejection or a cancelled checkpoint cannot send or start an email attempt', async () => {
    let checkpoints = 0, requests = 0;
    globalThis.fetch = async () => { requests++; throw new Error('Network must not run'); };
    const unavailable = new EmailService({ acquire: async () => { throw new EmailProviderError('Busy', 'email_rate_limited', true, 9000); }, defer: async () => { } });
    await assert.rejects(unavailable.sendPreparedAnnouncement('Title', 'Message', async () => { checkpoints++; return { send: true, status: 'pending' }; }));
    assert.equal(checkpoints, 0);
    assert.equal(requests, 0);
    const allowed = new EmailService({ acquire: async () => { }, defer: async () => { } });
    assert.deepEqual(await allowed.sendPreparedAnnouncement('Title', 'Message', async () => ({ send: false, status: 'pending' })), { status: 'pending' });
    assert.equal(requests, 0);
    assert.deepEqual(await allowed.sendPreparedAnnouncement('Title', 'Message', async () => ({ send: true, status: 'pending', email: payload.to, fullName: 'Fixture', validUntil: new Date(Date.now() - 1).toISOString() })), { status: 'needs_review' });
    assert.equal(requests, 0);
});
test('provider Retry-After is shared, quota exhaustion is distinct and private errors are sanitized', async () => {
    const delays: number[] = [], service = new EmailService({ acquire: async () => { }, defer: async (ms) => { delays.push(ms); } });
    globalThis.fetch = async () => new Response(JSON.stringify({ name: 'rate_limit_exceeded', message: 'private recipient and provider data' }), { status: 429, headers: { 'retry-after': '2' } });
    await assert.rejects(service.send(payload), (e: any) => e.code === 'email_rate_limited' && e.retryable && !e.message.includes('private'));
    assert.deepEqual(delays, [2000]);
    globalThis.fetch = async () => new Response(JSON.stringify({ name: 'daily_quota_exceeded', message: 'private quota details' }), { status: 429 });
    await assert.rejects(service.send(payload), (e: any) => e.code === 'email_quota_exceeded' && !e.retryable);
});
test('lost or invalid provider confirmations remain retryable with the original key', async () => {
    const service = new EmailService({ acquire: async () => { }, defer: async () => { } });
    globalThis.fetch = async () => { throw new Error('private transport failure'); };
    await assert.rejects(service.send(payload), (e: any) => e.code === 'email_provider_timeout' && e.retryable && !e.message.includes('private'));
    globalThis.fetch = async () => new Response('{}', { status: 200 });
    await assert.rejects(service.send(payload), (e: any) => e.code === 'email_provider_response_invalid' && e.retryable);
});
