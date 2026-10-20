import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import type { AppContext } from '../src/types/app-context';
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
const { SyncRepository } = require('../src/modules/sync/sync.repository') as typeof import('../src/modules/sync/sync.repository');
const { SyncService } = require('../src/modules/sync/sync.service') as typeof import('../src/modules/sync/sync.service');
const ctx = { roles: new Set(['teacher']) } as AppContext;
function mark() { return { operationId: randomUUID(), uuid: randomUUID(), classId: 1, date: '2026-10-18', studentId: 2, statusId: 1, expectedVersion: 0, recordedAt: '2026-10-18T12:00:00.000Z', notes: null }; }
test('one sync request contains the complete bounded batch and validates keys and versions before SQL', async () => {
    const calls: any[] = [];
    const service = new SyncService(new SyncRepository({ rpc: async (name: string, args: any) => { calls.push({ name, args }); return { data: { sessions: [], records: [] }, error: null }; } }));
    const marks = [mark(), { ...mark(), studentId: 3 }];
    await service.batch(ctx, { marks });
    assert.deepEqual(calls[0], { name: 'sync_attendance_batch', args: { p_sessions: [], p_marks: marks } });
    for (const invalid of [{ ...mark(), expectedVersion: null }, { ...mark(), classId: true }, { ...mark(), classId: '9007199254740993' },
        { ...mark(), operationId: 'bad' }, { ...mark(), date: '2026-02-30' }]) {
        await assert.rejects(service.batch(ctx, { marks: [invalid] }), { status: 400 });
    }
    await assert.rejects(service.batch(ctx, { marks: Array.from({ length: 101 }, mark) }), { status: 400 });
    assert.equal(calls.length, 1);
});
test('incremental cursors preserve microseconds and bigint IDs and never advance from serverTime', async () => {
    const calls: any[] = [];
    const cursor = { updatedAt: '2026-10-19T12:00:00.123456+00:00', id: '9007199254740993' };
    const service = new SyncService(new SyncRepository({ rpc: async (name: string, args: any) => { calls.push({ name, args }); return { data: { items: [], hasMore: false, cursor }, error: null }; } }));
    const first = await service.pull(ctx, {});
    await service.pull(ctx, { cursor: first.changes.nextCursor });
    assert.deepEqual(calls[1].args, { p_after_at: cursor.updatedAt, p_after_id: cursor.id, p_limit: 100 });
    for (const query of [{ page: 2 }, { cursor: 'invalid' }, { since: {} }, { limit: 501 }])
        await assert.rejects(service.pull(ctx, query), { status: 400 });
    assert.equal(calls.length, 2);
});
test('sync failures preserve conflict and permission semantics without exposing database details', async () => {
    for (const [code, status] of [['42501', 403], ['23505', 409], ['22023', 400], ['XX000', 503]] as const) {
        const repo = new SyncRepository({ rpc: async () => ({ data: null, error: { code, message: 'private database schema' } }) });
        await assert.rejects(repo.batch([], []), (e: any) => e.status === status && !e.message.includes('private'));
    }
    const repo = new SyncRepository({ rpc: async () => ({ data: null, error: null }) });
    await assert.rejects(repo.batch([], []), { status: 503 });
});
