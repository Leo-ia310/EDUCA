import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parsePushSubscription } from '../src/lib/push-subscription';
const key = Buffer.concat([Buffer.from([4]), Buffer.alloc(64)]).toString('base64url'), auth = Buffer.alloc(16).toString('base64url');
const subscription = (endpoint: string) => ({ endpoint, keys: { p256dh: key, auth } });
test('push allows provider HTTPS endpoints and rejects injected/internal destinations and invalid keys', () => {
    for (const endpoint of ['https://fcm.googleapis.com/wp/fixture', 'https://updates.push.services.mozilla.com/wpush/fixture', 'https://web.push.apple.com/fixture', 'https://wns2.fixture.notify.windows.com/w/fixture'])
        assert.equal(parsePushSubscription(subscription(endpoint)).endpoint, endpoint);
    for (const endpoint of ['http://fcm.googleapis.com/', 'https://127.0.0.1/', 'https://169.254.169.254/', 'https://fcm.googleapis.com.attacker.invalid/', 'https://fcm.googleapis.com@attacker.invalid/', 'https://fcm.googleapis.com:444/', 'https://private.fixture.invalid/'])
        assert.throws(() => parsePushSubscription(subscription(endpoint)));
    assert.throws(() => parsePushSubscription({ ...subscription('https://fcm.googleapis.com/wp/fixture'), keys: { p256dh: key, auth: 'bad' } }));
    assert.throws(() => parsePushSubscription('not json'));
});
