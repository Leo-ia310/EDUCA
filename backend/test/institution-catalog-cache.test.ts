import assert from "node:assert/strict";
import { test } from "node:test";
import { InstitutionCatalogCache } from "../src/lib/institution-catalog-cache";
import type { AppContext } from "../src/types/app-context";

process.env.NODE_ENV = "test";
process.env.SUPABASE_URL = "https://fixture.supabase.co";
process.env.SUPABASE_ANON_KEY = "fixture-public";

function fixture() {
  let now = 0;
  const values = new Map<string, { value: string; expires: number }>();
  const commands: Array<Array<string | number>> = [];
  const fetcher: typeof fetch = async (_url, options) => {
    const args = JSON.parse(String(options?.body)) as Array<string | number>;
    commands.push(args);
    const [cmd, key, value, , ttl] = args;
    let result: string | null = "OK";
    if (cmd === "SET") values.set(String(key), { value: String(value), expires: now + Number(ttl) * 1000 });
    else {
      const entry = values.get(String(key));
      result = entry && entry.expires > now ? entry.value : null;
    }
    return new Response(JSON.stringify({ result }));
  };
  const makeCache = (namespace?: string) => new InstitutionCatalogCache({ url: "https://fixture.upstash.io", token: "fixture", namespace, fetch: fetcher, now: () => now });
  return { cache: makeCache(), makeCache,
    advance: (ms: number) => { now += ms; }, commands };
}
const result = (id: number) => ({ scale: { id, name: `Scale ${id}` }, status: "configured" });

test("20 repeated institutional reads reduce catalog DB queries from 40 to 2, expire and isolate tenants", async () => {
  const { cache, advance } = fixture();
  let queries = 0;
  const load = async () => { queries += 2; return result(7); };
  for (let i = 0; i < 20; i++) assert.deepEqual(await cache.read(7, load), result(7));
  assert.equal(queries, 2);
  assert.equal(cache.metrics.hits, 19);
  assert.deepEqual(await cache.read(8, async () => result(8)), result(8));
  advance(30_001);
  await cache.read(7, load);
  assert.equal(queries, 4);
});

const statuses = () => [
  { id: 1, name: "Present", code: "P", counts_as_absent: false, color: null },
  { id: 2, name: "Absent", code: "A", counts_as_absent: true, color: null },
];

test("20 attendance catalog reads use one DB query and two Redis commands; another replica shares it", async () => {
  const { cache, makeCache, commands, advance } = fixture();
  let queries = 0;
  const load = async () => { queries++; return statuses(); };
  const reads = await Promise.all(Array.from({ length: 20 }, () => cache.readAttendanceStatuses(7, load)));
  assert.equal(queries, 1);
  assert.equal(commands.length, 2);
  reads[0][0].name = "Changed by caller";
  assert.equal((await cache.readAttendanceStatuses(7, load))[0].name, "Present");
  await makeCache().readAttendanceStatuses(7, load);
  assert.equal(queries, 1);
  assert.equal(commands.length, 3);
  advance(10_001);
  await cache.readAttendanceStatuses(7, load);
  assert.equal(queries, 1);
  advance(60_001);
  await cache.readAttendanceStatuses(7, load);
  assert.equal(queries, 2);
});

test("attendance catalogs isolate projects and institutions and bound process memory", async () => {
  const { cache, makeCache } = fixture();
  let loads = 0;
  const load = async () => { loads++; return statuses(); };
  await cache.readAttendanceStatuses(7, load);
  await cache.readAttendanceStatuses(8, load);
  await makeCache("other-project").readAttendanceStatuses(7, load);
  assert.equal(loads, 3);
  for (let id = 9; id <= 140; id++) await cache.readAttendanceStatuses(id, load);
  assert.equal(cache.snapshot().localEntries, 128);
  assert.equal(JSON.stringify(cache.snapshot()).includes("fixture"), false);
});

test("attendance errors cannot populate either L1 or Redis", async () => {
  const { cache, commands } = fixture();
  await assert.rejects(cache.readAttendanceStatuses(7, async () => { throw new Error("DB failed"); }));
  assert.equal(cache.snapshot().localEntries, 0);
  assert.equal(commands.some(args => args[0] === "SET"), false);
  assert.deepEqual(await cache.readAttendanceStatuses(7, async () => statuses()), statuses());
});

test("attendance service caches only statuses and still checks grants and reloads marks on every request", async () => {
  const { AttendanceService } = await import("../src/modules/attendance/attendance.service");
  const { cache } = fixture();
  let statusQueries = 0, markQueries = 0, allowed = true;
  const repository = {
    statuses: async () => { statusQueries++; return statuses(); },
    groupNames: async () => [{ id: 1, name: "Group" }],
    sessionsInRange: async () => [{ id: 10, group_id: 1 }],
    marksOfSessions: async () => { markQueries++; return [{ class_session_id: 10, attendance_status_id: markQueries === 1 ? 1 : 2 }]; },
  };
  const permissions = { isAdmin: () => allowed, requireAdminPermission: () => {} };
  const service = new AttendanceService(repository as any, permissions as any, cache);
  const ctx = { institutionId: 7 } as AppContext;
  const query = { from: "2026-10-01", to: "2026-10-20" };
  assert.equal((await service.summary(ctx, query)).total.absent, 0);
  assert.equal((await service.summary(ctx, query)).total.absent, 1);
  assert.equal(statusQueries, 1);
  assert.equal(markQueries, 2);
  allowed = false;
  await assert.rejects(service.summary(ctx, query), { status: 403 });
  assert.equal(markQueries, 2);
});

test("in-flight reads join and a mutation makes old loads unreachable", async () => {
  const { cache } = fixture();
  let resolve!: (value: ReturnType<typeof result>) => void;
  let started!: () => void;
  const loading = new Promise<void>(r => { started = r; });
  const load = () => { started(); return new Promise<ReturnType<typeof result>>(r => { resolve = r; }); };
  const first = cache.read(7, load);
  await loading;
  const joined = cache.read(7, load);
  // Let the second read resolve its revision/cache lookup before invalidation.
  await new Promise(r => setImmediate(r));
  await cache.invalidate(7);
  assert.deepEqual(await cache.read(7, async () => result(2)), result(2));
  resolve(result(1));
  assert.deepEqual(await first, result(1));
  assert.deepEqual(await joined, result(1));
  assert.deepEqual(await cache.read(7, async () => result(3)), result(2));
  assert.equal(cache.metrics.joins, 1);
});

test("no credentials makes no Redis requests; errors are not cached", async () => {
  const cache = new InstitutionCatalogCache({ fetch: async () => { throw new Error("Unexpected network"); } });
  await assert.rejects(cache.read(7, async () => { throw new Error("DB failed"); }));
  assert.deepEqual(await cache.read(7, async () => result(1)), result(1));
  await assert.rejects(cache.read(0, async () => result(1)));
});

test("Redis failure falls back to DB and opens a 30s circuit", async () => {
  let requests = 0, now = 0;
  const cache = new InstitutionCatalogCache({ url: "https://fixture.upstash.io", token: "fixture", now: () => now,
    fetch: async () => { requests++; throw new Error("Redis unavailable"); } });
  assert.deepEqual(await cache.read(7, async () => result(1)), result(1));
  assert.deepEqual(await cache.read(7, async () => result(2)), result(2));
  assert.equal(requests, 1);
  now = 30_001;
  await cache.read(7, async () => result(3));
  assert.equal(requests, 2);
});

test("failed DB loads are evicted from single flight", async () => {
  const { cache } = fixture();
  await assert.rejects(cache.read(7, async () => { throw new Error("DB failed"); }));
  assert.deepEqual(await cache.read(7, async () => result(2)), result(2));
});

test("service invalidates institutional catalog after both scale mutations and retains public response", async () => {
  const { GradesService } = await import("../src/modules/grades/grades.service");
  const { cache } = fixture();
  let selected = "1", queries = 0;
  const repository = {
    findActiveScales: async (institution: number) => { assert.equal(institution, 7); queries++; return [{ id: 1 }, { id: 2 }]; },
    findDefaultScaleSetting: async () => { queries++; return selected; },
    findInstitutionScale: async () => ({ id: 2 }),
    upsertDefaultScaleSetting: async (_institution: number, id: number) => { selected = String(id); },
    writeScale: async () => ({ id: 2 }),
  };
  const permissions = { isAdmin: () => true, requireAdminPermission: () => {} };
  const service = new GradesService(repository as any, permissions as any, cache);
  const ctx = { institutionId: 7, userId: 1, roles: new Set(["admin"]) } as AppContext;
  assert.deepEqual(await service.getDefaultScale(ctx), { scale: { id: 1 }, status: "configured" });
  await service.getDefaultScale({ ...ctx, userId: 2 });
  assert.equal(queries, 2);
  await service.setDefaultScale(ctx, { id: 2 });
  assert.deepEqual(await service.getDefaultScale(ctx), { scale: { id: 2 }, status: "configured" });
  assert.equal(queries, 4);
  await service.upsertScale(ctx, { name: "Scale", type: "numeric", minValue: 0, maxValue: 100, passValue: 60 });
  await service.getDefaultScale(ctx);
  assert.equal(queries, 6);
});
