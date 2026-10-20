import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {before,after,afterEach,test} from 'node:test';
import {database,asUser} from './helpers/database.mjs';
let db;
before(async()=>{db=await database();},{timeout:120000});
afterEach(async()=>{if(db)await db.release();});
after(async()=>{if(db)await db.close();});
async function fixture() {
 const q=(sql,args)=>db.admin.query(sql,args);
 const inst=(await q("insert into institutions(code,name) values($1,'Assignment fixture') returning id",[randomUUID()])).rows[0].id;
 async function user(role) {
  const person=(await q("insert into persons(institution_id,first_name,last_name) values($1,$2,'Fixture') returning id",[inst,role])).rows[0].id;
  const auth=randomUUID();await q('insert into auth.users(id) values($1)',[auth]);
  const id=(await q('insert into users(institution_id,person_id,auth_user_id,email,full_name) values($1,$2,$3,$4,$5) returning id',[inst,person,auth,auth+'@fixture.invalid',role])).rows[0].id;
  await q('insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code=$3 order by id limit 1',[inst,id,role]);
  return {id,person,auth};
 }
 const owner=await user('teacher'),collaborator=await user('teacher'),parent=await user('parent'),studentUser=await user('student');
 const teacher=(await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[inst,owner.person])).rows[0].id;
 const collaboratorTeacher=(await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[inst,collaborator.person])).rows[0].id;
 const parentId=(await q('insert into parents(institution_id,person_id) values($1,$2) returning id',[inst,parent.person])).rows[0].id;
 const student=(await q('insert into students(institution_id,person_id) values($1,$2) returning id',[inst,studentUser.person])).rows[0].id;
 await q('insert into parent_students(parent_id,student_id) values($1,$2)',[parentId,student]);
 const year=(await q("insert into academic_years(institution_id,name,year,is_current) values($1,'2026',2026,true) returning id",[inst])).rows[0].id;
 const group=(await q("insert into groups(institution_id,academic_year_id,name) values($1,$2,'A') returning id",[inst,year])).rows[0].id;
 const cls=(await q('insert into classes(institution_id,academic_year_id,group_id,teacher_id) values($1,$2,$3,$4) returning id',[inst,year,group,teacher])).rows[0].id;
 const otherClass=(await q('insert into classes(institution_id,academic_year_id,group_id,teacher_id) values($1,$2,$3,$4) returning id',[inst,year,group,collaboratorTeacher])).rows[0].id;
 await q("insert into enrollments(institution_id,student_id,group_id,academic_year_id,enrollment_status_id) select $1,$2,$3,$4,id from catalog_enrollment_statuses where code='ACT'",[inst,student,group,year]);
 const file=(await q("insert into files(institution_id,original_name,uploaded_by) values($1,'fixture.txt',$2) returning id",[inst,owner.id])).rows[0].id;
 async function connect(actor=owner,scope=inst) {const c=await db.connect();await asUser(c,actor.auth,scope);return c;}
 const client=await connect();
 const payload={class_id:cls,title:'Task',due_at:'2026-11-01T12:00:00Z',max_score:100,published:false,allow_late:false};
 return {inst,owner,collaborator,parent,studentUser,student,cls,otherClass,file,client,connect,payload,q};
}
async function write(f,{client=f.client,id=null,data=f.payload,files=[],key=randomUUID()}={}) {
 return (await client.query('select assignment_write($1,$2::jsonb,$3::bigint[],$4) result',[id,JSON.stringify(data),files,key])).rows[0].result;
}
test('batched class grants equal existing row grants and observe live collaborator revocation',async()=>{
 const f=await fixture(),c=await f.connect(f.collaborator);
 const grant=(await f.q("insert into class_collaborators(institution_id,class_id,teacher_id,teacher_user_id,status,permissions,invited_by) select $1,$2,id,$3,'active',array['class.view','assignments.create'],$5 from teachers where person_id=$4 returning id",[f.inst,f.cls,f.collaborator.id,f.collaborator.person,f.owner.id])).rows[0].id;
 for(const permission of ['class.view','assignments.create','students.view','assignments.review','collaborators.manage']) {
  const expected=(await c.query('select id from classes where institution_id=$1 and class_permission(id,$2) order by id',[f.inst,permission])).rows.map(r=>r.id);
  const actual=(await c.query('select unnest(class_permission_ids($1)) id order by id',[permission])).rows.map(r=>r.id);
  assert.deepEqual(actual,expected);
 }
 const task=await write(f);assert.ok((await c.query('select id from assignments where id=$1',[task.id])).rows.length);
 await f.q("update class_collaborators set status='revoked' where id=$1",[grant]);
 assert.equal((await c.query('select id from assignments where id=$1',[task.id])).rows.length,0);
 await assert.rejects(write(f,{client:c,id:task.id}),{code:'42501'});
});
test('family scope, tenant isolation and optional MFA remain enforced by direct RLS',async()=>{
 const f=await fixture(),task=await write(f,{data:{...f.payload,published:true}}),parent=await f.connect(f.parent);
 const feed=(await parent.query('select assignment_feed(p_student_id=>$1) result',[f.student])).rows[0].result;
 assert.ok(feed.assignments.some(a=>a.id===task.id));
 assert.equal((await (await f.connect(f.parent,999999)).query('select id from assignments')).rows.length,0);
 await f.q('insert into auth_two_factor_settings(user_id,enabled) values($1,true)',[f.parent.id]);
 assert.equal((await parent.query('select id from assignments')).rows.length,0);
 await f.q('update auth_two_factor_settings set enabled=false where user_id=$1',[f.parent.id]);
 assert.ok((await parent.query('select id from assignments where id=$1',[task.id])).rows.length);
 await assert.rejects(write(f,{client:parent}),{code:'42501'});
});
test('batched grants retain limited administrative permissions and independent teacher grants',async()=>{
 const f=await fixture();
 await f.q("insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code='admin' order by id limit 1",[f.inst,f.owner.id]);
 await f.q("update users set admin_permissions=array['dashboard.view'] where id=$1",[f.owner.id]);
 for(const permission of ['class.view','students.view','assignments.create','grades.write','unknown']) {
  const expected=(await f.client.query('select id from classes where institution_id=$1 and class_permission(id,$2) order by id',[f.inst,permission])).rows.map(r=>r.id);
  const actual=(await f.client.query('select unnest(class_permission_ids($1)) id order by id',[permission])).rows.map(r=>r.id);
  assert.deepEqual(actual,expected);
 }
 const task=await write(f);assert.ok(task.id);
 await assert.rejects(write(f,{data:{...f.payload,class_id:f.otherClass}}),{code:'42501'});
});
test('task creation and its document replay atomically under concurrent duplicate requests',async()=>{
 const f=await fixture(),key=randomUUID(),a=await f.connect(),b=await f.connect();
 const results=await Promise.all([write(f,{client:a,key,files:[f.file]}),write(f,{client:b,key,files:[f.file]})]);
 assert.deepEqual(results[0],results[1]);assert.equal(results[0].attachments.length,1);
 assert.equal(results[0].totalStudents,1);
 assert.equal((await f.q('select count(*) from assignments where institution_id=$1',[f.inst])).rows[0].count,'1');
 await assert.rejects(write(f,{key,files:[f.file],data:{...f.payload,title:'Different'}}),{code:'23505'});
});
test('invalid attachment or class move cannot partially update a task; empty attachments replace links',async()=>{
 const f=await fixture(),task=await write(f,{files:[f.file]});
 await assert.rejects(write(f,{id:task.id,data:{...f.payload,title:'Must roll back'},files:[99999999]}),{code:'42501'});
 assert.equal((await f.q('select title from assignments where id=$1',[task.id])).rows[0].title,'Task');
 assert.equal((await write(f,{id:task.id,files:null})).attachments.length,1);
 assert.equal((await write(f,{id:task.id,files:[]})).attachments.length,0);
 await assert.rejects(write(f,{id:task.id,data:{...f.payload,class_id:f.otherClass}}),{code:'42501'});
 assert.equal((await f.q('select class_id from assignments where id=$1',[task.id])).rows[0].class_id,f.cls);
});
test('timeout while confirming the document rolls back the task and operation receipt',async()=>{
 const f=await fixture(),key=randomUUID();
 await f.q(`create function public.test_assignment_timeout() returns trigger language plpgsql as $$ begin
 if new.operation='assignment_write' and new.response is not null then raise exception 'Fixture timeout' using errcode='57014'; end if;
 return new;end $$;create trigger test_assignment_timeout before update on api_write_receipts for each row execute function test_assignment_timeout()`);
 try {
  await assert.rejects(write(f,{key,files:[f.file]}),{code:'57014'});
  assert.equal((await f.q('select count(*) from assignments where institution_id=$1',[f.inst])).rows[0].count,'0');
  assert.equal((await f.q('select count(*) from api_write_receipts where institution_id=$1',[f.inst])).rows[0].count,'0');
 } finally {await f.q('drop trigger test_assignment_timeout on api_write_receipts;drop function test_assignment_timeout()');}
 assert.ok((await write(f,{key,files:[f.file]})).id);
});
test('collaborator task document does not disclose roster or review counts without grants',async()=>{
 const f=await fixture(),c=await f.connect(f.collaborator);
 await f.q("insert into class_collaborators(institution_id,class_id,teacher_id,teacher_user_id,status,permissions,invited_by) select $1,$2,id,$3,'active',array['class.view','assignments.create'],$5 from teachers where person_id=$4",[f.inst,f.cls,f.collaborator.id,f.collaborator.person,f.owner.id]);
 const task=await write(f,{client:c});
 assert.equal(task.totalStudents,0);assert.equal(task.submittedCount,0);
});
test('large task reads evaluate class scope as an InitPlan, not once per task',async()=>{
 const f=await fixture();
 await f.q("insert into assignments(institution_id,class_id,title,published) select $1,$2,'Bulk '||n,false from generate_series(1,300) n",[f.inst,f.cls]);
 const plan=(await f.client.query('explain (analyze,verbose,format json) select id from assignments where institution_id=$1',[f.inst])).rows[0]['QUERY PLAN'][0].Plan;
 const nodes=[];function visit(n){nodes.push(n);for(const c of n.Plans??[])visit(c);}visit(plan);
 const scope=nodes.filter(n=>n['Subplan Name']?.startsWith('InitPlan')&&n.Output?.some(s=>s.includes('class_permission_ids')));
 assert.ok(scope.length>0);assert.ok(scope.every(n=>n['Actual Loops']<=1));assert.equal(plan['Actual Rows'],300);
});
