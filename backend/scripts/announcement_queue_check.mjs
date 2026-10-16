// All rows stay inside a rolled-back transaction. No external delivery occurs.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { loadEnv, pgConfig } from './env.mjs';

const client = new pg.Client({ ...pgConfig(loadEnv()), connectionTimeoutMillis: 10000, query_timeout: 15000 });
try {
  await client.connect();
  await client.query('begin');
  const actor = (await client.query(`select u.id,u.auth_user_id,u.institution_id from users u
    join user_roles ur on ur.user_id=u.id join roles r on r.id=ur.role_id
    where u.active and u.deleted_at is null and u.auth_user_id is not null and r.code='admin' limit 1`)).rows[0];
  assert.ok(actor);
  await client.query(`select set_config('request.jwt.claims',$1,true)`, [JSON.stringify({ sub: actor.auth_user_id,
    role: 'authenticated', app_metadata: { institution_id: Number(actor.institution_id) } })]);
  const key = randomUUID();
  const publish = (title = 'Queue regression') => client.query(
    'select publish_school_announcement($1,$2,$3,$4,$5,$6,$7) as result',
    [actor.institution_id, actor.id, title, 'Not sent; rolled back', '2026-10-15T12:00:00Z', 'all', key]);
  await client.query('set local role authenticated');
  const created = (await publish()).rows[0].result;
  const duplicate = (await publish()).rows[0].result;
  assert.equal(created.announcement.id, duplicate.announcement.id);
  assert.equal(created.delivery.id, duplicate.delivery.id);
  assert.equal(created.delivery.status, 'queued');
  assert.equal((await client.query('select count(*)::int n from announcement_delivery_jobs where id=$1', [created.delivery.id])).rows[0].n, 1);
  for (const action of [() => publish('Different body'),
    () => client.query('select claim_announcement_delivery()'),
    () => client.query('select retry_announcement_delivery($1)', [created.delivery.id]),
    () => client.query('update announcement_delivery_jobs set status=\'completed\' where id=$1', [created.delivery.id])]) {
    await client.query('savepoint forbidden');
    await assert.rejects(action());
    await client.query('rollback to savepoint forbidden');
  }
  await client.query('reset role');
  // Restrict claims in this transaction to our test job, invisible to workers.
  await client.query(`update announcement_delivery_jobs set status='completed' where id<>$1`, [created.delivery.id]);
  await client.query('set local role service_role');
  let job = (await client.query('select claim_announcement_delivery() job')).rows[0].job;
  assert.equal(job.id, created.delivery.id);
  assert.equal((await client.query('select claim_announcement_delivery() job')).rows[0].job, null);
  await client.query('select prepare_announcement_delivery($1,$2)', [job.id, job.lock_token]);
  const recipients = (await client.query('select * from announcement_delivery_recipients where job_id=$1 order by user_id', [job.id])).rows;
  assert.ok(recipients.length > 0);
  const first = recipients[0];
  await client.query('select record_announcement_delivery($1,$2,$3,$4,$5,$6,$7)', [job.id, job.lock_token, first.user_id, 'sent', 'skipped', 'fake-provider-id', null]);
  // Simulate restart after a checkpoint. A new lease fences the old worker.
  await client.query(`update announcement_delivery_jobs set lease_until=now()-interval '1 second' where id=$1`, [job.id]);
  const oldLock = job.lock_token;
  job = (await client.query('select claim_announcement_delivery() job')).rows[0].job;
  assert.notEqual(job.lock_token, oldLock);
  await client.query('savepoint stale_worker');
  await assert.rejects(client.query('select prepare_announcement_delivery($1,$2)', [job.id, oldLock]), /delivery_lease_lost/);
  await client.query('rollback to savepoint stale_worker');
  await client.query('select prepare_announcement_delivery($1,$2)', [job.id, job.lock_token]);
  assert.equal((await client.query('select count(*)::int n from announcement_delivery_recipients where job_id=$1', [job.id])).rows[0].n, recipients.length);
  for (const r of recipients.slice(1)) await client.query('select record_announcement_delivery($1,$2,$3,$4,$5,$6,$7)',
    [job.id, job.lock_token, r.user_id, r === recipients[1] ? 'failed' : 'skipped', 'skipped', null, null]);
  const finished = (await client.query('select finish_announcement_delivery($1,$2) job', [job.id, job.lock_token])).rows[0].job;
  assert.equal(finished.status, recipients.length > 1 ? 'completed_with_errors' : 'completed');
  const notices = (await client.query("select * from notifications where delivery_key=$1", [`announcement/${job.announcement_id}/completion/1`])).rows;
  assert.equal(notices.length, 1);
  assert.equal(String(notices[0].user_id), String(actor.id));
  assert.equal(notices[0].read, false);
  const retry = (await client.query('select retry_announcement_delivery($1) job', [job.id])).rows[0].job;
  if (recipients.length > 1) {
    assert.equal(retry.status, 'queued');
    assert.equal(retry.processed, recipients.length - 1, 'Retry progress must exclude failed recipients now pending');
    assert.equal(retry.email_failed, 0);
  }
  const checkpoint = (await client.query('select email_status from announcement_delivery_recipients where job_id=$1 and user_id=$2', [job.id, first.user_id])).rows[0];
  assert.equal(checkpoint.email_status, 'sent', 'Retry preserves successfully sent email');
  console.log('Queue DB checks passed: atomic/idempotent publication, RLS, worker-only access, lease recovery/fencing, recipient checkpoints, final admin notification and selective retry. No emails sent.');
} finally {
  await client.query('rollback').catch(() => {});
  await client.end();
}
