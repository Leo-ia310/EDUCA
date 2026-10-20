import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import { test } from "node:test";
import { gracefulShutdown } from "../src/lib/graceful-shutdown";
import { requestRuntime } from "../src/lib/request-lifetime";
test("shutdown closes admission and waits for provider checkpoints before completing", async () => {
    const server = createServer((_req, res) => res.end("ok"));
    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    let finish!: () => void, done = false;
    const stopped = gracefulShutdown(server, [() => new Promise<void>(resolve => { finish = resolve; })], 1000).then(clean => { done = true; return clean; });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(requestRuntime().draining, true);
    assert.equal(done, false);
    finish();
    assert.equal(await stopped, true);
});
test("shutdown has a bounded deadline when a provider cannot drain", async () => {
    const server = createServer();
    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    assert.equal(await gracefulShutdown(server, [() => new Promise<void>(() => { })], 20), false);
});
