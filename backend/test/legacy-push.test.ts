import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createPushQueueHandler } from '../../supabase/functions/send-push/handler';
const req = (id: unknown, secret = 'fixture-internal') => new Request('https://project.supabase.co/functions/v1/send-push', { method: 'POST', headers: { authorization: 'Bearer ' + secret, 'content-type': 'application/json' }, body: JSON.stringify({ notificationId: id }) });
test('legacy push is authenticated and enqueues bigint IDs without calling a provider', async () => {
    const ids: string[] = [];
    const handler = createPushQueueHandler({ secret: 'fixture-internal', async enqueue(id, signal) { assert.equal(signal.aborted, false); ids.push(id); return { status: 'pending' }; } });
    assert.equal((await handler(req('123', 'wrong'))).status, 401);
    assert.equal(ids.length, 0);
    assert.equal((await handler(req(9007199254740992))).status, 400);
    assert.equal((await handler(req('9223372036854775808'))).status, 400);
    assert.equal((await handler(req('9007199254740993'))).status, 202);
    assert.deepEqual(ids, ['9007199254740993']);
    const failed = createPushQueueHandler({ secret: 'fixture-internal', async enqueue() { throw Error('private host token'); } });
    const response = await failed(req('1'));
    assert.equal(response.status, 503);
    assert.ok(!(await response.text()).includes('private'));
});
