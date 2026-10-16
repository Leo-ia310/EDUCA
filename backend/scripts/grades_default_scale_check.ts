import assert from "node:assert/strict";
import { GradesRepository } from "../src/modules/grades/grades.repository";
import { GradesService } from "../src/modules/grades/grades.service";
import type { AppContext } from "../src/types/app-context";

const ctx = { institutionId: 7 } as AppContext;
const scales = [
  { id: 1, institution_id: 8, active: true },
  { id: 2, institution_id: 7, active: false },
  { id: 3, institution_id: 7, active: true },
  { id: 4, institution_id: 7, active: true },
];

function service(defaultId: string | null, rows = scales, dbError = false) {
  const client = {
    from(table: string) {
      let selected: Array<Record<string, unknown>> = table === "grading_scales"
        ? [...rows]
        : defaultId == null ? [] : [{ institution_id: 7, key: "default_grading_scale_id", value: defaultId }];
      const query = {
        select() { return query; },
        eq(key: string, value: unknown) {
          assert.ok(!key.includes("period"), "Scales must be shared across terms");
          selected = selected.filter((row) => row[key] === value);
          return query;
        },
        order() { return query; },
        maybeSingle() {
          return Promise.resolve({ data: selected[0] ?? null, error: null });
        },
        then(resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) {
          return Promise.resolve({ data: selected, error: dbError ? { message: "Database unavailable" } : null }).then(resolve, reject);
        },
      };
      return query;
    },
  };
  return new GradesService(new GradesRepository(client));
}

async function main() {
  assert.deepEqual(await service(null, []).getDefaultScale(ctx), { scale: null, status: "not_configured" });
  assert.deepEqual(await service(null, scales.slice(0, 2)).getDefaultScale(ctx), { scale: null, status: "not_configured" });
  for (const defaultId of [null, "1", "2", "999", "invalid"]) {
    const result = await service(defaultId).getDefaultScale(ctx);
    assert.equal(result.scale?.id, 3, "Missing, foreign or inactive defaults use first active institutional scale");
  }
  const resolver = service("4");
  for (const term of ["Term 1", "Term 2"]) {
    assert.equal((await resolver.getDefaultScale(ctx)).scale?.id, 4, term);
  }
  await assert.rejects(service(null, scales, true).getDefaultScale(ctx), /Database unavailable/);
  console.log("Grade scale regression checks passed (empty, inactive, tenant scope, defaults, shared terms, DB errors).");
}

void main();
