import assert from "node:assert/strict";
import { test } from "node:test";
import { effectiveChargeStatus } from "../src/modules/payments/payment-status";
test("a charge due today is open through the school's calendar day", () => {
    const charge = { status: "partial", due_at: "2026-09-30" };
    assert.equal(effectiveChargeStatus(charge, new Date("2026-10-01T05:59:59Z")), "partial");
    assert.equal(effectiveChargeStatus(charge, new Date("2026-10-01T06:00:00Z")), "overdue");
    assert.equal(effectiveChargeStatus({ ...charge, institutions: { timezone: "Pacific/Kiritimati" } }, new Date("2026-10-01T01:00:00Z")), "overdue");
});
test("closed charges and undated charges keep their state", () => {
    for (const status of ["paid", "cancelled"])
        assert.equal(effectiveChargeStatus({ status, due_at: "2000-01-01" }), status);
    assert.equal(effectiveChargeStatus({ status: "pending" }), "pending");
});
