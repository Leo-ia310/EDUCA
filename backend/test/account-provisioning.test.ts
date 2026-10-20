import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fixture-public';
const { AccountProvisioningService } = require('../src/modules/admin/account-provisioning.service') as typeof import('../src/modules/admin/account-provisioning.service');
function fixture() {
    const job = { id: randomUUID(), authUserId: randomUUID(), email: 'fixture@school.invalid', status: 'pending', result: null as any };
    const users = new Map<string, any>(), begins: any[] = [], observed: string[] = [];
    let creates = 0, commits = 0, rejected = 0, loseAuth = false, loseSql = false, providerStatus = 0;
    const result = { user: { id: 101 }, entity: { id: 77 } };
    const repository = {
        async beginProvision(...args: any[]) { begins.push(args); return { ...job }; },
        async completeProvision(_id: string) {
            if (job.status !== 'completed') {
                commits++;
                job.status = 'completed';
                job.result = result;
            }
            if (loseSql) {
                loseSql = false;
                throw Error('lost SQL response');
            }
            return result;
        },
        async observeProvision(_id: string, auth: string) { observed.push(auth); return true; },
        async rejectProvision(_id: string) { rejected++; job.status = 'cancelled'; return true; },
    };
    const auth = { auth: { admin: {
                async getUserById(id: string) { return users.has(id) ? { data: { user: users.get(id) }, error: null } : { data: { user: null }, error: { status: 404 } }; },
                async createUser(payload: any) {
                    creates++;
                    if (providerStatus)
                        return { data: { user: null }, error: { status: providerStatus, message: 'private provider diagnostics' } };
                    if (users.has(payload.id))
                        return { data: { user: null }, error: { status: 400 } };
                    const user = { id: payload.id, email: payload.email, app_metadata: payload.app_metadata };
                    users.set(payload.id, user);
                    if (loseAuth) {
                        loseAuth = false;
                        throw Error('lost provider response');
                    }
                    return { data: { user }, error: null };
                },
                async deleteUser() { throw Error('must never delete an ambiguous creation'); },
            } } };
    const service = new AccountProvisioningService(repository, () => auth);
    const payload = { person: { first_name: 'Fixture', last_name: 'Test' }, entity: { student_code: 'FIXTURE' }, relations: {}, account: { email: job.email, full_name: 'Fixture Test', active: true } };
    const key = randomUUID(), password = 'fixture-password-only';
    return { job, users, begins, observed, service, payload, key, password,
        create: () => service.create(1, 'students', key, payload, password),
        counts: () => ({ creates, commits, rejected }), loseAuth: () => { loseAuth = true; }, loseSql: () => { loseSql = true; }, provider: (status: number) => { providerStatus = status; } };
}
test('a lost Auth response resumes the reserved UUID without creating or deleting another account', async () => {
    const f = fixture();
    f.loseAuth();
    await assert.rejects(f.create(), { status: 503 });
    assert.equal(f.users.size, 1);
    assert.equal(f.counts().commits, 0);
    const result = await f.create();
    assert.equal(result.user.id, 101);
    assert.deepEqual(f.counts(), { creates: 1, commits: 1, rejected: 0 });
    assert.equal(f.begins[0][4], f.begins[1][4]);
    assert.match(f.begins[0][4], /^[0-9a-f]{64}$/);
    assert.ok(!JSON.stringify(f.begins).includes(f.password));
    assert.deepEqual(f.users.get(f.job.authUserId).app_metadata.roles, ['student']);
});
test('a lost SQL response returns its durable completed result without deleting Auth', async () => {
    const f = fixture();
    f.loseSql();
    await assert.rejects(f.create());
    const result = await f.create();
    assert.equal(result.entity.id, 77);
    assert.deepEqual(f.counts(), { creates: 1, commits: 1, rejected: 0 });
});
test('explicit provider rejection retires only an uncreated reservation; transient failures remain pending', async () => {
    const definite = fixture();
    definite.provider(422);
    await assert.rejects(definite.create(), (e: any) => e.status === 400 && e.code === 'auth_user_create_failed' && !e.message.includes('private'));
    assert.equal(definite.counts().rejected, 1);
    const transient = fixture();
    transient.provider(503);
    await assert.rejects(transient.create(), { status: 503 });
    assert.equal(transient.counts().rejected, 0);
});
test('an existing Auth identity with another provenance is never adopted', async () => {
    const f = fixture();
    f.users.set(f.job.authUserId, { id: f.job.authUserId, email: f.job.email, app_metadata: { institution_id: 1, provisioning_id: randomUUID() } });
    await assert.rejects(f.create(), { status: 409 });
    assert.equal(f.counts().creates, 0);
    assert.equal(f.counts().commits, 0);
});
test('concurrent retries materialize one account and return the same result', async () => {
    const f = fixture();
    const results = await Promise.all([f.create(), f.create()]);
    assert.deepEqual(results[0], results[1]);
    assert.equal(f.users.size, 1);
    assert.equal(f.counts().commits, 1);
});
