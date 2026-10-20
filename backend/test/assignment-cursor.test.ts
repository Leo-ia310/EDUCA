import assert from "node:assert/strict";
import { test } from "node:test";
import { decodeAssignmentCursor, encodeAssignmentCursor } from "../src/modules/assignments/assignment-cursor";
test("cursor round trip preserves PostgreSQL microseconds and bigint precision", () => {
    const cursor = { id: "9223372036854775807", dueAt: "2026-10-18T20:00:00.123456+00:00" };
    assert.deepEqual(decodeAssignmentCursor(encodeAssignmentCursor(cursor)), cursor);
    assert.deepEqual(decodeAssignmentCursor(encodeAssignmentCursor({ id: "1", dueAt: null })), { id: "1", dueAt: null });
});
test("malformed, oversized and out-of-range cursors fail validation", () => {
    for (const value of ["not-json", "!", "x".repeat(513), encodeAssignmentCursor({ id: "9223372036854775808", dueAt: null }),
        encodeAssignmentCursor({ id: "1", dueAt: "2026-10-18' OR true--" })]) {
        assert.throws(() => decodeAssignmentCursor(value), { status: 400, code: "validation_error" });
    }
    assert.equal(decodeAssignmentCursor(undefined), null);
});
