import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import pg from 'pg';
import {loadEnv,pgConfig,ROOT_DIR} from './env.mjs';

const args=process.argv.slice(2),index=args.indexOf('--backup-dir');
if(!args.includes('--apply')||index<0||!args[index+1])throw Error('Usage: --apply --backup-dir <verified private backup directory>');
const backup=path.resolve(args[index+1]),manifest=JSON.parse(fs.readFileSync(path.join(backup,'manifest.json'),'utf8'));
const digest=createHash('sha256').update(fs.readFileSync(path.join(backup,manifest.file))).digest('hex');
const age=Date.now()-Date.parse(manifest.createdAt);
if(digest!==manifest.sha256||!manifest.verified||!Number.isFinite(age)||age<0||age>86400000)throw Error('A recent verified backup is required');
const name='0056_live_actor_role_queries.sql';
const functions=['current_roles()','portal_staff(bigint)','class_admin_actor()','is_teacher_actor()'];
const client=new pg.Client(pgConfig(loadEnv()));
const report={startedAt:new Date().toISOString(),migration:name,backupSha256:digest};
async function integrity() {
 const rows={};
 for(const table of ['students','parents','persons','enrollments','parent_students','schedules','assignments','grades']) {
  rows[table]=(await client.query(`select count(*)::int rows,md5(coalesce(jsonb_agg(to_jsonb(t) order by t.id)::text,'[]')) hash from public.${table} t`)).rows[0];
 }
 return rows;
}
try {
 await client.connect();
 const ready=(await client.query('select public.backend_readiness_v1() result')).rows[0].result;
 if(ready.schemaVersion!==53||ready.assignmentWriteVersion!==1)throw Error('Expected deployed assignment contract');
 await client.query('begin isolation level repeatable read');
 await client.query("set local lock_timeout='5s';set local statement_timeout='30s'");
 await client.query("select pg_advisory_xact_lock(hashtext('educa-migration-0056'))");
 if((await client.query('select 1 from public._applied_scripts where name=$1',[name])).rowCount)throw Error('Migration already applied');
 const old=[];
 for(const fn of functions)old.push((await client.query('select pg_get_functiondef($1::regprocedure) definition',['public.'+fn])).rows[0].definition);
 fs.writeFileSync(path.join(backup,'rollback-role-query-update.sql'),['BEGIN;',...old,`DELETE FROM public._applied_scripts WHERE name='${name}';`,"NOTIFY pgrst,'reload schema';",'COMMIT;'].join('\n'));
 const before=await integrity();
 await client.query(fs.readFileSync(path.join(ROOT_DIR,'supabase/migrations',name),'utf8'));
 const after=await integrity();
 if(JSON.stringify(before)!==JSON.stringify(after))throw Error('Academic integrity changed');
 const unprotected=Number((await client.query("select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity")).rows[0].count);
 if(unprotected!==0)throw Error('RLS invariant failed');
 await client.query('insert into public._applied_scripts(name) values($1)',[name]);
 await client.query("notify pgrst,'reload schema'");
 await client.query('commit');
 Object.assign(report,{committed:true,academicIntegrityUnchanged:true,unprotectedTables:unprotected,integrity:after,completedAt:new Date().toISOString()});
 fs.writeFileSync(path.join(backup,'migration-result.json'),JSON.stringify(report,null,2));
 const output=path.join(ROOT_DIR,'backend/stress-results/2026-10-20/fixes/render/roles');fs.mkdirSync(output,{recursive:true});
 fs.writeFileSync(path.join(output,'supabase-update.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({committed:true,migration:name,academicIntegrityUnchanged:true,unprotectedTables:unprotected,backup}));
} catch(error) {await client.query('rollback').catch(()=>{});throw error;}
finally {await client.end();}
