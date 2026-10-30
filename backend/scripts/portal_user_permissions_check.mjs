// --apply installs only the additive RPCs. Every permission change is rolled
// back to a savepoint before commit; no user's actual settings are changed.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import pg from 'pg';
import {loadEnv,pgConfig} from './env.mjs';
const c=new pg.Client({...pgConfig(loadEnv()),connectionTimeoutMillis:15000});
const migration='0062_portal_user_permission_editor.sql';
const apply=process.argv.includes('--apply');
try {
  await c.connect();await c.query('begin');
  await c.query("set local statement_timeout='20s'");
  await c.query("set local lock_timeout='5s'");
  await c.query("select pg_advisory_xact_lock(hashtext('educa-migration-0062'))");
  const installed=(await c.query('select 1 from public._applied_scripts where name=$1',[migration])).rowCount>0;
  if(!installed) await c.query(readFileSync(new URL('../../supabase/migrations/'+migration,import.meta.url),'utf8'));
  const actors=(await c.query(`select id,auth_user_id,institution_id,lower(email) email from users where active and deleted_at is null
    and lower(email) in ('ernesto@bigschool.edu','pablo@bigschool.edu','maikel@bigschool.edu','osmar@bigschool.edu')`)).rows;
  assert.equal(actors.length,4);
  const admin=actors.find(u=>u.email==='ernesto@bigschool.edu');
  const student=actors.find(u=>u.email==='pablo@bigschool.edu');
  const parent=actors.find(u=>u.email==='maikel@bigschool.edu');
  const staff=actors.find(u=>u.email==='osmar@bigschool.edu');
  const hash=async()=>(await c.query("select md5(coalesce(jsonb_agg(to_jsonb(p) order by id)::text,'[]')) hash from portal_permission_rules p")).rows[0].hash;
  const before=await hash();
  const foreign=(await c.query('select id from users where institution_id<>$1 and active and deleted_at is null limit 1',[admin.institution_id])).rows[0];
  await c.query('savepoint fixtures');
  // Only uncommitted test overrides are replaced to make inheritance assertions
  // deterministic; the original complete table hash is checked before commit.
  await c.query("delete from portal_permission_rules where scope='user' and user_id=any($1::bigint[])",[[student.id,parent.id]]);
  async function as(actor) {
    await c.query('reset role');
    await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor.auth_user_id,role:'authenticated',institution_id:actor.institution_id})]);
    await c.query('set local role authenticated');
  }
  async function one(payload){await c.query("select public.manage_portal_access('save_permission',$1)",[payload]);}
  async function view(id){return(await c.query('select public.portal_user_permissions($1) data',[id])).rows[0].data;}
  async function save(id,changes){return(await c.query('select public.manage_portal_user_permissions($1,$2) data',[id,JSON.stringify(changes)])).rows[0].data;}
  async function denied(fn,code){await c.query('savepoint invalid');await assert.rejects(fn,e=>e.code===code);await c.query('rollback to savepoint invalid');}
  await as(admin);
  await one({scope:'institution',permission:'assignments.view',allowed:false});
  await one({scope:'role',role:'student',permission:'payments.view',allowed:false});
  await one({scope:'user',userId:student.id,permission:'grades.view',allowed:false});
  let snapshot=await view(student.id);
  assert.equal(Object.keys(snapshot.permissions).length,11);
  assert.equal(snapshot.permissions['assignments.view'],false);
  assert.equal(snapshot.permissions['payments.view'],false);
  assert.equal(snapshot.permissions['grades.view'],false);
  snapshot=await save(student.id,[{permission:'reports.view',allowed:true},{permission:'reports.download',allowed:false},{permission:'grades.view',allowed:true}]);
  assert.equal(snapshot.permissions['reports.view'],true);
  assert.equal(snapshot.permissions['reports.download'],false);
  assert.equal(snapshot.permissions['grades.view'],true);
  assert.equal(snapshot.permissions['payments.view'],false);
  assert.equal(snapshot.permissions['assignments.view'],false);
  assert.deepEqual(Object.keys(snapshot.overrides).sort(),['grades.view','reports.download','reports.view']);
  // Untouched permissions still follow subsequent role/institution changes.
  await one({scope:'institution',permission:'assignments.view',allowed:true});
  await one({scope:'role',role:'student',permission:'payments.view',allowed:true});
  snapshot=await view(student.id);
  assert.equal(snapshot.permissions['assignments.view'],true);
  assert.equal(snapshot.permissions['payments.view'],true);
  const parentSnapshot=await save(parent.id,[{permission:'reports.view',allowed:false},{permission:'reports.download',allowed:true}]);
  assert.equal(parentSnapshot.permissions['reports.view'],false);
  assert.equal(parentSnapshot.permissions['reports.download'],true);
  for(const changes of [null,[],['reports.view'],[{permission:'reports.view',allowed:'false'}],
    [{permission:'unknown',allowed:false}],[{permission:'reports.view',allowed:true},{permission:'reports.view',allowed:false}]]) {
    await denied(()=>save(student.id,changes),'22023');
  }
  assert.deepEqual(await view(student.id),snapshot);
  for(const id of [foreign.id,staff.id]) {
    await denied(()=>view(id),'42501');
    await denied(()=>save(id,[{permission:'reports.view',allowed:false}]),'42501');
  }
  await as(student);
  for(const [code,expected] of Object.entries(snapshot.permissions)) assert.equal((await c.query('select portal_can($1) allowed',[code])).rows[0].allowed,expected);
  await denied(()=>view(student.id),'42501');
  await denied(()=>save(student.id,[{permission:'reports.view',allowed:false}]),'42501');
  await as(parent);await denied(()=>view(parent.id),'42501');
  await c.query('reset role');await c.query('rollback to savepoint fixtures');
  assert.equal(await hash(),before);
  if(apply) {
    await c.query('insert into public._applied_scripts(name) values($1) on conflict do nothing',[migration]);
    await c.query('commit');
  }else await c.query('rollback');
  console.log(JSON.stringify({migration,mode:apply?'applied':'validated-and-rolled-back',effectiveSwitches:true,mixedBooleanStates:true,globalInheritancePreserved:true,tenantAndStaffGuards:true,originalPermissionsPreserved:true}));
}catch(e){await c.query('rollback').catch(()=>{});console.error(e.message);process.exitCode=1;}
finally{await c.end();}
