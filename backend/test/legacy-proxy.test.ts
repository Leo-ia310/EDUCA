import assert from "node:assert/strict";
import { test } from "node:test";
import { createBusinessProxy } from "../../supabase/functions/business-api/proxy";
const target = "https://backend.fixture.invalid/api", origin = "https://app.fixture.invalid";
const request = (body = '{}', headers: Record<string, string> = {}) => new Request("https://project.supabase.co/functions/v1/business-api", { method: "POST", headers: { authorization: "Bearer fixture-user-jwt", origin, ...headers }, body });
test("legacy entry point fails closed without a Node target and rejects recursive/wrong origins", async () => {
    for (const value of [undefined, "https://project.supabase.co/api", "https://backend.fixture.invalid/functions/v1/business-api", "http://backend.fixture.invalid/api"]) {
        assert.equal((await createBusinessProxy({ target: value, allowedOrigins: [origin] })(request())).status, 503);
    }
    assert.equal((await createBusinessProxy({ target, allowedOrigins: [] })(request())).status, 403);
});
test("proxy forwards original JWT and operation key, preserving denial, retry and correlation", async () => {
    let calls = 0;
    const proxy = createBusinessProxy({ target, allowedOrigins: [origin], fetchImpl: async (input, init) => {
            calls++;
            assert.equal(String(input), target + "/business-api");
            const headers = new Headers(init?.headers);
            assert.equal(headers.get("authorization"), "Bearer fixture-user-jwt");
            assert.equal(headers.get("apikey"), null);
            assert.equal(headers.get("x-forwarded-for"), null);
            assert.match(new TextDecoder().decode(init?.body as Uint8Array), /stable-operation/);
            return new Response(JSON.stringify({ ok: false, error: { code: "forbidden" } }), { status: 403, headers: { "content-type": "application/json", "retry-after": "5", "x-request-id": "fixture-id" } });
        } });
    const response = await proxy(request(JSON.stringify({ action: "chat.sendMessage", payload: { requestId: "stable-operation" } }), { "x-forwarded-for": "spoofed", "x-request-id": "fixture-id" }));
    assert.equal(calls, 1);
    assert.equal(response.status, 403);
    assert.equal(response.headers.get("retry-after"), "5");
    assert.equal(response.headers.get("access-control-allow-origin"), origin);
    assert.equal((await response.json() as any).error.code, "forbidden");
});
test("proxy bounds bodies and timeouts before exposing transport errors", async () => {
    let calls = 0;
    const proxy = createBusinessProxy({ target, allowedOrigins: [origin], timeoutMs: 20, fetchImpl: async (_input, init) => {
            calls++;
            return new Promise((_resolve, reject) => init?.signal?.addEventListener("abort", () => reject(Error("private host credentials")), { once: true }));
        } });
    assert.equal((await proxy(request("x".repeat(524289)))).status, 413);
    assert.equal(calls, 0);
    // Retain one real timer while AbortSignal.timeout uses an unreferenced timer.
    const keepAlive = setTimeout(() => { }, 1000);
    try {
        const response = await proxy(request());
        assert.equal(response.status, 504);
        assert.ok(!(await response.text()).includes("private"));
    }
    finally {
        clearTimeout(keepAlive);
    }
});
