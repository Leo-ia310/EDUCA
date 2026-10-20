import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {before,after,afterEach,test} from 'node:test';
import {database,asUser} from './helpers/database.mjs';
let db;
before(async()=>{db=await database();},{timeout:120000});
afterEach(async()=>{if(db)await db.release();});
after(async()=>{if(db)await db.close();});
async function fixture(count=2) {
 const q=(sql,args)=>db.admin.query(sql,args), tag=randomUUID().slice(0,8);
 const inst=(await q("insert into institutions(code,name) values($1,'Attendance fixture') returning id",['SYNC-'+tag])).rows[0].id;
 const person=(await q("insert into persons(institution_id,first_name,last_name) values($1,'Teacher','Fixture') returning id",[inst])).rows[0].id;
 const auth=randomUUID();await q('insert into auth.users(id) values($1)',[auth]);
 const user=(await q("insert into users(institution_id,auth_user_id,person_id,email,full_name) values($1,$2,$3,$4,'Teacher') returning id",[inst,auth,person,tag+'@fixture.invalid'])).rows[0].id;
 await q("insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code='teacher' limit 1",[inst,user]);
 const teacher=(await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[inst,person])).rows[0].id;
 const year=(await q("insert into academic_years(institution_id,name,year,start_date,end_date,is_current) values($1,'2026',2026,'2026-01-01','2026-12-31',true) returning id",[inst])).rows[0].id;
 const group=(await q("insert into groups(institution_id,name,academic_year_id) values($1,'Fixture',$2) returning id",[inst,year])).rows[0].id;
 const subject=(await q("insert into subjects(institution_id,name) values($1,'Fixture') returning id",[inst])).rows[0].id;
 const cls=(await q('insert into classes(institution_id,group_id,subject_id,teacher_id,academic_year_id) values($1,$2,$3,$4,$5) returning id',[inst,group,subject,teacher,year])).rows[0].id;
 const people=(await q("insert into persons(institution_id,first_name,last_name) select $1,'Student '||i,'Fixture' from generate_series(1,$2::int) i returning id",[inst,count])).rows.map(r=>r.id);
 const students=(await q('insert into students(institution_id,person_id) select $1,unnest($2::bigint[]) returning id',[inst,people])).rows.map(r=>r.id);
 await q("insert into enrollments(institution_id,student_id,group_id,academic_year_id,enrollment_status_id) select $1,unnest($2::bigint[]),$3,$4,(select id from catalog_enrollment_statuses where code='ACT' limit 1)",[inst,students,group,year]);
 const client=await db.connect();await asUser(client,auth,inst);
 return {inst,user,auth,cls,students,client};
}
function mark(f,student=f.students[0],extra={}) {return {operationId:randomUUID(),uuid:randomUUID(),classId:f.cls,date:'2026-10-18',studentId:student,statusId:1,recordedAt:'2026-10-18T12:00:00Z',expectedVersion:0,notes:null,...extra};}
async function upload(f,marks,sessions=[]) {return (await f.client.query('select sync_attendance_batch($1::jsonb,$2::jsonb) result',[JSON.stringify(sessions),JSON.stringify(marks)])).rows[0].result;}
test('a lost batch response replays original IDs and versions without changing attendance twice',async()=>{
 const f=await fixture(),m=mark(f),first=await upload(f,[m]);
 assert.equal(first.records[0].status,'applied');assert.equal(first.records[0].version,1);
 assert.deepEqual(await upload(f,[m]),first);
 const q=await db.admin.query("select (select count(*) from attendances where institution_id=$1) marks,(select count(*) from change_log where institution_id=$1) changes",[f.inst]);
 assert.deepEqual(q.rows[0],{marks:'1',changes:'1'});
 await assert.rejects(upload(f,[{...m,statusId:2}]),{code:'23505'});
});
test('concurrent edits compare versions and return a durable conflict instead of overwriting',async()=>{
 const f=await fixture(),initial=(await upload(f,[mark(f)])).records[0];
 const person=(await db.admin.query("insert into persons(institution_id,first_name,last_name) values($1,'Collaborator','Fixture') returning id",[f.inst])).rows[0].id;
 const auth=randomUUID();await db.admin.query('insert into auth.users(id) values($1)',[auth]);
 const user=(await db.admin.query("insert into users(institution_id,person_id,auth_user_id,email,full_name) values($1,$2,$3,$4,'Collaborator') returning id",[f.inst,person,auth,auth+'@fixture.invalid'])).rows[0].id;
 const teacher=(await db.admin.query('insert into teachers(institution_id,person_id) values($1,$2) returning id',[f.inst,person])).rows[0].id;
 await db.admin.query("insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code='teacher' limit 1",[f.inst,user]);
 await db.admin.query("insert into class_collaborators(institution_id,class_id,teacher_id,teacher_user_id,invited_by,permissions,status) values($1,$2,$3,$4,$5,array['class.view','attendance.write'],'active')",[f.inst,f.cls,teacher,user,f.user]);
 const second=await db.connect();await asUser(second,auth,f.inst);
 const a=mark(f,f.students[0],{expectedVersion:initial.version,statusId:2}),b=mark(f,f.students[0],{expectedVersion:initial.version,statusId:3});
 const results=await Promise.all([upload(f,[a]),upload({...f,client:second},[b])]);
 assert.deepEqual(results.map(r=>r.records[0].status).sort(),['applied','conflict']);
 const conflict=results.find(r=>r.records[0].status==='conflict').records[0];assert.equal(conflict.version,2);
 assert.equal((await db.admin.query('select version from attendances where institution_id=$1',[f.inst])).rows[0].version,2);
 await db.admin.query("update class_collaborators set status='revoked' where teacher_user_id=$1",[user]);
 await assert.rejects(upload({...f,client:second},[mark(f,f.students[0],{expectedVersion:2})]),{code:'42501'});
});
test('invalid marks roll back the session and the complete batch; direct bypass and unrelated classes are denied',async()=>{
 const f=await fixture(),foreign=await fixture();
 await assert.rejects(upload(f,[mark(f),mark(f,f.students[1],{statusId:9999})]),{code:'22023'});
 assert.equal((await db.admin.query('select count(*) from class_sessions where institution_id=$1',[f.inst])).rows[0].count,'0');
 await assert.rejects(upload(f,[mark(f,foreign.students[0])]),{code:'42501'});
 await assert.rejects(upload(f,[mark(f,f.students[0],{classId:foreign.cls})]),{code:'42501'});
 await assert.rejects(f.client.query("insert into attendances(uuid,institution_id) values($1,$2)",[randomUUID(),f.inst]),{code:'42501'});
});
test('more than 1000 changes page by timestamp plus ID with tied timestamps and exact class scope',async()=>{
 const f=await fixture(1105),foreign=await fixture();
 for(let i=0;i<f.students.length;i+=100)await upload(f,f.students.slice(i,i+100).map(s=>mark(f,s)));
 await upload(foreign,[mark(foreign)]);
 await db.admin.query("update change_log set updated_at='2026-10-19T12:00:00.123456Z' where institution_id=$1",[f.inst]);
 let cursor={updatedAt:'1970-01-01T00:00:00Z',id:'0'},ids=[];
 for(let i=0;i<20;i++) {
  const page=(await f.client.query('select attendance_changes($1,$2,100) page',[cursor.updatedAt,cursor.id])).rows[0].page;
  ids.push(...page.items.map(r=>r.id));cursor=page.cursor;
  if(!page.hasMore)break;
 }
 assert.equal(ids.length,1105);assert.equal(new Set(ids).size,1105);
 assert.match(cursor.updatedAt,/\.123456(?:Z|[+-])/);
 assert.equal(Date.parse(cursor.updatedAt),Date.parse('2026-10-19T12:00:00.123456Z'));
});
test('pull waits for an uncommitted writer before allocating its returned cursor',async()=>{
 const f=await fixture(),other=await db.connect();await asUser(other,f.auth,f.inst);
 await f.client.query('begin');const saved=await upload(f,[mark(f)]);
 let settled=false;
 const pending=other.query('select attendance_changes() page').then(r=>{settled=true;return r.rows[0].page;});
 await new Promise(resolve=>setTimeout(resolve,50));assert.equal(settled,false);
 await f.client.query('commit');const page=await pending;
 assert.equal(page.items.length,1);assert.equal(page.items[0].recordId,saved.records[0].id);
});
