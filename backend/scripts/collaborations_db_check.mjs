// Real RLS/RPC checks with temporary identities. Everything rolls back, including
// invitations/notifications/audit, and no email/push service is called.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { loadEnv, pgConfig } from './env.mjs';
const c = new pg.Client({...pgConfig(loadEnv()), connectionTimeoutMillis:10000, query_timeout:15000});
try {
 await c.connect(); await c.query('begin');
 const classes = (await c.query('select id,institution_id,group_id from classes where institution_id=2 and active order by id limit 3')).rows;
 assert.equal(classes.length,3);
 const inst=classes[0].institution_id;
 const teacherRole=(await c.query("select id from roles where code='teacher' order by institution_id nulls first limit 1")).rows[0].id;
 async function teacher(name, institution=inst) {
   const auth=randomUUID();
   await c.query('insert into auth.users(id) values($1)',[auth]);
   const person=(await c.query('insert into persons(institution_id,first_name,last_name) values($1,$2,$3) returning id',[institution,'Collaboration',name])).rows[0].id;
   const user=(await c.query('insert into users(institution_id,person_id,auth_user_id,email,full_name) values($1,$2,$3,$4,$5) returning id',[institution,person,auth,`${auth}@invalid.test`,name])).rows[0].id;
   const tid=(await c.query('insert into teachers(institution_id,person_id) values($1,$2) returning id',[institution,person])).rows[0].id;
   await c.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)',[user,teacherRole,institution]);
   return {auth,user,tid,person,institution};
 }
 const owner=await teacher('Owner'), guest=await teacher('Guest'), outsider=await teacher('Other institution',1);
 await c.query('update classes set teacher_id=$1 where id=any($2::bigint[])',[owner.tid,classes.slice(0,2).map(x=>x.id)]);
 async function as(actor) {
   await c.query('reset role');
   await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor.auth,role:'authenticated',app_metadata:{institution_id:Number(actor.institution)}})]);
   await c.query('set local role authenticated');
 }
 async function denied(fn, message) { await c.query('savepoint denied'); await assert.rejects(fn, message); await c.query('rollback to savepoint denied'); }
 async function manage(action, ids=null, perms=null, invitation=null, user=guest.user) {
   return (await c.query('select manage_class_collaboration($1,$2,$3,$4,$5) data',[action,ids,user,perms,invitation])).rows[0].data;
 }
 const can=async(id,p)=>(await c.query('select class_permission($1,$2) ok',[id,p])).rows[0].ok;
 await as(owner);
 await denied(()=>manage('invite',[classes[0].id,classes[2].id],['class.view']),/permiso/);
 assert.equal((await c.query('select count(*)::int n from class_collaborators where invited_by=$1',[owner.user])).rows[0].n,0,'Batch with unauthorized class rolls back all invites');
 await denied(()=>manage('invite',[classes[0].id],['class.view'],null,outsider.user),/instituci/);
 await denied(()=>manage('invite',[classes[0].id],['collaborators.manage']),/Permisos/);
 let workspace=await manage('invite',classes.slice(0,2).map(x=>x.id),['assignments.grade','grades.write']);
 const invitations=workspace.invitations.filter(x=>String(x.teacherUserId)===String(guest.user));
 assert.equal(invitations.length,2);
 const first=invitations.find(x=>String(x.classId)===String(classes[0].id));
 await denied(()=>manage('accept',null,null,first.id),/responder/);
 await as(guest);
 assert.equal(await can(classes[0].id,'class.view'),false,'Pending invitation grants no access');
 await manage('accept',null,null,first.id);
 assert.equal(await can(classes[0].id,'assignments.grade'),true);
 assert.equal(await can(classes[0].id,'assignments.review'),true);
 assert.equal(await can(classes[0].id,'students.view'),true);
 assert.equal(await can(classes[0].id,'grades.write'),true);
 assert.equal(await can(classes[0].id,'assignments.create'),false);
 assert.equal(await can(classes[0].id,'attendance.write'),false);
 assert.equal(await can(classes[1].id,'class.view'),false,'Second class is still pending');
 await denied(()=>manage('invite',[classes[0].id],['class.view'],null,owner.user),/permiso/);
 await denied(()=>manage('update',null,['attendance.write'],first.id),/titular/);
 // Direct table calls cannot widen privileges or change ownership identities.
 await denied(()=>c.query('update class_collaborators set permissions=$1 where id=$2',[['class.view','assignments.create'],first.id]),/permission denied/);
 await denied(()=>c.query('update users set person_id=$1 where id=$2',[owner.person,guest.user]),/identidad/);
 assert.equal((await c.query('update teachers set person_id=$1 where id=$2 returning id',[guest.person,owner.tid])).rowCount,0);
 assert.equal((await c.query('delete from user_roles where user_id=$1 returning id',[owner.user])).rowCount,0);
 assert.equal((await c.query('select id from classes where id=$1',[classes[0].id])).rowCount,1);
 assert.equal((await c.query('select id from classes where id=$1',[classes[1].id])).rowCount,0);
 await denied(()=>c.query('insert into assignments(institution_id,class_id,title,due_at,max_score,published) values($1,$2,$3,now()+interval \'1 day\',100,true)',[inst,classes[0].id,'Forbidden create']),/row-level security/);
 // Create a submission as owner/student fixture using transaction owner only.
 await c.query('reset role');
 const student=(await c.query('select student_id from enrollments where group_id=$1 limit 1',[classes[0].group_id])).rows[0]; assert.ok(student);
 const assignment=(await c.query('insert into assignments(institution_id,class_id,title,due_at,max_score,published) values($1,$2,$3,now()+interval \'1 day\',100,true) returning id',[inst,classes[0].id,'Collaboration rollback test'])).rows[0].id;
 const submission=(await c.query('insert into submissions(institution_id,assignment_id,student_id,submitted_at) values($1,$2,$3,now()) returning id',[inst,assignment,student.student_id])).rows[0].id;
 await as(guest);
 const grade=(await c.query('select grade_submission($1,75,$2) id',[submission,'Reviewed by collaborator'])).rows[0].id;
 assert.equal(String((await c.query('select recorded_by from grades where id=$1',[grade])).rows[0].recorded_by),String(guest.user));
 assert.equal((await c.query('update grades set score=80 where id=$1 returning id',[grade])).rowCount,1);
 await denied(()=>c.query('insert into class_sessions(institution_id,class_id,group_id,date) values($1,$2,$3,current_date)',[inst,classes[0].id,classes[0].group_id]),/row-level security/);
 await as(owner); await manage('update',null,['assignments.grade'],first.id);
 await as(guest);
 await c.query('select grade_submission($1,76,null)',[submission]);
 assert.equal((await c.query('update grades set score=77 where id=$1 returning id',[grade])).rowCount,0,'Task grading does not grant direct gradebook editing');
 await as(owner); await manage('update',null,['grades.write'],first.id);
 await as(guest);
 await denied(()=>c.query('select grade_submission($1,78,null)',[submission]),/permiso/);
 assert.equal((await c.query('update grades set score=79 where id=$1 returning id',[grade])).rowCount,1,'Gradebook permission does not grant task grading');
 await as(owner);
 await manage('update',null,['class.view'],first.id);
 await as(guest);
 assert.equal(await can(classes[0].id,'class.view'),true);
 assert.equal(await can(classes[0].id,'students.view'),false);
 assert.equal((await c.query('select id from submissions where id=$1',[submission])).rowCount,0);
 assert.equal((await c.query('select id from grades where id=$1',[grade])).rowCount,0);
 await denied(()=>c.query('select grade_submission($1,90,null)',[submission]),/permiso/);
 await denied(()=>c.query('select grade_submission_internal($1,90,null)',[submission]),/permission denied/);
 // Read-only still cannot create tasks, record notes, or change class ownership.
 assert.equal((await c.query('update assignments set title=$1 where id=$2 returning id',['Cannot edit',assignment])).rowCount,0);
 await denied(()=>c.query('update classes set teacher_id=$1 where id=$2 returning id',[guest.tid,classes[0].id]),/row-level security/);
 await as(owner); await manage('update',null,['assignments.create','attendance.write'],first.id);
 await as(guest);
 const ownTask=(await c.query('insert into assignments(institution_id,class_id,title,due_at,max_score,published,created_by) values($1,$2,$3,now()+interval \'1 day\',100,true,$4) returning id',[inst,classes[0].id,'Allowed collaborator task',guest.tid])).rows[0].id;
 assert.ok(ownTask);
 await denied(()=>c.query('insert into assignments(institution_id,class_id,title,due_at,max_score,published) values($1,$2,$3,now()+interval \'1 day\',100,true)',[inst,classes[1].id,'Forbidden other class']),/row-level security/);
 const session=(await c.query("select ensure_collaborative_class_session($1,'2030-01-10') id",[classes[0].id])).rows[0].id;
 await as(owner);
 assert.equal((await c.query("select ensure_collaborative_class_session($1,'2030-01-10') id",[classes[0].id])).rows[0].id,session,'Owner and collaborator share the same attendance session');
 await as(guest);
 await as(owner); await manage('revoke',null,null,first.id);
 await as(guest); assert.equal(await can(classes[0].id,'class.view'),false);
 assert.equal((await c.query('select id from assignments where id=$1',[assignment])).rowCount,0);
 await as(outsider); assert.equal(await can(classes[0].id,'class.view'),false);
 await c.query('reset role');
 const audits=(await c.query("select count(*)::int n from audit_log where user_id=$1 and table_name='grades'",[guest.user])).rows[0].n;
 assert.ok(audits>=2,'Grading RPC and direct grade edits audit the actual actor');
 console.log('Collaboration DB checks passed: multi-class atomic invites, acceptance, dependencies, direct SQL/RPC denials, grade actor/audit, tenant/identity isolation, permission changes and immediate revocation. All test data rolled back.');
} finally { await c.query('rollback').catch(()=>{}); await c.end(); }
