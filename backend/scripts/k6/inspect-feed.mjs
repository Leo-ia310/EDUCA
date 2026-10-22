// Read-only profiling under the authenticated role: retains the production RLS policies.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { Client } = require('pg');
const e = require('dotenv').parse(fs.readFileSync(path.resolve(import.meta.dirname, '../../.env')));
const client = new Client({ host: e.SUPABASE_DB_HOST, port: Number(e.SUPABASE_DB_PORT), user: e.SUPABASE_DB_USER, password: e.SUPABASE_DB_PASSWORD, database: e.SUPABASE_DB_NAME || 'postgres', ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 10000 });
const output = { at: new Date().toISOString(), observations: [] };
try {
  await client.connect();
  const actorId = Number(process.env.PROFILE_USER_ID || 12);
  if (!Number.isSafeInteger(actorId) || actorId < 1) throw Error('Invalid PROFILE_USER_ID');
  const { rows: [actor] } = await client.query('select auth_user_id,institution_id,person_id from public.users where id=$1 and active and deleted_at is null', [actorId]);
  if (!actor) throw Error('Authorized actor fixture not available');
  let studentId = null;
  if (process.env.PROFILE_FAMILY_SCOPE === '1') {
    const {rows: [student]} = await client.query(`select id from public.students where institution_id=$1 and person_id=$2
      union select ps.student_id from public.parent_students ps join public.parents p on p.id=ps.parent_id
      where p.institution_id=$1 and p.person_id=$2 order by id limit 1`, [actor.institution_id,actor.person_id]);
    if (!student) throw Error('No authorized student scope');
    studentId = Number(student.id);
    if (!Number.isSafeInteger(studentId) || studentId < 1) throw Error('Invalid student scope');
  }
  output.familyScope = studentId !== null;
  const { rows: [fn] } = await client.query("select pg_get_functiondef('public.assignment_feed(bigint,bigint,text,boolean,text[],text,timestamptz,bigint,integer)'::regprocedure) as definition");
  await client.query('begin read only');
  await client.query("set local statement_timeout='20s'");
  await client.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({ sub: actor.auth_user_id, role: 'authenticated', institution_id: actor.institution_id })]);
  await client.query('set local role authenticated');
  const settings = await client.query("select current_user,public.current_institution_id() as institution,current_setting('jit') as jit,current_setting('jit_above_cost') as jit_above_cost");
  output.context = settings.rows[0];
  for (const variant of ['rpc-default', 'cte-default', 'cte-jit-off']) {
    if (variant === 'cte-jit-off') await client.query('set local jit=off');
    let sql = `select public.assignment_feed(p_student_id=>${studentId ?? 'null'}::bigint,p_limit=>20)`;
    if (variant.startsWith('cte')) {
      const start = fn.definition.indexOf('with base as materialized');
      const end = fn.definition.indexOf(' into result;', start);
      if (start < 0 || end < 0) throw Error('Live feed definition has changed; refusing approximate SQL');
      sql = fn.definition.slice(start, end);
      const values = { p_student_id: `${studentId ?? 'null'}::bigint`, p_class_id: 'null::bigint', p_search: 'null::text', p_only_open: 'false', p_kinds: 'null::text[]', p_subject: 'null::text', p_after_due_at: 'null::timestamptz', p_after_id: 'null::bigint', p_limit: '20' };
      for (const [key, value] of Object.entries(values)) sql = sql.replace(new RegExp(`\\b${key}\\b`, 'g'), value);
    }
    await client.query('savepoint inspection');
    try {
      const t = performance.now();
      const result = await client.query('explain (analyze,buffers,settings,format json) ' + sql);
      output.observations.push({ variant, clientMs: performance.now() - t, explain: result.rows[0]['QUERY PLAN'] });
      console.log(JSON.stringify({ variant, ms: performance.now() - t, executionMs: result.rows[0]['QUERY PLAN'][0]['Execution Time'], jit: result.rows[0]['QUERY PLAN'][0].JIT }));
    } catch (error) {
      await client.query('rollback to savepoint inspection');
      output.observations.push({ variant, error: error.code, message: error.message });
      console.log(JSON.stringify({ variant, error: error.code, message: error.message }));
    }
  }
} finally {
  await client.query('rollback').catch(() => {});
  await client.end();
  const out = path.resolve(import.meta.dirname, '../../stress-results',process.env.RUN_LABEL || '2026-10-20');
  fs.mkdirSync(out,{recursive:true});
  fs.writeFileSync(path.join(out,'feed-explain.json'), JSON.stringify(output, null, 2));
}
