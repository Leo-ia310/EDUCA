// Regression checks plus read-only SQL scope checks. No accounts/data created.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const {SchedulesService} = require('../src/modules/schedules/schedules.service.ts') as typeof import('../src/modules/schedules/schedules.service');
const {SchedulesRepository} = require('../src/modules/schedules/schedules.repository.ts') as typeof import('../src/modules/schedules/schedules.repository');
const {PermissionsService} = require('../src/services/permissions.service.ts') as typeof import('../src/services/permissions.service');
const {requireSupabaseServiceRole} = require('../src/lib/supabase.ts') as typeof import('../src/lib/supabase');
type Context = import('../src/types/app-context').AppContext;

async function main() {
  let received: unknown;
  let enrolled = true;
  const row = {id: 301, kind: 'class', institution_id: 7, class_id: 40,
    weekday_id: 1, start_time: '08:00:00', end_time: '09:00:00',
    classes: {group_id: 20, subjects: {name: 'Álgebra asignada'}}};
  class Repository extends SchedulesRepository {
    async groupIdsOfStudent(institutionId: number, studentId: number) {
      assert.equal(institutionId, 7); assert.equal(studentId, 10);
      return enrolled ? [20] : [];
    }
    async classesOfGroups(institutionId: number, groupIds: number[]) {
      assert.equal(institutionId, 7);
      return groupIds.length ? [{id: 40, group_id: 20}] : [];
    }
    async listByInstitution(): Promise<any[]> { throw Error('Must not load entire institution'); }
    async listForClasses(institutionId: number, classIds: number[], groupIds: number[]) {
      received = [institutionId, classIds, groupIds];
      return classIds.length ? [row] : [];
    }
  }
  const permissions = new PermissionsService({parentStudentLinkExists: async (_inst: number, _parent: number, id: number) => id === 10} as any);
  const service = new SchedulesService(new Repository(), permissions);
  const ctx: Context = {authUserId: 'fixture', userId: 1, institutionId: 7,
    personId: 1, fullName: 'Fixture', roles: new Set(['student']), adminPermissions: null, studentId: 10};
  const own = await service.mine(ctx, {institutionId: 999});
  assert.equal(own.schedules[0].subject, 'Álgebra asignada');
  assert.deepEqual(received, [7, [40], [20]], 'Institution comes from authenticated session');
  await assert.rejects(service.mine(ctx, {studentId: 11}), (e: any) => e.status === 403);
  enrolled = false;
  assert.deepEqual(await service.mine(ctx, {}), {schedules: []});
  assert.deepEqual(received, [7, [], []]);
  enrolled = true;
  const parent = {...ctx, roles: new Set(['parent']), parentId: 3};
  await assert.rejects(service.mine(parent, {studentId: 11}), (e: any) => e.status === 403);
  await assert.rejects(service.mine(parent, {}), (e: any) => e.status === 403);
  assert.equal((await service.mine(parent, {studentId: 10})).schedules.length, 1);

  const db = requireSupabaseServiceRole();
  const repository = new SchedulesRepository(db);
  assert.deepEqual(await repository.listForClasses(7, [], []), []);
  const scheduled = await db.from('schedules').select('class_id,institution_id,classes(group_id)')
    .not('class_id', 'is', null).limit(1).maybeSingle();
  assert.ifError(scheduled.error);
  if (scheduled.data) {
    const item = scheduled.data as any;
    const institutionId = Number(item.institution_id);
    const classId = Number(item.class_id);
    const groupIds = item.classes?.group_id == null ? [] : [Number(item.classes.group_id)];
    const rows = await repository.listForClasses(institutionId, [classId], groupIds);
    assert.ok(rows.some(r => Number(r.class_id) === classId));
    assert.ok(rows.every(r => Number(r.institution_id) === institutionId));
    assert.ok(rows.every(r => r.kind === 'break'
      ? r.group_id == null || groupIds.includes(Number(r.group_id))
      : Number(r.class_id) === classId));
    assert.deepEqual(await repository.listForClasses(-institutionId, [classId], groupIds), []);
    assert.deepEqual(await repository.listForClasses(institutionId, [Number.MAX_SAFE_INTEGER], groupIds), [], 'No standalone breaks');
    console.log('Read-only database scopes passed: actual class schedule, group/general breaks, cross-institution rejection and no standalone breaks.');
  } else {
    console.log('No persisted class schedule available for positive SQL check; service scope checks passed.');
  }
  console.log('Student/parent identity, institution and empty schedule checks passed. No data modified.');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
