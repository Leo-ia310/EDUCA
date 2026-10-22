import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { database } from './helpers/database.mjs';

test('SQL Editor bundle blocks conflicting schedules atomically and keeps 2FA optional', { timeout: 120000 }, async () => {
  const db = await database({ through: '0028_two_factor_methods.sql' });
  const q = (sql, params) => db.admin.query(sql, params);
  try {
    const sql = await readFile(new URL('../../supabase/deploy/scalability-0029-0053.sql', import.meta.url), 'utf8');
    const institution = (await q("insert into institutions(code,name) values('BUNDLE','Bundle test') returning id")).rows[0].id;
    const year = (await q("insert into academic_years(institution_id,name,year,is_current) values($1,'2026',2026,true) returning id", [institution])).rows[0].id;
    const group = (await q("insert into groups(institution_id,academic_year_id,name) values($1,$2,'A') returning id", [institution, year])).rows[0].id;
    const classId = (await q('insert into classes(institution_id,academic_year_id,group_id) values($1,$2,$3) returning id', [institution, year, group])).rows[0].id;
    const schedules = (await q("insert into schedules(institution_id,class_id,weekday_id,start_time,end_time) values($1,$2,1,'08:00','09:30'),($1,$2,1,'08:00','09:30') returning id", [institution, classId])).rows;
    await assert.rejects(q(sql), error => error.code === '23P01' && error.message.includes('horarios incompatibles'));
    await q('ROLLBACK');
    assert.equal((await q("select to_regclass('public.backend_user_quotas') result")).rows[0].result, null);
    assert.equal((await q('select count(*) from schedules where institution_id=$1', [institution])).rows[0].count, '2');
    // The fixture correction is local only. The real timetable requires review.
    await q("update schedules set start_time='10:00',end_time='11:30' where id=$1", [schedules[1].id]);
    await q(sql);
    assert.deepEqual((await q('select public.backend_readiness_v1() result')).rows[0].result, { schemaVersion: 53 });
    const authId = randomUUID(), sessionId = randomUUID();
    await q('insert into auth.users(id) values($1)', [authId]);
    await q('insert into auth.sessions(id,user_id) values($1,$2)', [sessionId, authId]);
    const actor = (await q("insert into users(auth_user_id,institution_id,email,full_name) values($1,$2,'bundle@test.invalid','Bundle test') returning id", [authId, institution])).rows[0].id;
    const role = (await q("insert into roles(institution_id,name,code) values($1,'Admin','admin') returning id", [institution])).rows[0].id;
    await q('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)', [actor, role, institution]);
    const context = async () => (await q('select public.backend_request_context($1,$2) result', [authId, sessionId])).rows[0].result;
    assert.equal((await context()).allowed, true, 'No 2FA settings must allow normal use');
    await q('insert into auth_two_factor_settings(user_id,enabled) values($1,false)', [actor]);
    assert.equal((await context()).allowed, true, 'Disabled 2FA must allow normal use');
    await q('update auth_two_factor_settings set enabled=true where user_id=$1', [actor]);
    await assert.rejects(context(), error => error.code === '42501' && error.detail === 'two_factor_required');
    await assert.rejects(q(sql), /marcador de esta actualización ya existe/);
    await q('ROLLBACK');
  } finally {
    await db.close();
  }
});

test('incremental assignment bundle installs both fixes atomically and preserves the deployed base readiness contract', {timeout:120000}, async()=>{
  const db=await database({through:'0053_backend_readiness.sql'});
  try {
    const sql=await readFile(new URL('../../supabase/deploy/assignment-performance-0054-0055.sql',import.meta.url),'utf8');
    await db.admin.query(sql);
    assert.deepEqual((await db.admin.query('select backend_readiness_v1() result')).rows[0].result,{schemaVersion:53,assignmentWriteVersion:1});
    assert.equal((await db.admin.query("select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity")).rows[0].count,'0');
    await assert.rejects(db.admin.query(sql),/already present/);await db.admin.query('rollback');
  } finally {await db.close();}
});
