// Real DB/RLS regression check. All publications are rolled back and no
// notification service is called, so this does not send email or push.
import assert from 'node:assert/strict';
import pg from 'pg';
import { loadEnv, pgConfig } from './env.mjs';

const client = new pg.Client({ ...pgConfig(loadEnv()), connectionTimeoutMillis: 10000, query_timeout: 15000 });
try {
  await client.connect();
  await client.query('begin');
  const actor = (await client.query(`select u.id,u.auth_user_id,u.institution_id from users u
    join user_roles ur on ur.user_id=u.id join roles r on r.id=ur.role_id
    where u.institution_id=2 and u.active=true and u.deleted_at is null
      and u.auth_user_id is not null and r.code in ('admin','coordinator','director','super_admin') limit 1`)).rows[0];
  assert.ok(actor, 'An existing admin is required for the RLS check');
  await client.query(`select set_config('request.jwt.claims',$1,true)`, [JSON.stringify({ sub: actor.auth_user_id, role: 'authenticated', app_metadata: { institution_id: Number(actor.institution_id) } })]);
  await client.query('set local role authenticated');
  const publish = (institution = actor.institution_id, author = actor.id, title = 'Atomic announcement regression') => client.query(
    'select public.publish_school_announcement($1,$2,$3,$4,$5,$6) as result',
    [institution, author, title, 'Temporary transaction test', '2000-01-01T00:00:00Z', 'all'],
  );
  const result = (await publish()).rows[0].result;
  assert.equal(String(result.announcement.institution_id), String(actor.institution_id));
  assert.equal(String(result.announcement.created_by), String(actor.id));
  assert.equal(result.announcement.published, true);
  assert.equal(result.announcement.event_id, result.event.id);
  const saved = (await client.query('select id from announcements where institution_id=$1 and published=true and id=$2', [actor.institution_id, result.announcement.id])).rows;
  assert.equal(saved.length, 1, 'Published announcement must be immediately readable under RLS');
  for (const [institution, author] of [[999, actor.id], [actor.institution_id, 999999999]]) {
    await client.query('savepoint denied_actor');
    await assert.rejects(publish(institution, author), /permiso/);
    await client.query('rollback to savepoint denied_actor');
  }
  await client.query('reset role');
  await client.query(`create function pg_temp.reject_regression_announcement() returns trigger language plpgsql as $$
    begin if new.title='Atomic failure regression' then raise exception 'simulated announcement failure'; end if; return new; end $$`);
  await client.query(`create trigger regression_announcement_failure before insert on public.announcements
    for each row execute function pg_temp.reject_regression_announcement()`);
  await client.query('set local role authenticated');
  await client.query('savepoint failed_publication');
  await assert.rejects(publish(actor.institution_id, actor.id, 'Atomic failure regression'), /simulated announcement failure/);
  await client.query('rollback to savepoint failed_publication');
  const orphan = (await client.query("select count(*)::int as n from calendar_events where title='Atomic failure regression'")).rows[0].n;
  assert.equal(orphan, 0, 'A failed announcement must roll back its calendar event');
  console.log('DB checks passed: authenticated publication, immediate listing, tenant/author validation, RLS and atomic rollback.');
} finally {
  await client.query('rollback').catch(() => {});
  await client.end();
}
