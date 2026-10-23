import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, after, afterEach, test } from 'node:test';
import { tsImport } from 'tsx/esm/api';
import { database, asUser } from './helpers/database.mjs';
const { prepareText, compareTexts } = await tsImport('../src/modules/assignments/originality/domain.ts', import.meta.url);
let db;
before(async () => { db = await database(); }, { timeout: 120000 });
afterEach(async () => { if (db) { await db.admin.query('update originality_consumer set lease_until=null,lock_token=null; update originality_jobs set finished_at=clock_timestamp() where finished_at is null'); await db.release(); } });
after(async () => { if (db) await db.close(); });
const body = Array.from({ length: 80 }, (_, i) => `word${i}`).join(' ');
const version = 'nivra-1-n5-m40';
async function fixture(count = 2) {
 const q = async (sql,args=[]) => (await db.admin.query(sql,args)).rows;
 const inst = (await q("insert into institutions(code,name) values($1,'Originality fixture') returning id", [randomUUID()]))[0].id;
 async function person(name) { return (await q("insert into persons(institution_id,first_name,last_name) values($1,$2,'Fixture') returning id",[inst,name]))[0].id; }
 async function actor(role) {
  const pid=await person(role), auth=randomUUID(); await q('insert into auth.users(id) values($1)',[auth]);
  const id=(await q('insert into users(institution_id,person_id,auth_user_id,email,full_name) values($1,$2,$3,$4,$5) returning id',[inst,pid,auth,auth+'@fixture.invalid',role]))[0].id;
  await q('insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code=$3 order by id limit 1',[inst,id,role]);
  return {id,pid,auth};
 }
 const owner=await actor('teacher'), outsider=await actor('teacher'), learner=await actor('student');
 const teacher=(await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[inst,owner.pid]))[0].id;
 const otherTeacher=(await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[inst,outsider.pid]))[0].id;
 const year=(await q("insert into academic_years(institution_id,name,year,is_current) values($1,'2026',2026,true) returning id",[inst]))[0].id;
 const group=(await q("insert into groups(institution_id,academic_year_id,name) values($1,$2,'A') returning id",[inst,year]))[0].id;
 const cls=(await q('insert into classes(institution_id,academic_year_id,group_id,teacher_id) values($1,$2,$3,$4) returning id',[inst,year,group,teacher]))[0].id;
 const assignment=(await q("insert into assignments(institution_id,class_id,title,published,allow_late,due_at) values($1,$2,'Essay',true,true,clock_timestamp()+interval '1 day') returning id",[inst,cls]))[0].id;
 const students=[];
 for(let i=0;i<count;i++) {
  const pid=i===0?learner.pid:await person('Student '+i);
  const student=(await q('insert into students(institution_id,person_id) values($1,$2) returning id',[inst,pid]))[0].id;
  students.push(student);
  await q("insert into enrollments(institution_id,student_id,group_id,academic_year_id,enrollment_status_id) select $1,$2,$3,$4,id from catalog_enrollment_statuses where code='ACT' limit 1",[inst,student,group,year]);
 }
 async function connect(user=owner,scope=inst) { const c=await db.connect();await asUser(c,user.auth,scope);return c; }
 async function submit(i,text=body) { return (await q("insert into submissions(institution_id,assignment_id,student_id,student_notes,submitted_at,task_status_id) select $1,$2,$3,$4,'2000-01-01',id from catalog_task_statuses where code='ENTR' returning id,submitted_at",[inst,assignment,students[i],text]))[0]; }
 async function doc(s) { return (await q('select * from originality_documents where submission_id=$1 and active order by id',[s.id]))[0]; }
 return {q,inst,owner,outsider,learner,otherTeacher,year,group,cls,assignment,students,connect,submit,doc};
}
async function finish(f,job,text, pairs=[]) {
 const academic=prepareText(text);
 await f.q('select originality_finish($1,$2,$3::jsonb,$4::jsonb)',[job.id,job.lock_token,JSON.stringify({state:'completed',academic,fingerprints:academic.fingerprints,textHash:academic.textHash,binaryHash:null,algorithmVersion:version,durationMs:1}),JSON.stringify(pairs)]);
}
async function claim(f) {return (await f.q('select originality_claim() job'))[0].job;}
async function drain(f) {
 let job;
 while((job=await claim(f))) {
  const d=(await f.q('select * from originality_documents where id=$1',[job.document_id]))[0],a=prepareText(d.source_notes);
  const candidates=[];let after=0;
  while(true){
   const page=await f.q('select * from originality_candidates($1,null,$2,$3,$4,$5)',[d.id,a.textHash,a.fingerprints,after,version]);
   if(!page.length)break;candidates.push(page[0]);after=page[0].id;
  }
  const pairs=candidates.map(c=>({otherId:c.id,...compareTexts(a,c.academic),binaryIdentical:false})).filter(p=>p.aCoverage>0);
  await finish(f,job,d.source_notes,pairs);
 }
}
test('durable capture is idempotent, timestamp is DB UTC, lease is globally serial and recoverable', async()=>{
 const f=await fixture(),s=await f.submit(0),d=await f.doc(s);
 assert.ok(new Date(s.submitted_at).getUTCFullYear()>=2026);
 await f.q('select originality_capture($1)',[s.id]);
 assert.equal((await f.q('select count(*) n from originality_documents where submission_id=$1',[s.id]))[0].n,'1');
 const job=await claim(f);assert.equal(job.document_id,Number(d.id));assert.equal(await claim(f),null);
 await f.q("select originality_fail($1,$2,'extraction_timeout')",[job.id,job.lock_token]);
 assert.equal(await claim(f),null);
 await f.q("update originality_jobs set available_at=clock_timestamp() where id=$1",[job.id]);
 const retry=await claim(f);assert.equal(retry.attempts,2);assert.notEqual(retry.lock_token,job.lock_token);
 await assert.rejects(f.q('select originality_finish($1,$2,$3,$4)',[job.id,job.lock_token,'{}','[]']),/lease_lost/);
 await f.q("update originality_consumer set lease_until=clock_timestamp()-interval '1 second'");
 await f.q("update originality_jobs set lease_until=clock_timestamp()-interval '1 second' where id=$1",[job.id]);
 const recovered=await claim(f);assert.equal(recovered.attempts,3);
 await f.q("select originality_fail($1,$2,'analysis_unavailable')",[recovered.id,recovered.lock_token]);
 const c=await f.connect();await c.query('select originality_report($1,false,true)',[s.id]);
 const reset=await claim(f);assert.equal(reset.attempts,1);await finish(f,reset,body);
});
test('40 learners: delivery 39 matches 1, updates both reports; max and ties are deterministic', async()=>{
 const f=await fixture(40),subs=[];
 for(let i=0;i<40;i++)subs.push(await f.submit(i,i===0||i===38||i===39?body:Array.from({length:80},(_,j)=>`student${i}word${j}`).join(' ')));
 await drain(f);
 const c=await f.connect();
 const report=(await c.query('select originality_report($1,true) result',[subs[0].id])).rows[0].result;
 const source=await f.doc(subs[38]);
 assert.equal(report.documents[0].topMatch.coverage,100);
 assert.equal(report.documents[0].topMatch.sourceId,Number(source.id));
 assert.ok(report.documents[0].topMatch.fragments[0].text.startsWith('word0'));
 const reverse=(await c.query('select originality_report($1,false) result',[subs[38].id])).rows[0].result;
 assert.equal(reverse.documents[0].topMatch.coverage,100);
 assert.equal((await f.q('select count(*) n from originality_pairs where a_id=$1',[Number((await f.doc(subs[0])).id)]))[0].n,'2');
 assert.equal((await f.q('select count(*) n from originality_jobs where finished_at is null and document_id in (select id from originality_documents where institution_id=$1)',[f.inst]))[0].n,'0');
});
test('versions invalidate old pairs, first document is not exempt, empty candidates are not 0%',async()=>{
 const f=await fixture(),a=await f.submit(0);await drain(f);
 const c=await f.connect();let report=(await c.query('select originality_report($1,false) result',[a.id])).rows[0].result;
 assert.equal(report.documents[0].compared,false);assert.equal(report.documents[0].topMatch,null);
 await f.submit(1);await drain(f);
 report=(await c.query('select originality_report($1,false) result',[a.id])).rows[0].result;assert.equal(report.documents[0].topMatch.coverage,100);
 const old=await f.doc(a);
 await f.q('update submissions set student_notes=$2 where id=$1',[a.id,body+' revised']);await drain(f);
 assert.notEqual((await f.doc(a)).id,old.id);
 assert.equal((await f.q('select active from originality_documents where id=$1',[old.id]))[0].active,false);
 await f.q('update assignments set deleted_at=clock_timestamp() where id=$1',[f.assignment]);
 await f.q('select originality_reconcile()');
 assert.equal((await f.q('select count(*) n from originality_documents where assignment_id=$1',[f.assignment]))[0].n,'0');
});
test('same-assignment/tenant candidate isolation and live role/class grants protect evidence and retries',async()=>{
 const f=await fixture(),g=await fixture(),s=await f.submit(0);await g.submit(0);await drain(f);
 const d=await f.doc(s),academic=prepareText(body);
 const candidates=await f.q('select * from originality_candidates($1,null,$2,$3,0,$4)',[d.id,academic.textHash,academic.fingerprints,version]);assert.equal(candidates.length,0);
 const owner=await f.connect(),outsider=await f.connect(f.outsider),student=await f.connect(f.learner),foreign=await f.connect(f.owner,g.inst);
 for(const c of [outsider,student,foreign])await assert.rejects(c.query('select originality_report($1,true,true)',[s.id]),{code:'42501'});
 for(const table of ['originality_documents','originality_pairs','originality_jobs'])await assert.rejects(student.query('select * from '+table),{code:'42501'});
 await assert.rejects(student.query('select originality_claim()'),{code:'42501'});
 assert.ok((await owner.query('select originality_report($1,true)',[s.id])).rows.length);
 await f.q("insert into class_collaborators(institution_id,class_id,teacher_id,teacher_user_id,status,permissions,invited_by) values($1,$2,$3,$4,'active',array['class.view','assignments.review'],$5)",[f.inst,f.cls,f.otherTeacher,f.outsider.id,f.owner.id]);
 await assert.rejects(outsider.query('select originality_report($1,true)',[s.id]),{code:'42501'});
 await f.q("update class_collaborators set permissions=array['class.view','assignments.review','students.view'] where class_id=$1",[f.cls]);
 assert.ok((await outsider.query('select originality_report($1,true)',[s.id])).rows.length);
 await assert.rejects(f.q("update class_collaborators set permissions=array['assignments.review','students.view'] where class_id=$1",[f.cls]),{code:'23514'});
 await f.q("update class_collaborators set status='revoked' where class_id=$1",[f.cls]);
 await assert.rejects(outsider.query('select originality_report($1,true)',[s.id]),{code:'42501'});
});
test('atomic submission replaces links, replays same content and rejects a peer file without partial writes',async()=>{
 const f=await fixture(),student=await f.connect(f.learner);
 const file=(await f.q("insert into files(institution_id,original_name,uploaded_by) values($1,'one.txt',$2) returning id",[f.inst,f.learner.id]))[0].id;
 const peer=(await f.q("insert into files(institution_id,original_name,uploaded_by) values($1,'peer.txt',$2) returning id",[f.inst,f.owner.id]))[0].id;
 const submit=async(notes,files)=>(await student.query('select assignment_submit($1,$2,$3,$4) result',[f.assignment,f.students[0],notes,files])).rows[0].result;
 const first=await submit(body,[file]);const d=await f.doc(first);
 await submit(body,[file]);assert.equal((await f.doc(first)).id,d.id);
 await submit(body+' notes only',null);
 assert.equal((await f.q('select count(*) n from submission_files where submission_id=$1',[first.id]))[0].n,'1');
 const retained=await f.doc(first);
 await assert.rejects(submit('must roll back',[peer]),{code:'42501'});
 assert.equal((await f.doc(first)).id,retained.id);
 await submit(body+' changed',[]);
 assert.equal((await f.q('select count(*) n from submission_files where submission_id=$1',[first.id]))[0].n,'0');
 assert.equal((await f.q('select count(*) n from originality_documents where submission_id=$1 and active',[first.id]))[0].n,'1');
 await f.q('update files set deleted_at=clock_timestamp() where id=$1',[file]);
 assert.equal((await f.q('select count(*) n from originality_documents where file_id=$1',[file]))[0].n,'0');
});
test('withdrawal immediately hides a source and reactivation safely requeues the current revision',async()=>{
 const f=await fixture(),a=await f.submit(0),b=await f.submit(1);await drain(f);const c=await f.connect();
 await f.q('update students set active=false where id=$1',[f.students[1]]);
 let report=(await c.query('select originality_report($1,true) result',[a.id])).rows[0].result;
 assert.equal(report.documents[0].topMatch,null);assert.equal(report.documents[0].compared,false);
 await f.q('select originality_capture($1)',[b.id]);
 assert.equal((await f.q('select academic from originality_documents where submission_id=$1',[b.id]))[0].academic,null);
 await f.q('update students set active=true where id=$1',[f.students[1]]);await f.q('select originality_capture($1)',[b.id]);await drain(f);
 report=(await c.query('select originality_report($1,true) result',[a.id])).rows[0].result;assert.equal(report.documents[0].topMatch.coverage,100);
});
test('identical binary evidence is available without assigning a text percentage to insufficient samples',async()=>{
 const f=await fixture(),a=await f.submit(0);await f.submit(1);
 const result=JSON.stringify({state:'insufficient_text',academic:null,fingerprints:[],textHash:null,binaryHash:'same-binary-hash',algorithmVersion:version,durationMs:1});
 const first=await claim(f);await f.q('select originality_finish($1,$2,$3::jsonb,$4::jsonb)',[first.id,first.lock_token,result,'[]']);
 const second=await claim(f);await f.q('select originality_finish($1,$2,$3::jsonb,$4::jsonb)',[second.id,second.lock_token,result,JSON.stringify([{otherId:first.document_id,aCoverage:0,bCoverage:0,aIntervals:[],bIntervals:[],textIdentical:false,binaryIdentical:true}])]);
 const c=await f.connect(),report=(await c.query('select originality_report($1,true) result',[a.id])).rows[0].result;
 assert.equal(report.documents[0].state,'insufficient_text');assert.equal(report.documents[0].compared,false);
 assert.equal(report.documents[0].topMatch.binaryIdentical,true);
});
test('direct forged file links never enroll another learner or teacher private file into analysis',async()=>{
 const f=await fixture(),s=await f.submit(0);
 const file=(await f.q("insert into files(institution_id,original_name,uploaded_by) values($1,'private.txt',$2) returning id",[f.inst,f.owner.id]))[0].id;
 await f.q('insert into submission_files(submission_id,file_id) values($1,$2)',[s.id,file]);
 assert.equal((await f.q('select originality_source_allowed($1,$2) allowed',[s.id,file]))[0].allowed,false);
 assert.equal((await f.q('select count(*) n from originality_documents where submission_id=$1 and file_id=$2',[s.id,file]))[0].n,'0');
});
test('an unsubmitted draft stays unsubmitted and never enters the queue',async()=>{
 const f=await fixture();
 const s=(await f.q('insert into submissions(institution_id,assignment_id,student_id) values($1,$2,$3) returning id,submitted_at',[f.inst,f.assignment,f.students[0]]))[0];
 assert.equal(s.submitted_at,null);assert.equal(await f.doc(s),undefined);
});
test('a missed outbox capture keeps a closed report preliminary until reconciliation',async()=>{
 const f=await fixture(),a=await f.submit(0);await drain(f);
 await f.q("update assignments set due_at=clock_timestamp()-interval '1 day' where id=$1",[f.assignment]);
 await f.q('alter table submissions disable trigger originality_submission_capture');
 try { await f.submit(1); } finally { await f.q('alter table submissions enable trigger originality_submission_capture'); }
 const c=await f.connect();let report=(await c.query('select originality_report($1,false) result',[a.id])).rows[0].result;
 assert.equal(report.documents[0].preliminary,true);assert.equal(report.documents[0].compared,false);
 let reconciliationAfter=0;
 do { reconciliationAfter=Number((await f.q('select originality_reconcile($1) next_id',[reconciliationAfter]))[0].next_id); } while(reconciliationAfter!==0);
 await drain(f);
 report=(await c.query('select originality_report($1,false) result',[a.id])).rows[0].result;
 assert.equal(report.documents[0].preliminary,false);assert.equal(report.documents[0].topMatch.coverage,100);
});
