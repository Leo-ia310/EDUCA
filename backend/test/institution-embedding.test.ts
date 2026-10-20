import assert from "node:assert/strict";
import { mock, test } from "node:test";

process.env.NODE_ENV = "test";
process.env.SUPABASE_URL = "https://fixture.supabase.co";
process.env.SUPABASE_ANON_KEY = "fixture-public";
process.env.SUPABASE_SERVICE_ROLE_KEY = "fixture-service";
const { AuthFlowRepository } = require("../src/modules/auth/auth-flow.repository") as typeof import("../src/modules/auth/auth-flow.repository");
const { DeveloperRepository } = require("../src/modules/developer/developer.repository") as typeof import("../src/modules/developer/developer.repository");
const { PaymentsRepository } = require("../src/modules/payments/payments.repository") as typeof import("../src/modules/payments/payments.repository");

test("SDK reads keep the direct institution relationship when receipt junctions add alternate paths", async () => {
  const fetch = mock.method(globalThis, "fetch", async (input: string | URL | Request) => {
    const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
    assert.equal(url.hostname, "fixture.supabase.co");
    const table = url.pathname.split("/").at(-1);
    assert.ok(table === "users" || table === "charges");
    const fk = table === "users" ? "users_institution_id_fkey" : "charges_institution_id_fkey";
    // PostgREST also discovers many-to-many routes through private receipt
    // tables. An unqualified embed fails before authentication can finish.
    if (!url.searchParams.get("select")?.includes(`institutions!${fk}(`)) {
      return Response.json({ code: "PGRST201", message: "Multiple institution relationships" }, { status: 300 });
    }
    const row = table === "users"
      ? { id: 1, institutions: { id: 2, name: "School", code: "TEST" }, user_roles: [] }
      : { id: 3, institutions: { timezone: "America/Managua" } };
    return Response.json(table === "users" ? [row] : row, { headers: { "content-range": "0-0/1" } });
  });
  try {
    const user = await new AuthFlowRepository().findLoginUserByIdentifier("fixture");
    assert.deepEqual(user?.institutions, { id: 2, name: "School", code: "TEST" });
    const page = await new DeveloperRepository().listUsers({ page: 1, pageSize: 50, from: 0, to: 49 });
    assert.equal(page.pageInfo.total, 1);
    assert.deepEqual((page.items[0] as { institutions: unknown }).institutions, user?.institutions);
    const charge = await new PaymentsRepository().findCharge(2, 3);
    assert.deepEqual(charge.institutions, { timezone: "America/Managua" });
  } finally {
    fetch.mock.restore();
  }
});
