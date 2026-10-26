// Measure equivalence and speed before committing the scoped RLS optimization.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import pg from 'pg';
import {loadEnv,pgConfig} from './env.mjs';
const c=new pg.Client({...pgConfig(loadEnv()),connectionTimeoutMillis:15000});
const apply=process.argv.includes('--apply');
const name='0060_batched_attendance_portal_scope.sql';
const actorIds=[13,55,12,11];
async function asActor(id,fn) {
 await c.query('reset role');
 const actor=(await c.query('select auth_user_id,institution_id from users where id=$1',[id])).rows[0];
 await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor.auth_user_id,role:'authenticated',institution_id:actor.institution_id})]);
 await c.query('set local role authenticated');
 try{return await fn();}finally{await c.query('reset role');}
}
async function snapshot() {
 const result={};
 for(const id of actorIds) result[id]=await asActor(id,async()=>{
   // Compare the original row predicates with their batched equivalents over
   // every resource in this tenant, including archived/test resources.
   const diff=(await c.query(`select
    (select count(*) from classes where institution_id=public.current_institution_id() and
      public.portal_class_scope(id) is distinct from (public.portal_staff_actor() or id=any(public.portal_family_class_ids()))) classes,
    (select count(*) from students where institution_id=public.current_institution_id() and
      public.portal_student_scope(id) is distinct from (public.portal_staff_actor() or id=any(public.portal_family_student_ids()))) students`)).rows[0];
   assert.equal(Number(diff.classes),0);assert.equal(Number(diff.students),0);
   const start=performance.now();
   const report=(await c.query('select public.student_report_context($1,6) data',[id===55?23:22])).rows[0].data;
   const marks=(await c.query(`select a.id,a.student_id,a.attendance_status_id,s.id session_id from attendances a
     join class_sessions s on s.id=a.class_session_id where a.institution_id=2 and a.student_id=$1 order by a.id`,[id===55?23:22])).rows;
   // Family actors must still see no unrelated attendance or other tenants.
   if(id===13||id===55) assert.equal((await c.query('select count(*) n from attendances where student_id=$1',[id===13?23:22])).rows[0].n,'0');
   assert.equal((await c.query('select count(*) n from attendances where institution_id<>2')).rows[0].n,'0');
   return {report,hash:createHash('sha256').update(JSON.stringify(marks)).digest('hex'),count:marks.length,ms:performance.now()-start};
 });
 return result;
}
try {
 await c.connect();await c.query('begin');
 await c.query("set local statement_timeout='30s'");
 await c.query("set local lock_timeout='5s'");
 await c.query("select pg_advisory_xact_lock(hashtext('educa-migration-0060'))");
 if(apply && (await c.query('select 1 from public._applied_scripts where name=$1',[name])).rowCount) {
   throw Error('0060 ya está aplicada; se conserva el archivo de reversión original.');
 }
 const before=await snapshot();
 console.log(JSON.stringify({phase:'before',timings:Object.fromEntries(Object.entries(before).map(([id,r])=>[id,r.ms]))}));
 const policies=(await c.query("select tablename,policyname,qual from pg_policies where schemaname='public' and policyname='portal_module_read' and tablename in ('attendances','class_sessions') order by tablename")).rows;
 assert.equal(policies.length,2);
 const rollback=['BEGIN;',...policies.map(p=>`alter policy ${p.policyname} on public.${p.tablename} using (${p.qual});`),`delete from public._applied_scripts where name='${name}';`,'COMMIT;'].join('\n');
 await c.query(readFileSync(new URL('../../supabase/migrations/'+name,import.meta.url),'utf8'));
 const after=await snapshot();
 for(const id of actorIds){assert.deepEqual(after[id].report,before[id].report);assert.equal(after[id].hash,before[id].hash);}
 if(apply) {
   writeFileSync(new URL('../../supabase/demo/rollback-0060.sql',import.meta.url),rollback);
   await c.query('insert into public._applied_scripts(name) values($1) on conflict do nothing',[name]);
 }
 const summary={mode:apply?'applied':'validated-and-rolled-back',equivalentReports:true,equivalentAttendance:true,tenantAndFamilyIsolation:true,
   timings:Object.fromEntries(actorIds.map(id=>[id,{beforeMs:before[id].ms,afterMs:after[id].ms,records:after[id].count}]))};
 await c.query(apply?'commit':'rollback');console.log(JSON.stringify(summary,null,2));
}catch(e){await c.query('rollback').catch(()=>{});console.error(e.message);process.exitCode=1;}
finally{await c.end();}
