// Copy authorized application rows into a disposable loopback database. Remote
// access is READ ONLY; personal rows are never written to the report/repository.
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {database,asUser} from '../../test/helpers/database.mjs';
const require=createRequire(import.meta.url),{Client}=require('pg');
if(!process.argv.includes('--copy-authorized-production-data'))throw Error('Explicit dataset opt-in required');
const e=require('dotenv').parse(fs.readFileSync(path.resolve(import.meta.dirname,'../../.env')));
const remote=new Client({host:e.SUPABASE_DB_HOST,port:Number(e.SUPABASE_DB_PORT),user:e.SUPABASE_DB_USER,password:e.SUPABASE_DB_PASSWORD,database:e.SUPABASE_DB_NAME||'postgres',ssl:{rejectUnauthorized:false},connectionTimeoutMillis:10000});
const result={at:new Date().toISOString(),scope:'disposable local PostgreSQL with production rows',tables:0,cases:[]};
let local;
const quote=s=>'"'+s.replaceAll('"','""')+'"';
try {
 await remote.connect();await remote.query('begin read only');
 local=await database({through:'0053_backend_readiness.sql'});
 const tables=(await local.admin.query("select c.relname,array_agg(a.attname::text order by a.attnum) columns from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid where n.nspname='public' and c.relkind='r' and a.attnum>0 and not a.attisdropped and a.attgenerated='' group by c.relname order by c.relname")).rows;
 await local.admin.query('set session_replication_role=replica');
 await local.admin.query('truncate '+tables.map(t=>'public.'+quote(t.relname)).join(',')+' cascade');
 for(const table of tables) {
  const cols=table.columns.map(quote).join(','),name='public.'+quote(table.relname);
  const rows=(await remote.query(`select coalesce(jsonb_agg(t),'[]') data from (select ${cols} from ${name}) t`)).rows[0].data;
  if(rows.length)await local.admin.query(`insert into ${name}(${cols}) select ${cols} from jsonb_populate_recordset(null::${name},$1::jsonb)`,[JSON.stringify(rows)]);
  result.tables++;
 }
 const auth=(await remote.query('select distinct auth_user_id id from public.users where auth_user_id is not null')).rows;
 for(const row of auth)await local.admin.query('insert into auth.users(id) values($1) on conflict do nothing',[row.id]);
 await local.admin.query('set session_replication_role=origin');await local.admin.query('analyze');
 await remote.query('rollback');await remote.end();
 const cases=[];
 for(const id of [11,12,13,55,5,3,2,4]) {
  const user=(await local.admin.query('select id,auth_user_id,institution_id,person_id from users where id=$1 and active',[id])).rows[0];
  const role=id===11||id===5?'admin':id===12||id===3?'teacher':id===13||id===2?'student':'parent';
  let student=null;
  if(role==='student')student=(await local.admin.query('select id from students where person_id=$1 and institution_id=$2',[user.person_id,user.institution_id])).rows[0]?.id;
  if(role==='parent')student=(await local.admin.query('select ps.student_id id from parent_students ps join parents p on p.id=ps.parent_id where p.person_id=$1 and p.institution_id=$2 order by ps.student_id limit 1',[user.person_id,user.institution_id])).rows[0]?.id;
  if((role==='student'||role==='parent')&&!student)continue;
  const client=await local.connect();await asUser(client,user.auth_user_id,user.institution_id);
  await client.query("set statement_timeout='40s'");
  cases.push({client,role,institution:user.institution_id,student});
 }
 for(const phase of ['before','after']) {
  if(phase==='after')await local.admin.query(fs.readFileSync(path.resolve(import.meta.dirname,'../../../supabase/migrations/0054_batched_academic_rls.sql'),'utf8'));
  for(const item of cases) {
   const t=performance.now();
   const doc=(await item.client.query('select assignment_feed(p_student_id=>$1,p_limit=>20) result',[item.student])).rows[0].result;
   const row={phase,role:item.role,institution:item.institution,ms:performance.now()-t,count:doc.assignments.length,hash:createHash('sha256').update(JSON.stringify(doc)).digest('hex')};
   result.cases.push(row);console.log(JSON.stringify(row));
  }
 }
 for(const row of result.cases.filter(r=>r.phase==='before')) {
  const after=result.cases.find(r=>r.phase==='after'&&r.role===row.role&&r.institution===row.institution);
  if(row.hash!==after.hash)throw Error('Feed output changed for '+row.role+'/'+row.institution);
 }
 result.identicalOutputs=true;
} finally {
 await remote.end().catch(()=>{});if(local)await local.close();
 const out=path.resolve(import.meta.dirname,'../../stress-results/2026-10-20/fixes');fs.mkdirSync(out,{recursive:true});
 fs.writeFileSync(path.join(out,'local-rls-benchmark.json'),JSON.stringify(result,null,2));
}
