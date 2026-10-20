import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {before,after,afterEach,test} from 'node:test';
import {database,asUser} from './helpers/database.mjs';
let db;
before(async()=>{db=await database();},{timeout:120000});
afterEach(async()=>{if(db)await db.release();});after(async()=>{if(db)await db.close();});
async function fixture() {
 const q=(sql,args)=>db.admin.query(sql,args),tag=randomUUID().slice(0,8);
 const inst=(await q("insert into institutions(code,name) values($1,'Atomic admin fixture') returning id",['ADMIN-'+tag])).rows[0].id;
 async function user(role,name=role) {
  const person=(await q("insert into persons(institution_id,first_name,last_name) values($1,$2,'Fixture') returning id",[inst,name])).rows[0].id;
  const auth=randomUUID();await q('insert into auth.users(id) values($1)',[auth]);
  const id=(await q('insert into users(institution_id,person_id,auth_user_id,email,full_name) values($1,$2,$3,$4,$5) returning id',[inst,person,auth,auth+'@fixture.invalid',name])).rows[0].id;
  await q("insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code=$3 order by id limit 1",[inst,id,role]);
  return {id,person,auth};
 }
 const admin=await user('admin'),teacherUser=await user('teacher'),parentUser=await user('parent');
 const teacher=(await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[inst,teacherUser.person])).rows[0].id;
 const parent=(await q('insert into parents(institution_id,person_id) values($1,$2) returning id',[inst,parentUser.person])).rows[0].id;
 const studentPerson=(await q("insert into persons(institution_id,first_name,last_name) values($1,'Student','Fixture') returning id",[inst])).rows[0].id;
 const student=(await q('insert into students(institution_id,person_id) values($1,$2) returning id',[inst,studentPerson])).rows[0].id;
 await q('insert into parent_students(parent_id,student_id) values($1,$2)',[parent,student]);
 const year=(await q("insert into academic_years(institution_id,name,year,is_current) values($1,'2026',2026,true) returning id",[inst])).rows[0].id;
 const oldYear=(await q("insert into academic_years(institution_id,name,year) values($1,'2025',2025) returning id",[inst])).rows[0].id;
 async function cls(y) {
  const group=(await q("insert into groups(institution_id,name,academic_year_id) values($1,'Fixture',$2) returning id",[inst,y])).rows[0].id;
  const subject=(await q("insert into subjects(institution_id,name) values($1,'Fixture') returning id",[inst])).rows[0].id;
  return (await q('insert into classes(institution_id,group_id,subject_id,academic_year_id,teacher_id) values($1,$2,$3,$4,$5) returning id',[inst,group,subject,y,teacher])).rows[0].id;
 }
 const currentClass=await cls(year),oldClass=await cls(oldYear),client=await db.connect();await asUser(client,admin.auth,inst);
 return {inst,admin,teacher,teacherUser,parent,parentUser,student,year,oldYear,currentClass,oldClass,client};
}
async function personWrite(f,kind,id,person={},entity={},relations={}) {return (await f.client.query('select admin_person_write($1,$2,$3,$4::jsonb,$5::jsonb,$6::jsonb) result',[f.inst,kind,id,JSON.stringify(person),JSON.stringify(entity),JSON.stringify(relations)])).rows[0].result;}
async function accountWrite(f,id,changes={},roles=null){return (await f.client.query('select admin_account_write($1,$2,$3::jsonb,$4::text[]) result',[f.inst,id,JSON.stringify(changes),roles])).rows[0].result;}
test('invalid parent relations roll back person changes and retain all previous links',async()=>{
 const f=await fixture();
 await assert.rejects(personWrite(f,'parents',f.parent,{first_name:'Changed'},{},{childIds:[99999999]}),{code:'22023'});
 assert.equal((await db.admin.query('select first_name from persons where id=$1',[f.parentUser.person])).rows[0].first_name,'parent');
 assert.equal((await db.admin.query('select count(*) from parent_students where parent_id=$1',[f.parent])).rows[0].count,'1');
 await personWrite(f,'parents',f.parent,{first_name:'Saved'},{},{childIds:[]});
 assert.equal((await db.admin.query('select count(*) from parent_students where parent_id=$1',[f.parent])).rows[0].count,'0');
 assert.equal((await db.admin.query('select full_name from users where id=$1',[f.parentUser.id])).rows[0].full_name,'Saved Fixture');
});
test('teacher assignment replacement preserves historical years and rejects hidden or unauthorized classes atomically',async()=>{
 const f=await fixture();
 await personWrite(f,'teachers',f.teacher,{first_name:'New'},{},{classIds:[]});
 const rows=(await db.admin.query('select id,teacher_id from classes where institution_id=$1 order by id',[f.inst])).rows;
 assert.equal(rows.find(r=>r.id===f.oldClass).teacher_id,f.teacher);
 assert.equal(rows.find(r=>r.id===f.currentClass).teacher_id,null);
 await assert.rejects(personWrite(f,'teachers',f.teacher,{first_name:'Bad'},{},{classIds:[f.oldClass]}),{code:'22023'});
 await db.admin.query("update users set admin_permissions=array['teachers.edit'] where id=$1",[f.admin.id]);
 await assert.rejects(personWrite(f,'teachers',f.teacher,{first_name:'Denied'},{},{classIds:[f.currentClass]}),{code:'42501'});
 assert.equal((await db.admin.query('select first_name from persons where id=$1',[f.teacherUser.person])).rows[0].first_name,'New');
});
test('user changes and replacement roles share one transaction and cannot escalate platform or self privileges',async()=>{
 const f=await fixture();
 await assert.rejects(accountWrite(f,f.teacherUser.id,{full_name:'Changed'},['missing']),{code:'22023'});
 assert.equal((await db.admin.query('select full_name from users where id=$1',[f.teacherUser.id])).rows[0].full_name,'teacher');
 await assert.rejects(accountWrite(f,f.teacherUser.id,{},['super_admin']),{code:'42501'});
 await assert.rejects(accountWrite(f,f.admin.id,{},['teacher']),{code:'42501'});
 const saved=await accountWrite(f,f.teacherUser.id,{full_name:'Saved'},['teacher','parent']);
 assert.equal(saved.full_name,'Saved');assert.equal(saved.user_roles.length,2);
 await db.admin.query("update users set admin_permissions=array['roles.edit'] where id=$1",[f.admin.id]);
 await assert.rejects(accountWrite(f,f.teacherUser.id,{},['admin']),{code:'42501'});
});
test('private write helpers cannot be called through authenticated SQL and unknown fields are rejected',async()=>{
 const f=await fixture();
 await assert.rejects(f.client.query("select admin_record_write('users',$1,$2,'{}')",[f.inst,f.admin.id]),{code:'42501'});
 await assert.rejects(f.client.query("select admin_role_set($1,$2,array['super_admin'])",[f.inst,f.teacherUser.id]),{code:'42501'});
 await assert.rejects(personWrite(f,'parents',f.parent,{institution_id:999}),{code:'22023'});
});

async function scaleWrite(f,id,header,ranges,key=randomUUID()) {return (await f.client.query('select grading_scale_write($1,$2::jsonb,$3::jsonb,$4) result',[id,JSON.stringify(header),JSON.stringify(ranges),key])).rows[0].result;}
test('scale changes and ranges commit together and idempotency preserves the same scale',async()=>{
 const f=await fixture(),header={name:'Original',scale_type:'numeric',min_value:0,max_value:100,pass_value:60,decimals:2};
 const ranges=[{label:'Fail',range_min:0,range_max:59.99,passed:false},{label:'Pass',range_min:60,range_max:100,passed:true}],key=randomUUID();
 const first=await scaleWrite(f,null,header,ranges,key);assert.deepEqual(await scaleWrite(f,null,header,ranges,key),first);
 assert.equal(first.grading_scale_ranges.length,2);
 await assert.rejects(scaleWrite(f,first.id,{...header,name:'Invalid'},[{label:'Bad',range_min:0,range_max:200}]),{code:'22023'});
 await assert.rejects(scaleWrite(f,first.id,header,[{label:'A',range_min:0,range_max:60},{label:'B',range_min:60,range_max:100}]),{code:'22023'});
 assert.equal((await db.admin.query('select name from grading_scales where id=$1',[first.id])).rows[0].name,'Original');
 assert.equal((await db.admin.query('select count(*) from grading_scale_ranges where scale_id=$1',[first.id])).rows[0].count,'2');
});
async function reportFixture(f) {
 const group=(await db.admin.query('select group_id,subject_id from classes where id=$1',[f.currentClass])).rows[0];
 await db.admin.query("insert into enrollments(institution_id,student_id,group_id,academic_year_id,enrollment_status_id) values($1,$2,$3,$4,(select id from catalog_enrollment_statuses where code='ACT' limit 1))",[f.inst,f.student,group.group_id,f.year]);
 const period=(await db.admin.query("insert into academic_periods(institution_id,academic_year_id,name) values($1,$2,'Period') returning id",[f.inst,f.year])).rows[0].id;
 await db.admin.query('insert into period_grades(institution_id,student_id,class_id,subject_id,academic_period_id,final_score) values($1,$2,$3,$4,$5,70)',[f.inst,f.student,f.currentClass,group.subject_id,period]);
 return period;
}
async function reportWrite(f,period,key=randomUUID()) {return (await f.client.query('select report_card_generate($1,$2,null,$3) result',[f.student,period,key])).rows[0].result;}
test('report generation snapshots grades and persists a real year/enrollment without partial documents',async()=>{
 const f=await fixture(),period=await reportFixture(f),key=randomUUID(),first=await reportWrite(f,period,key);
 assert.equal(String(first.academic_year_id),f.year);assert.ok(first.enrollment_id);assert.equal(first.lines.length,1);assert.equal(first.overall_average,70);
 assert.deepEqual(await reportWrite(f,period,key),first);
 await db.admin.query("create function fixture_reject_report_line() returns trigger language plpgsql as $$ begin raise exception 'fixture line failure' using errcode='22023'; end $$");
 await db.admin.query('create trigger fixture_reject before insert on report_card_lines for each row execute function fixture_reject_report_line()');
 try {
  await assert.rejects(reportWrite(f,period),{code:'22023'});
  assert.equal((await db.admin.query('select count(*) from report_cards where institution_id=$1',[f.inst])).rows[0].count,'1');
 } finally {await db.admin.query('drop trigger fixture_reject on report_card_lines');await db.admin.query('drop function fixture_reject_report_line()');}
 await assert.rejects(f.client.query("insert into report_cards(institution_id,student_id) values($1,$2)",[f.inst,f.student]),{code:'42501'});
});
test('bulk charges return every ID past 1000 rows and retry without duplicates',async()=>{
 const f=await fixture(),concept=(await db.admin.query("insert into payment_concepts(institution_id,name,base_amount) values($1,'Fixture',100) returning id",[f.inst])).rows[0].id;
 const people=(await db.admin.query("insert into persons(institution_id,first_name,last_name) select $1,'Bulk '||i,'Fixture' from generate_series(1,1104) i returning id",[f.inst])).rows.map(r=>r.id);
 const students=[f.student,...(await db.admin.query('insert into students(institution_id,person_id) select $1,unnest($2::bigint[]) returning id',[f.inst,people])).rows.map(r=>r.id)];
 const rows=students.map(student=>({institution_id:f.inst,student_id:student,concept_id:concept,academic_year_id:f.year,description:'Fixture',amount:100,discount:5,late_fee:0,total_amount:95,due_at:'2026-10-31',status:'pending'}));
 const key=randomUUID(),write=async data=>(await f.client.query('select charges_create_batch($1::jsonb,$2) result',[JSON.stringify(data),key])).rows[0].result;
 const ids=await write(rows);assert.equal(ids.length,1105);assert.equal(new Set(ids).size,1105);assert.equal(typeof ids[0],'string');
 assert.deepEqual(await write(rows),ids);
 await assert.rejects(write(rows.map((r,i)=>i===0?{...r,discount:10}:r)),{code:'23505'});
 assert.equal((await db.admin.query('select count(*) from charges where institution_id=$1',[f.inst])).rows[0].count,'1105');
});

function provisionPayload(f,kind='students') {
 const email=`new-${randomUUID()}@fixture.invalid`;
 if(kind==='profile')return {roleCode:'coordinator',account:{email,full_name:'New Coordinator',active:true,admin_permissions:['roles.create']}};
 return {person:{first_name:'New',last_name:'Fixture',email},entity:kind==='students'?{student_code:'NEW-'+randomUUID()}:{},
  relations:kind==='students'?{groupId:null}:{},account:{email,full_name:'New Fixture',active:true}};
}
async function reserve(f,kind,payload,key=randomUUID(),proof='a'.repeat(64)) {return (await f.client.query('select admin_provision_begin($1,$2,$3,$4::jsonb,$5) result',[f.inst,kind,key,JSON.stringify(payload),proof])).rows[0].result;}
async function authConfirm(f,job) {await db.admin.query('insert into auth.users(id,email,raw_app_meta_data) values($1,$2,$3::jsonb)',[job.authUserId,job.email,JSON.stringify({institution_id:f.inst,provisioning_id:job.id})]);}
async function complete(f,job) {return (await f.client.query('select admin_provision_complete($1) result',[job.id])).rows[0].result;}
test('a create-only student operator provisions its fixed role atomically without roles.edit and replays completion',async()=>{
 const f=await fixture();await db.admin.query("update users set admin_permissions=array['students.create'] where id=$1",[f.admin.id]);
 await db.admin.query('update academic_years set is_current=false where institution_id=$1',[f.inst]);
 const payload=provisionPayload(f),key=randomUUID(),job=await reserve(f,'students',payload,key);
 assert.equal((await db.admin.query('select count(*) from users where auth_user_id=$1',[job.authUserId])).rows[0].count,'0');
 await assert.rejects(complete(f,job),{code:'22023'});
 await authConfirm(f,job);const result=await complete(f,job);
 assert.equal(result.entity.persons.first_name,'New');assert.equal(result.user.user_roles[0].roles.code,'student');
 assert.deepEqual(await complete(f,job),result);
 const retry=await reserve(f,'students',payload,key);assert.equal(retry.status,'completed');assert.deepEqual(retry.result,result);
 await assert.rejects(reserve(f,'students',payload,key,'b'.repeat(64)),{code:'23505'});
 const malicious=provisionPayload(f);malicious.account.admin_permissions=['roles.edit'];
 await assert.rejects(reserve(f,'students',malicious),{code:'42501'});
});
test('late account insertion failure leaves no partial person/entity and the reserved Auth identity remains recoverable',async()=>{
 const f=await fixture(),payload=provisionPayload(f);payload.account.username='provision-'+randomUUID();
 const job=await reserve(f,'students',payload);await authConfirm(f,job);
 await db.admin.query('update users set username=$1 where id=$2',[payload.account.username,f.teacherUser.id]);
 const before=(await db.admin.query('select count(*) from persons where institution_id=$1',[f.inst])).rows[0].count;
 await assert.rejects(complete(f,job),{code:'23505'});
 assert.equal((await db.admin.query('select count(*) from persons where institution_id=$1',[f.inst])).rows[0].count,before);
 assert.equal((await db.admin.query('select status from admin_provisionings where id=$1',[job.id])).rows[0].status,'pending');
 assert.equal((await db.admin.query('select count(*) from auth.users where id=$1',[job.authUserId])).rows[0].count,'1');
 await db.admin.query('update users set username=null where id=$1',[f.teacherUser.id]);
 assert.equal((await complete(f,job)).user.auth_user_id,job.authUserId);
});
test('create-only profile grants stay within the creator permissions and Auth provenance is mandatory',async()=>{
 const f=await fixture();await db.admin.query("update users set admin_permissions=array['roles.create'] where id=$1",[f.admin.id]);
 const payload=provisionPayload(f,'profile'),job=await reserve(f,'profile',payload);
 await db.admin.query('insert into auth.users(id,email,raw_app_meta_data) values($1,$2,$3::jsonb)',[job.authUserId,job.email,JSON.stringify({institution_id:f.inst,provisioning_id:randomUUID()})]);
 await assert.rejects(complete(f,job),{code:'22023'});
 await db.admin.query('update auth.users set raw_app_meta_data=$1::jsonb where id=$2',[JSON.stringify({institution_id:f.inst,provisioning_id:job.id}),job.authUserId]);
 const profile=(await complete(f,job)).user;assert.deepEqual(profile.admin_permissions,['roles.create']);
 assert.equal(profile.user_roles[0].roles.code,'coordinator');
 const elevated=provisionPayload(f,'profile');elevated.account.admin_permissions=['roles.edit'];
 await assert.rejects(reserve(f,'profile',elevated),{code:'42501'});
});
test('a confirmed external rejection retires only a missing identity; observed mismatches require review',async()=>{
 const f=await fixture(),payload=provisionPayload(f),job=await reserve(f,'students',payload);
 assert.equal((await f.client.query('select admin_provision_reject($1) result',[job.id])).rows[0].result,true);
 const next=await reserve(f,'students',payload);assert.notEqual(next.authUserId,job.authUserId);
 const unexpected=randomUUID();await db.admin.query('insert into auth.users(id,email,raw_app_meta_data) values($1,$2,$3::jsonb)',[unexpected,next.email,JSON.stringify({institution_id:f.inst,provisioning_id:next.id})]);
 await f.client.query('select admin_provision_observe($1,$2)',[next.id,unexpected]);
 const state=(await db.admin.query('select status,observed_auth_user_id from admin_provisionings where id=$1',[next.id])).rows[0];
 assert.equal(state.status,'needs_review');assert.equal(state.observed_auth_user_id,unexpected);
 await assert.rejects(complete(f,next),{code:'22023'});
});
test('archiving a person disables its linked login in the same transaction and protects administrative identities',async()=>{
 const f=await fixture();await f.client.query("select admin_person_archive($1,'parents',$2)",[f.inst,f.parent]);
 const row=(await db.admin.query('select active,deleted_at from users where id=$1',[f.parentUser.id])).rows[0];assert.equal(row.active,false);assert.ok(row.deleted_at);
 const session=await db.connect();await asUser(session,f.parentUser.auth,f.inst);
 assert.equal((await session.query('select current_institution_id() id')).rows[0].id,null);
 await assert.rejects(f.client.query('select admin_account_archive($1,$2)',[f.inst,f.admin.id]),{code:'42501'});
});
test('role definitions cannot mint platform privilege or rename an assigned role into another authority',async()=>{
 const f=await fixture();
 await assert.rejects(f.client.query("select admin_role_write($1,null,'{\"name\":\"Platform\",\"code\":\"super_admin\"}',false)",[f.inst]),{code:'42501'});
 const role=(await f.client.query("select admin_role_write($1,null,'{\"name\":\"Custom\",\"code\":\"custom\"}',false) result",[f.inst])).rows[0].result;
 await db.admin.query('insert into user_roles(institution_id,user_id,role_id) values($1,$2,$3)',[f.inst,f.teacherUser.id,role.id]);
 await assert.rejects(f.client.query("select admin_role_write($1,$2,'{\"code\":\"super_admin\"}',false)",[f.inst,role.id]),{code:'22023'});
 assert.equal((await db.admin.query('select code from roles where id=$1',[role.id])).rows[0].code,'custom');
});
