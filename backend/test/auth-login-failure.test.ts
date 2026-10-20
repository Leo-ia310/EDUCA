import assert from "node:assert/strict";
import { test } from "node:test";
process.env.NODE_ENV = "test";
process.env.SUPABASE_URL = "https://fixture.supabase.co";
process.env.SUPABASE_ANON_KEY = "fixture-public";
const { AuthFlowService } = require("../src/modules/auth/auth-flow.service") as typeof import("../src/modules/auth/auth-flow.service");
test("Auth outages and rate limits do not increment password failure counters", async () => {
    let failed = 0;
    const repository = { async findLoginUserByIdentifier() { return { id: 1, email: "fixture@school.invalid", active: true, institutions: { id: 1, active: true } }; }, async incrementFailedAttempts() { failed++; } };
    for (const status of [0, 429, 503, 504]) {
        const service = new AuthFlowService(repository as any, {} as any, { async signInWithPassword() { return { data: { session: null, user: null }, error: { status } }; } } as any);
        await assert.rejects(service.login({ username: "fixture", password: "wrong" }), { status: status === 429 ? 429 : 503 });
    }
    assert.equal(failed, 0);
    const service = new AuthFlowService(repository as any, {} as any, { async signInWithPassword() { return { data: { session: null, user: null }, error: { status: 400 } }; } } as any);
    await assert.rejects(service.login({ username: "fixture", password: "wrong" }), { status: 401 });
    assert.equal(failed, 1);
});
