import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import pg from 'pg';
import {loadEnv,pgConfig,ROOT_DIR} from './env.mjs';
const args=process.argv.slice(2),backupArg=args.indexOf('--backup-dir');
if(!args.includes('--apply')||backupArg<0||!args[backupArg+1])throw Error('Usage: --apply --backup-dir <verified private backup directory>');
const backup=path.resolve(args[backupArg+1]);
const manifest=JSON.parse(fs.readFileSync(path.join(backup,'manifest.json'),'utf8'));
const digest=createHash('sha256').update(fs.readFileSync(path.join(backup,manifest.file))).digest('hex');
if(digest!==manifest.sha256||!manifest.verified||Date.now()-Date.parse(manifest.createdAt)>86400000)throw Error('A recent verified backup is required');
const names=['0054_batched_academic_rls.sql','0055_atomic_assignment_write.sql'];
const quote=s=>'"'+s.replaceAll('"','""')+'"';
const client=new pg.Client(pgConfig(loadEnv()));
const report={startedAt:new Date().toISOString(),migrations:names,backupSha256:digest};
async function integrity() {
 const result={};
 for(const name of ['students','parents','persons','enrollments','parent_students','schedules']) {
  result[name]=(await client.query(`select count(*)::int as rows,md5(coalesce(jsonb_agg(to_jsonb(t) order by t.id)::text,'[]')) as hash from public.${quote(name)} t`)).rows[0];
 }
 return result;
}
try {
 await client.connect();
 report.previous=(await client.query('select public.backend_readiness_v1() result')).rows[0].result;
 if(report.previous.schemaVersion!==53||report.previous.assignmentWriteVersion!=null)throw Error('Expected unmodified base contract 53');
 const oldReady=(await client.query("select pg_get_functiondef('public.backend_readiness_v1()'::regprocedure) definition")).rows[0].definition;
 const policies=(await client.query("select tablename,policyname,qual from pg_policies where schemaname='public' and tablename=any($1::text[]) and policyname in ('class_scope_read','class_scope_roster','class_scope_students','portal_module_read')",[['classes','assignments','evaluations','submissions','grades','class_sessions','attendances','enrollments','students']])).rows;
 const drop=['assignment_write(bigint,jsonb,bigint[],uuid)','portal_family_class_ids()','portal_family_student_ids()','portal_staff_actor()','teacher_student_ids()','teacher_group_ids()','class_permission_ids(text)'];
 fs.writeFileSync(path.join(backup,'rollback-assignment-update.sql'),[
  '-- Use only together with a backend rollback; current backend requires assignmentWriteVersion 1.',
  'BEGIN;',"SET LOCAL lock_timeout='5s';",...policies.map(p=>`ALTER POLICY ${quote(p.policyname)} ON public.${quote(p.tablename)} USING (${p.qual});`),
  oldReady,...drop.map(f=>'DROP FUNCTION IF EXISTS public.'+f+';'),
  "DELETE FROM public._applied_scripts WHERE name IN ('0054_batched_academic_rls.sql','0055_atomic_assignment_write.sql');",
  "NOTIFY pgrst, 'reload schema';",'COMMIT;',
 ].join('\n'));
 await client.query('begin isolation level repeatable read');
 await client.query("set local lock_timeout='5s';set local statement_timeout='30s'");
 const before=await integrity();
 for(const name of names)await client.query(fs.readFileSync(path.join(ROOT_DIR,'supabase/migrations',name),'utf8'));
 await client.query('insert into public._applied_scripts(name) select unnest($1::text[]) on conflict do nothing',[names]);
 const after=await integrity();
 if(JSON.stringify(before)!==JSON.stringify(after))throw Error('Academic data integrity changed; rolling back');
 report.academicIntegrityUnchanged=true;report.integrity=after;
 report.unprotectedTables=Number((await client.query("select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity")).rows[0].count);
 if(report.unprotectedTables!==0)throw Error('RLS invariant failed');
 report.installed=(await client.query('select public.backend_readiness_v1() result')).rows[0].result;
 if(report.installed.assignmentWriteVersion!==1)throw Error('New SQL capability missing');
 await client.query("notify pgrst,'reload schema'");await client.query('commit');
 report.completedAt=new Date().toISOString();report.committed=true;
 fs.writeFileSync(path.join(backup,'migration-result.json'),JSON.stringify(report,null,2));
 const out=path.join(ROOT_DIR,'backend/stress-results/2026-10-20/fixes');fs.mkdirSync(out,{recursive:true});
 fs.writeFileSync(path.join(out,'supabase-update.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({committed:true,installed:report.installed,academicIntegrityUnchanged:true,unprotectedTables:report.unprotectedTables,backup}));
} catch(error) {
 await client.query('rollback').catch(()=>{});throw error;
} finally {await client.end();}
