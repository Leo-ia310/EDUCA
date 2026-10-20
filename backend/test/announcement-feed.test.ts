import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AppContext } from '../src/types/app-context';
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
const { EventsRepository } = require('../src/modules/events/events.repository') as typeof import('../src/modules/events/events.repository');
const { EventsService } = require('../src/modules/events/events.service') as typeof import('../src/modules/events/events.service');
const ctx = {} as AppContext;
test('announcement pages preserve bigint cursors and reject malformed IDs before querying', async () => {
    const calls: any[] = [];
    const repo = new EventsRepository({ rpc: async (name: string, args: any) => {
            calls.push({ name, args });
            return { data: name === 'announcement_feed' ? { announcements: [], hasMore: false, nextBeforeId: null } : { deliveries: [] }, error: null };
        } });
    const service = new EventsService(repo);
    await service.listAnnouncements(ctx, { beforeId: '9007199254740993', limit: '100' });
    assert.deepEqual(calls[0], { name: 'announcement_feed', args: { p_before_id: '9007199254740993', p_limit: 100 } });
    await service.deliveryStates(ctx, { ids: '1,9007199254740993,1' });
    assert.deepEqual(calls[1], { name: 'announcement_delivery_state', args: { p_ids: ['1', '9007199254740993'] } });
    for (const beforeId of ['-1', '0', '1.5', '9223372036854775808', {}, ['1']]) {
        await assert.rejects(service.listAnnouncements(ctx, { beforeId }), { status: 400 });
    }
    for (const ids of ['', '1,', '1,NaN', Array(101).fill('1').join(',')]) {
        await assert.rejects(service.deliveryStates(ctx, { ids }), { status: 400 });
    }
    assert.equal(calls.length, 2);
});
test('announcement query errors are sanitized and null data cannot masquerade as an empty feed', async () => {
    for (const [code, status] of [['42501', 403], ['22023', 400], ['XX000', 503]] as const) {
        const repo = new EventsRepository({ rpc: async () => ({ data: null, error: { code, message: 'secret schema' } }) });
        await assert.rejects(repo.listPublishedAnnouncements(null, 50), (e: any) => e.status === status && !e.message.includes('secret'));
    }
    const repo = new EventsRepository({ rpc: async () => ({ data: null, error: null }) });
    await assert.rejects(repo.deliveryStates(['1']), { status: 503 });
});
