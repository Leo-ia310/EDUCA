// Validates the additive RPC and rolls back every permission change. --apply
// persists only the function/migration, never the temporary permission rules.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import pg from 'pg';
import {loadEnv,pgConfig} from './env.mjs';
const c=new pg.Client({...pgConfig(loadEnv()),connectionTimeoutMillis:15000});
const migration='0061_batch_portal_permissions.sql';
const apply=process.argv.includes('--apply');
const permissions=['grades.view','payments.view','attendance.view','schedule.view','assignments.view','assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view'];
try {
  await c.connect();await c.query('begin');
  await c.query("set local statement_timeout='20s'");
  await c.query("set local lock_timeout='5s'");
  await c.query("select pg_advisory_xact_lock(hashtext('educa-migration-0061'))");
  const installed=(await c.query('select 1 from public._applied_scripts where name=$1',[migration])).rowCount>0;
  if(!installed) await c.query(readFileSync(new URL('../../supabase/migrations/'+migration,import.meta.url),'utf8'));
  const accounts=(await c.query(`select id,auth_user_id,person_id,institution_id,lower(email) email from users
    where lower(email) in ('ernesto@bigschool.edu','pablo@bigschool.edu','maikel@bigschool.edu') and active and deleted_at is null`)).rows;
  assert.equal(accounts.length,3);
  const admin=accounts.find(u=>u.email==='ernesto@bigschool.edu');
  const student=accounts.find(u=>u.email==='pablo@bigschool.edu');
  const parent=accounts.find(u=>u.email==='maikel@bigschool.edu');
  const studentId=(await c.query('select id from students where person_id=$1 and institution_id=$2',[student.person_id,student.institution_id])).rows[0].id;
  const periodId=(await c.query('select id from academic_periods where institution_id=$1 order by display_order desc limit 1',[student.institution_id])).rows[0].id;
  const rulesHash=async()=>(await c.query('select md5(coalesce(jsonb_agg(to_jsonb(p) order by id)::text,\'[]\')) hash from portal_permission_rules p')).rows[0].hash;
  const original=await rulesHash();
  await c.query('savepoint fixtures');
  async function as(actor) {
    await c.query('reset role');
    await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor.auth_user_id,role:'authenticated',institution_id:actor.institution_id})]);
    await c.query('set local role authenticated');
  }
  async function batch(actor,codes,allowed,extra={}) {
    await as(admin);
    return (await c.query('select public.manage_portal_permissions($1) data',[{scope:'user',userId:actor.id,permissions:codes,allowed,...extra}])).rows[0].data;
  }
  async function can(code){return(await c.query('select portal_can($1) allowed',[code])).rows[0].allowed;}
  async function denied(fn,code) {
    await c.query('savepoint invalid_batch');
    await assert.rejects(fn,e=>!code||e.code===code);
    await c.query('rollback to savepoint invalid_batch');
  }
  // All eleven permissions can coexist on the same user and are reversible.
  for(const actor of [student,parent]) {
    await batch(actor,permissions,false);
    await as(actor);
    for(const code of permissions) assert.equal(await can(code),false);
    await batch(actor,permissions,true);
    await as(actor);
    for(const code of permissions) assert.equal(await can(code),true);
  }
  // Disabling downloads leaves the bulletin readable and other denials intact.
  await batch(student,['payments.view','messages.send','reports.download'],false);
  await as(student);
  assert.equal(await can('reports.view'),true);assert.equal(await can('reports.download'),false);
  assert.ok((await c.query('select public.student_report_context($1,$2) data',[studentId,periodId])).rows[0].data);
  await batch(student,['reports.view'],false);
  await as(student);assert.equal(await can('reports.view'),false);
  await denied(()=>c.query('select public.student_report_context($1,$2)',[studentId,periodId]),'42501');
  await batch(student,['reports.view'],true);
  await as(student);assert.equal(await can('reports.view'),true);assert.equal(await can('reports.download'),false);
  assert.equal(await can('payments.view'),false);assert.equal(await can('messages.send'),false);
  // Callers cannot bypass the same authorization checks through direct RPCs.
  await denied(()=>c.query('select public.manage_portal_permissions($1)',[{scope:'user',userId:student.id,permissions:['reports.view'],allowed:true}]),'42501');
  await as(admin);
  for(const codes of [[],['reports.view','reports.view'],['reports.view','invalid'],[1],null]) {
    await denied(()=>c.query('select public.manage_portal_permissions($1)',[{scope:'user',userId:student.id,permissions:codes,allowed:true}]),'22023');
  }
  await c.query('reset role');
  const foreign=(await c.query('select id from users where institution_id<>$1 and active and deleted_at is null limit 1',[admin.institution_id])).rows[0];
  assert.ok(foreign);
  await as(admin);
  await denied(()=>c.query('select public.manage_portal_permissions($1)',[{scope:'user',userId:foreign.id,permissions:['reports.view','reports.download'],allowed:false}]),'42501');
  await c.query('reset role');
  await c.query('rollback to savepoint fixtures');
  assert.equal(await rulesHash(),original,'No real permission changes may remain.');
  if(apply) {
    await c.query('insert into public._applied_scripts(name) values($1) on conflict do nothing',[migration]);
    await c.query('commit');
  }else await c.query('rollback');
  console.log(JSON.stringify({migration,mode:apply?'applied':'validated-and-rolled-back',multiplePermissions:true,viewAndDownloadIndependent:true,invalidBatchesRejected:true,unauthorizedAndForeignUsersDenied:true,originalPermissionsPreserved:true}));
}catch(e){await c.query('rollback').catch(()=>{});console.error(e.message);process.exitCode=1;}
finally{await c.end();}
