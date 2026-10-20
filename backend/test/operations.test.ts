import { paginationFromQuery } from "../src/lib/pagination";
import assert from "node:assert/strict";
import { test, mock } from "node:test";
import { once } from "node:events";
import express from "express";
import { requestLifetime, currentRequestSignal, requestRuntime } from "../src/lib/request-lifetime";
import { Readiness } from "../src/lib/readiness";
import { databaseError } from "../src/lib/database-error";
import { requestIdMiddleware } from "../src/middleware/request-id.middleware";
import { errorHandler } from "../src/middleware/error.middleware";
import { requiredId, requiredNumber, requiredDate, optionalBoolean } from "../src/validators/common.validators";
async function serve(app: express.Express, run: (url: string) => Promise<void>) {
    const server = app.listen(0, "127.0.0.1");
    await once(server, "listening");
    const address = server.address() as {
        port: number;
    };
    try {
        await run(`http://127.0.0.1:${address.port}`);
    }
    finally {
        server.closeAllConnections();
        await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }
}
test("database failures preserve HTTP semantics without disclosing SQL details", () => {
    const cases: [
        [
            string,
            number
        ],
        ...[
            string,
            number
        ][]
    ] = [["42501", 403], ["P0002", 404], ["23505", 409], ["23P01", 409], ["40P01", 409], ["23514", 400], ["22008", 400], ["57014", 503], ["42P01", 503], ["PGRST200", 503]];
    for (const [code, status] of cases) {
        const error = databaseError({ code, message: "secret SQL relation users email=private" });
        assert.equal(error.status, status);
        assert.ok(!error.message.includes("secret"));
    }
    assert.equal(databaseError({ code: "PGRST116", details: "The result contains 0 rows" }).status, 404);
    assert.equal(databaseError({ code: "PGRST116", details: "The result contains 2 rows" }).status, 503);
});
test('operational SQL errors log only a safe code and correlation ID',async()=>{
    const logs:unknown[]=[];
    const log=mock.method(console,'error',(value:unknown)=>{logs.push(value);});
    const app=express();app.use(requestIdMiddleware);
    app.get('/timeout',()=>{throw databaseError({code:'57014',message:'secret SQL email=private'});});
    app.use(errorHandler);
    try {await serve(app,async url=>{
        const r=await fetch(url+'/timeout');assert.equal(r.status,503);
        const body=await r.json() as any;assert.equal(body.error.code,'database_unavailable');
        assert.equal(logs.length,1);assert.deepEqual(logs[0],{event:'database_request_failed',requestId:body.error.requestId,status:503,databaseCode:'57014'});
        assert.ok(!JSON.stringify(body).includes('57014'));assert.ok(!JSON.stringify(logs).includes('secret SQL'));
    });}finally{log.mock.restore();}
});
test("IDs reject coercions/precision loss and dates reject normalized impossible days", () => {
    for (const value of [true, false, [], {}, " 1 ", "1e3", "0x10", 9007199254740992])
        assert.throws(() => requiredId(value, "ID"), { status: 400 });
    assert.equal(requiredId("123", "ID"), 123);
    for (const value of [[], {}, 'yes', '1']) {
        assert.throws(() => optionalBoolean(value), { status: 400 });
    }
    for (const value of [true, false, [], {}, 'yes']) {
        assert.throws(() => paginationFromQuery({ page: value }), { status: 400 });
    }
    assert.equal(paginationFromQuery({ page: '1' }).page, 1);
    assert.equal(optionalBoolean(false), false);
    assert.equal(optionalBoolean('false'), false);
    assert.throws(() => paginationFromQuery({ page: Number.MAX_SAFE_INTEGER, pageSize: 100 }), { status: 400 });
    for (const value of [null, true, [], "", " ", "0x10"])
        assert.throws(() => requiredNumber(value, "Valor"), { status: 400 });
    assert.equal(requiredNumber("12.50", "Valor"), 12.5);
    for (const value of ["2026-02-30", "2025-02-29T10:00:00Z", "2026-13-01", "2026-01-00"])
        assert.throws(() => requiredDate(value, "Fecha"), { status: 400 });
    assert.equal(requiredDate("2024-02-29", "Fecha").toISOString(), "2024-02-29T00:00:00.000Z");
});
test("readiness coalesces simultaneous probes and caches both success and failures briefly", async () => {
    let now = 0, calls = 0, resolve!: (value: boolean) => void;
    const readiness = new Readiness(async () => { calls++; return new Promise<boolean>(done => { resolve = done; }); }, () => now);
    const a = readiness.check(), b = readiness.check();
    assert.equal(calls, 1);
    resolve(true);
    assert.deepEqual(await Promise.all([a, b]), [true, true]);
    assert.equal(await readiness.check(), true);
    assert.equal(calls, 1);
    now = 2001;
    const c = readiness.check();
    resolve(false);
    assert.equal(await c, false);
    assert.equal(await readiness.check(), false);
    assert.equal(calls, 2);
});
test("malformed/oversized bodies and overload return controlled status and request IDs", async () => {
    const app = express();
    let release!: () => void;
    app.use(requestIdMiddleware);
    app.use(requestLifetime({ maxConcurrent: 1, timeoutMs: 1000 }));
    app.use(express.json({ limit: "32b" }));
    app.post("/body", (_req, res) => { res.json({ ok: true }); });
    app.get("/hold", (_req, res) => { void new Promise<void>(resolve => { release = resolve; }).then(() => res.json({ ok: true })); });
    app.use(errorHandler);
    await serve(app, async (url) => {
        const invalid = await fetch(url + "/body", { method: "POST", headers: { "content-type": "application/json", "x-request-id": "test-json" }, body: "{broken" });
        assert.equal(invalid.status, 400);
        assert.equal((await invalid.json() as any).error.requestId, "test-json");
        const large = await fetch(url + "/body", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text: "x".repeat(100) }) });
        assert.equal(large.status, 413);
        const first = fetch(url + "/hold");
        while (!release)
            await new Promise(resolve => setImmediate(resolve));
        const busy = await fetch(url + "/body", { method: "POST" });
        assert.equal(busy.status, 503);
        assert.equal(busy.headers.get("retry-after"), "2");
        release();
        assert.equal((await first).status, 200);
        assert.equal(requestRuntime().active, 0);
    });
});
test("request deadline aborts dependency context and releases admission without leaking a body", async () => {
    const app = express();
    let aborted = false;
    app.use(requestIdMiddleware);
    app.use(requestLifetime({ timeoutMs: 40 }));
    app.get("/slow", () => { currentRequestSignal()!.addEventListener("abort", () => { aborted = true; }, { once: true }); });
    app.use(errorHandler);
    await serve(app, async (url) => {
        const response = await fetch(url + "/slow");
        assert.equal(response.status, 504);
        assert.equal((await response.json() as any).error.code, "request_timeout");
        assert.equal(aborted, true);
        assert.equal(requestRuntime().active, 0);
    });
});
