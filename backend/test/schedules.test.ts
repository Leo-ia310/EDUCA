import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { AppContext } from '../src/types/app-context';
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
const { SchedulesRepository } = require('../src/modules/schedules/schedules.repository') as typeof import('../src/modules/schedules/schedules.repository');
const { SchedulesService } = require('../src/modules/schedules/schedules.service') as typeof import('../src/modules/schedules/schedules.service');
const ctx = { institutionId: 10, roles: new Set(['admin']) } as unknown as AppContext;
test('schedule reads send validated filters to one SQL RPC and patches avoid stale pre-reads', async () => {
    const calls: {
        name: string;
        args: any;
    }[] = [];
    const repository = new SchedulesRepository({ rpc: async (name: string, args: any) => { calls.push({ name, args }); return { data: { schedules: [], pageInfo: {} }, error: null }; } });
    const service = new SchedulesService(repository);
    await service.list(ctx, { groupId: '1105', weekdayId: '7', page: '12', pageSize: '100', shift: 'morning' });
    assert.deepEqual(calls[0], { name: 'schedule_list', args: { p_institution_id: 10, p_filters: { groupId: 1105, teacherId: null, classId: null, weekdayId: 7, shift: 'morning', page: 12, pageSize: 100 }, p_mine: false, p_student_id: null } });
    await service.update(ctx, '5', { room: null, weekday_id: 3 });
    assert.deepEqual(calls[1], { name: 'schedule_write', args: { p_institution_id: 10, p_action: 'update', p_payload: { room: null, weekdayId: 3 }, p_id: 5 } });
    await assert.rejects(service.create(ctx, { classId: 2, weekdayIds: [1], startTime: '08:00:30', endTime: '09:00' }), { status: 400 });
    await assert.rejects(service.list(ctx, { weekdayId: 8 }), { status: 400 });
    await assert.rejects(service.list(ctx,{weekdayId:true}),{status:400});
    assert.equal(calls.length, 2);
});
test('schedule SQL errors retain conflict semantics without exposing database internals', async () => {
    for (const [code, status] of [['23P01', 409], ['42501', 403], ['P0002', 404], ['22023', 400], ['XX000', 503]] as const) {
        const repository = new SchedulesRepository({ rpc: async () => ({ data: null, error: { code, message: 'private SQL internals' } }) });
        await assert.rejects(repository.write(10, 'create', {}), (error: any) => error.status === status && !error.message.includes('private SQL'));
    }
});
