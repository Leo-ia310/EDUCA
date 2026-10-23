import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { before, after, afterEach, test } from 'node:test';
import { database } from './helpers/database.mjs';
let db;
before(async () => { db = await database(); }, { timeout: 120000 });
after(async () => { if (db) await db.close(); });
afterEach(async () => {
  if (!db) return;
  await db.admin.query("update originality_jobs set finished_at=clock_timestamp() where finished_at is null; update originality_consumer set lock_token=null,lease_until=null");
});
const q = async (sql,args=[]) => (await db.admin.query(sql,args)).rows;
async function fixture() {
  const inst = (await q("insert into institutions(code,name) values($1,'Edge test') returning id",[randomUUID()]))[0].id;
  const person = async name => (await q("insert into persons(institution_id,first_name,last_name) values($1,$2,'Fixture') returning id",[inst,name]))[0].id;
  const teacher = (await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[inst,await person('Teacher')]))[0].id;
  const year = (await q("insert into academic_years(institution_id,name,year,is_current) values($1,'2026',2026,true) returning id",[inst]))[0].id;
  const group = (await q("insert into groups(institution_id,academic_year_id,name) values($1,$2,'A') returning id",[inst,year]))[0].id;
  const cls = (await q('insert into classes(institution_id,academic_year_id,group_id,teacher_id) values($1,$2,$3,$4) returning id',[inst,year,group,teacher]))[0].id;
  const assignment = (await q("insert into assignments(institution_id,class_id,title,published,allow_late) values($1,$2,'Essay',true,true) returning id",[inst,cls]))[0].id;
  const student = (await q('insert into students(institution_id,person_id) values($1,$2) returning id',[inst,await person('Student')]))[0].id;
  await q("insert into enrollments(institution_id,student_id,group_id,academic_year_id,enrollment_status_id) select $1,$2,$3,$4,id from catalog_enrollment_statuses where code='ACT' limit 1",[inst,student,group,year]);
  const submission = (await q("insert into submissions(institution_id,assignment_id,student_id,student_notes,submitted_at,task_status_id) select $1,$2,$3,'synthetic notes',clock_timestamp(),id from catalog_task_statuses where code='ENTR' returning id",[inst,assignment,student]))[0].id;
  return { inst, assignment, submission };
}
const claim = async () => (await q('select originality_edge_claim() job'))[0].job;
const pause = (job, state={stage:'prepare',version:'nivra-1-n5-m40',text:'private synthetic draft'}) =>
  q('select originality_edge_yield($1,$2,$3::jsonb)',[job.id,job.lock_token,JSON.stringify(state)]);

test('many clean yields persist private progress without exhausting attempts; stale fences never write', async () => {
  await fixture(); let job = await claim(); const first = job;
  for(let i=0;i<8;i++) {
    assert.equal(job.attempts,1); await pause(job); job=await claim();
    assert.equal(job.checkpoint.text,'private synthetic draft');
  }
  assert.notEqual(job.lock_token,first.lock_token);
  await assert.rejects(pause(first),/lease_lost/);
  assert.equal((await q('select state,academic from originality_documents where id=$1',[job.document_id]))[0].state,'processing');
  assert.equal((await q('select count(*) n from originality_pairs'))[0].n,'0');
  assert.equal((await q('select academic from originality_documents where id=$1',[job.document_id]))[0].academic,null);
});

test('global lease excludes overlapping Node and Edge consumers; crashes still exhaust bounded retries and purge checkpoints', async () => {
  await fixture(); let job=await claim(); await pause(job); job=await claim();
  assert.equal((await q('select originality_claim() job'))[0].job,null);
  assert.equal(await claim(),null);
  for(let attempt=2;attempt<=3;attempt++) {
    await q("update originality_jobs set lease_until=clock_timestamp()-interval '1 second' where id=$1;",[job.id]);
    await q("update originality_consumer set lease_until=clock_timestamp()-interval '1 second'");
    job=await claim(); assert.equal(job.attempts,attempt);
  }
  await q("update originality_jobs set lease_until=clock_timestamp()-interval '1 second' where id=$1",[job.id]);
  await q("update originality_consumer set lease_until=clock_timestamp()-interval '1 second'");
  assert.equal(await claim(),null);
  assert.equal((await q('select state from originality_documents where id=$1',[job.document_id]))[0].state,'failed');
  assert.equal((await q('select count(*) n from originality_edge_state where job_id=$1',[job.id]))[0].n,'0');
});

test('retiring a version or deleting an assignment immediately removes raw checkpoint text', async () => {
  const f=await fixture(); const job=await claim(); await pause(job);
  await q("update assignments set deleted_at=clock_timestamp() where id=$1",[f.assignment]);
  assert.equal((await q('select count(*) n from originality_edge_state where job_id=$1',[job.id]))[0].n,'0');
  assert.equal(await claim(),null);
  const g=await fixture(); const other=await claim(); await pause(other);
  await q("update submissions set student_notes='a new revision' where id=$1",[g.submission]);
  assert.equal((await q('select count(*) n from originality_edge_state where job_id=$1',[other.id]))[0].n,'0');
});

test('finish is atomic, removes its checkpoint and rejects invalid pairs without publishing partial results', async () => {
  await fixture(); let job=await claim(); await pause(job); job=await claim();
  const result={state:'insufficient_text',binaryHash:null,textHash:'synthetic',academic:null,fingerprints:[],algorithmVersion:'nivra-1-n5-m40',durationMs:1};
  await assert.rejects(q('select originality_edge_finish($1,$2,$3,$4)',[job.id,job.lock_token,result,JSON.stringify([{otherId:999999}])]),/invalid_pair/);
  assert.equal((await q('select state from originality_documents where id=$1',[job.document_id]))[0].state,'processing');
  assert.equal((await q('select count(*) n from originality_edge_state where job_id=$1',[job.id]))[0].n,'1');
  assert.equal((await q('select originality_edge_finish($1,$2,$3,$4) ok',[job.id,job.lock_token,result,JSON.stringify([])]))[0].ok,true);
  assert.equal((await q('select count(*) n from originality_edge_state where job_id=$1',[job.id]))[0].n,'0');
  assert.equal((await q('select state from originality_documents where id=$1',[job.document_id]))[0].state,'insufficient_text');
});

test('privileged checkpoint RPCs and tables deny both browser roles; malformed state cannot extend work', async () => {
  await fixture(); const job=await claim();
  await assert.rejects(pause(job,{stage:null}),/invalid_checkpoint/);
  const c=await db.connect();
  try {
    for(const role of ['anon','authenticated']) {
      await c.query('set role '+role);
      await assert.rejects(c.query('select * from originality_edge_state'),/permission denied/);
      for(const name of ['originality_edge_claim','originality_edge_reconcile'])await assert.rejects(c.query('select '+name+'()'),/permission denied/);
      await c.query('reset role');
    }
  } finally { await c.end(); }
});

test('reconciliation cursor survives invocations and throttles only after a complete traversal', async () => {
  await fixture(); await q("update originality_edge_control set after_id=0,reconcile_at='epoch'");
  const cursor=(await q('select originality_edge_reconcile() after'))[0].after; assert.ok(Number(cursor)>0);
  assert.equal((await q('select originality_edge_reconcile() after'))[0].after,null);
  await q("update originality_edge_control set reconcile_at='epoch'");
  assert.equal((await q('select originality_edge_reconcile() after'))[0].after,'0');
  assert.equal((await q('select after_id from originality_edge_control'))[0].after_id,'0');
});

test('0059 rollback preserves 0058 queue and original academic data', async () => {
  await fixture(); const job=await claim(); await pause(job);
  await db.admin.query(await readFile(new URL('../../supabase/rollback/0059_nivra_originality_edge.sql',import.meta.url),'utf8'));
  assert.equal((await q("select to_regclass('originality_edge_state') name"))[0].name,null);
  assert.ok((await q('select originality_claim() job'))[0].job);
  for(const table of ['submissions','files','assignments','originality_documents'])assert.ok((await q('select to_regclass($1) name',[table]))[0].name);
});
