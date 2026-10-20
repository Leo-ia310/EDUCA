import assert from "node:assert/strict";
import { test } from "node:test";
import { readAllPages } from "../src/lib/read-all";
test("complete grid reads continue past short server-capped pages and 1000 rows", async () => {
    const source = Array.from({ length: 1207 }, (_, id) => ({ id }));
    const offsets: number[] = [];
    const result = await readAllPages(async (from, to) => {
        offsets.push(from);
        return { data: source.slice(from, Math.min(to + 1, from + 100)), error: null };
    });
    assert.deepEqual(result, source);
    assert.equal(offsets[1], 100);
    assert.equal(offsets.at(-1), 1207);
});
test("a later page failure rejects rather than returning incomplete totals", async () => {
    await assert.rejects(readAllPages(async (from) => from === 0
        ? { data: [{ id: 1 }], error: null }
        : { data: null, error: { message: "Fixture page error" } }), { status: 503, code: "database_unavailable" });
});
test("empty domain results finish on the first request", async () => {
    let calls = 0;
    assert.deepEqual(await readAllPages(async () => { calls++; return { data: [], error: null }; }), []);
    assert.equal(calls, 1);
});
