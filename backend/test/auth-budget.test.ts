import assert from 'node:assert/strict';
import { beforeEach, afterEach, mock, test } from 'node:test';
import type { Response } from 'express';
import type { AppRequest } from '../src/types/app-context';
// Fixture-only config: importing API modules must never load the developer .env.
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fixture-service';
process.env.RATE_LIMIT_WINDOW_MS = '900000';
process.env.USER_RATE_LIMIT_MAX = '1200';
const { authMiddleware } = require('../src/middleware/auth.middleware') as typeof import('../src/middleware/auth.middleware');
const { authRepository } = require('../src/modules/auth/auth.repository') as typeof import('../src/modules/auth/auth.repository');
const { portalAccessService } = require('../src/modules/portal-access/portal-access.service') as typeof import('../src/modules/portal-access/portal-access.service');
const { HttpError } = require('../src/lib/errors') as typeof import('../src/lib/errors');
const session = '00000000-0000-4000-8000-000000000001';
const token = `fixture.${Buffer.from(JSON.stringify({ session_id: session })).toString('base64url')}.fixture`;
function context() {
    return { allowed: true, authUserId: 'auth-fixture', sessionId: session, userId: 7, institutionId: 10, personId: 70,
        fullName: 'Fixture', roles: ['parent'], adminPermissions: null, parentId: 42, studentId: null, teacherId: null,
        portalPermissions: { 'payments.view': true, 'attendance.view': false }, limit: 1200, remaining: 1199, resetsAt: '2026-10-18T12:00:00Z' };
}
async function request(path = '/api/payments/summary') {
    const req = { header: () => `Bearer ${token}`, originalUrl: path, method: 'GET', body: {} } as unknown as AppRequest;
    const headers = new Map<string, string>();
    const res = { setHeader: (key: string, value: string) => headers.set(key, value) } as unknown as Response;
    let error: unknown;
    await authMiddleware(req, res, (value?: unknown) => { error = value; });
    return { req, error, headers };
}
beforeEach(() => {
    mock.method(globalThis, 'fetch', () => { throw new Error('Unexpected external request in unit test'); });
});
afterEach(() => mock.restoreAll());
test('protected request uses one Auth verification and one context/quota RPC; cached portal grants are request-local', async () => {
    const auth = mock.method(authRepository, 'getAuthUser', async (value: string) => {
        assert.equal(value, token);
        return { data: { user: { id: 'auth-fixture' } }, error: null } as any;
    });
    const rpc = mock.method(authRepository, 'requestContext', async (uid: string, sid: string, window: number, limit: number) => {
        assert.equal(uid, 'auth-fixture');
        assert.equal(sid, session);
        assert.equal(window, 900000);
        assert.equal(limit, 1200);
        return context();
    });
    const first = await request();
    assert.equal(first.error, undefined);
    assert.equal(first.req.appContext?.parentId, 42);
    await portalAccessService.require(first.req.appContext!, 'payments.view');
    assert.equal(auth.mock.callCount(), 1);
    assert.equal(rpc.mock.callCount(), 1);
    assert.equal(first.headers.get('x-user-ratelimit-remaining'), '1199');
    rpc.mock.mockImplementation(async () => ({ ...context(), portalPermissions: { 'payments.view': false } }));
    const second = await request();
    assert.ok(second.error instanceof HttpError);
    assert.equal(second.error.status, 403);
    assert.equal(auth.mock.callCount(), 2);
    assert.equal(rpc.mock.callCount(), 2);
    assert.equal(first.req.appContext?.portalPermissions?.['payments.view'], true);
});
test('invalid bearer never reaches privileged context, and Auth outages are not credential failures', async () => {
    const auth = mock.method(authRepository, 'getAuthUser', async () => ({ data: { user: null }, error: { status: 401, name: 'AuthApiError' } } as any));
    const rpc = mock.method(authRepository, 'requestContext', async () => context());
    const invalid = await request();
    assert.ok(invalid.error instanceof HttpError);
    assert.equal(invalid.error.status, 401);
    assert.equal(rpc.mock.callCount(), 0);
    auth.mock.mockImplementation(async () => ({ data: { user: null }, error: { status: 503, name: 'AuthRetryableFetchError' } } as any));
    const outage = await request();
    assert.ok(outage.error instanceof HttpError);
    assert.equal(outage.error.status, 503);
    assert.equal(rpc.mock.callCount(), 0);
});
test('shared quota denial carries Retry-After and does not authorize a handler', async () => {
    mock.method(authRepository, 'getAuthUser', async () => ({ data: { user: { id: 'auth-fixture' } }, error: null } as any));
    mock.method(authRepository, 'requestContext', async () => ({ allowed: false, limit: 1200, remaining: 0, resetsAt: '2026-10-18T12:00:00Z', retryAfterSeconds: 33 }));
    const result = await request();
    assert.ok(result.error instanceof HttpError);
    assert.equal(result.error.status, 429);
    assert.equal(result.headers.get('retry-after'), '33');
    assert.equal(result.req.appContext, undefined);
});
