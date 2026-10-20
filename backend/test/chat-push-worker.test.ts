import assert from "node:assert/strict";
import { test } from "node:test";
process.env.NODE_ENV = "test";
process.env.SUPABASE_URL = "https://fixture.supabase.co";
process.env.SUPABASE_ANON_KEY = "fixture-public";
const { PushDeliveryWorker } = require("../src/modules/notifications/push-delivery.worker") as typeof import("../src/modules/notifications/push-delivery.worker");
const job = (id: string) => ({ id, token: id, notificationId: id, deviceId: id, subscription: "{}", title: "Fixture", body: "Text", deepLink: "/chat/1", tag: "chat-1" });
test("push admission is single-flight, bounded to two sends and shutdown awaits checkpoints", async () => {
    const jobs = [job("1"), job("2"), job("3")], gates: Array<() => void> = [], finished: string[] = [];
    let active = 0, max = 0;
    const worker = new PushDeliveryWorker({ async claim() { return jobs.shift() ?? null; }, async finish(j) { finished.push(j.id); return true; } }, async () => {
        active++;
        max = Math.max(max, active);
        await new Promise<void>(resolve => gates.push(resolve));
        active--;
    });
    const pending = worker.runOnce();
    await new Promise(resolve => setImmediate(resolve));
    await worker.runOnce();
    assert.equal(gates.length, 2);
    let stopped = false;
    const stop = worker.stop().then(() => { stopped = true; });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(stopped, false);
    gates.forEach(resolve => resolve());
    await Promise.all([pending, stop]);
    assert.equal(max, 2);
    assert.deepEqual(finished.sort(), ["1", "2"]);
    await worker.runOnce();
    assert.equal(jobs.length, 1);
});
test("provider retry-after, permanent errors and expired subscriptions have distinct checkpoints", async () => {
    const failures = [{ statusCode: 429, headers: { "retry-after": "120" } }, { statusCode: 410 }, { statusCode: 400 }, Error("network")];
    const observed: Array<[
        string,
        number
    ]> = [];
    for (const failure of failures) {
        let pending = true;
        const worker = new PushDeliveryWorker({ async claim() {
                if (!pending)
                    return null;
                pending = false;
                return job("1");
            }, async finish(_j, outcome, retry) { observed.push([outcome, retry]); return true; } }, async () => { throw failure; });
        await worker.runOnce();
        await worker.stop();
    }
    assert.deepEqual(observed, [["retry", 120], ["gone", 0], ["failed", 0], ["retry", 0]]);
});
test('fast completions cannot grow one slice or retain unbounded completed promises', async () => {
    const jobs = Array.from({ length: 1000 }, (_, i) => job(String(i)));
    let finished = 0;
    const worker = new PushDeliveryWorker({ async claim() { return jobs.shift() ?? null; }, async finish() { finished++; return true; } }, async () => { });
    await worker.runOnce();
    await worker.stop();
    assert.equal(finished, 2);
    assert.equal(jobs.length, 998);
});
