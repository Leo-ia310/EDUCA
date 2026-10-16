// All fixtures, policies configured by the test, notifications and audits roll
// back. This never sends email or changes a real family's permissions.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {loadEnv,pgConfig} from './env.mjs';
const c=new pg.Client({...pgConfig(loadEnv()),connectionTimeoutMillis:10000,query_timeout:20000});
try{
 await c.connect();await c.query('begin');
 const inst=2;
 const student=(await c.query('select s.id,s.person_id,e.group_id from students s join enrollments e on e.student_id=s.id where s.institution_id=$1 and s.active limit 1',[inst])).rows[0];assert.ok(student);
 const periods=(await c.query('select id from academic_periods where institution_id=$1 order by id limit 2',[inst])).rows;assert.equal(periods.length,2);
 const cls=(await c.query('select id from classes where institution_id=$1 and group_id=$2 and active limit 1',[inst,student.group_id])).rows[0];assert.ok(cls);
 async function user(role,person=null,institution=inst){
  const auth=randomUUID();await c.query('insert into auth.users(id) values($1)',[auth]);
  if(!person)person=(await c.query('insert into persons(institution_id,first_name,last_name) values($1,$2,$3) returning id',[institution,'Portal',role])).rows[0].id;
  const id=(await c.query('insert into users(institution_id,person_id,auth_user_id,email,full_name) values($1,$2,$3,$4,$5) returning id',[institution,person,auth,`${auth}@invalid.test`,'Portal '+role])).rows[0].id;
  const rid=(await c.query('select id from roles where code=$1 order by institution_id nulls first limit 1',[role])).rows[0].id;
  await c.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)',[id,rid,institution]);
  return{id,auth,person,institution};
 }
 const admin=await user('admin'),pupil=await user('student',student.person_id),parent=await user('parent'),foreign=await user('parent',null,1);
 const parentId=(await c.query('insert into parents(institution_id,person_id) values($1,$2) returning id',[inst,parent.person])).rows[0].id;
 await c.query('insert into parent_students(student_id,parent_id) values($1,$2)',[student.id,parentId]);
 const evals=[],grades=[];
 for(const p of periods){
  const eid=(await c.query('insert into evaluations(institution_id,class_id,academic_period_id,title,max_score,published) values($1,$2,$3,$4,100,true) returning id',[inst,cls.id,p.id,'Portal rollback evaluation'])).rows[0].id;evals.push(eid);
  grades.push((await c.query('insert into grades(institution_id,evaluation_id,student_id,score) values($1,$2,$3,86) on conflict(evaluation_id,student_id) do update set score=excluded.score returning id',[inst,eid,student.id])).rows[0].id);
 }
 const card=(await c.query('insert into report_cards(institution_id,student_id,academic_period_id,overall_average,pdf_url) values($1,$2,$3,86,$4) returning id',[inst,student.id,periods[0].id,'private-test-pdf-'+randomUUID()])).rows[0].id;
 const materialPath=`${inst}/materials/${randomUUID()}`;
 const file=(await c.query('insert into files(institution_id,original_name,storage_path,uploaded_by) values($1,$2,$3,$4) returning id',[inst,'Material de prueba',materialPath,admin.id])).rows[0].id;
 const pdfPath=`${inst}/reports/${randomUUID()}.pdf`;
 const pdfUrl=(await c.query('select pdf_url from report_cards where id=$1',[card])).rows[0].pdf_url;
 const pdfFile=(await c.query('insert into files(institution_id,original_name,storage_path,uploaded_by,url) values($1,$2,$3,$4,$5) returning id',[inst,'Boletin de prueba',pdfPath,admin.id,pdfUrl])).rows[0].id;
 await c.query('insert into storage.objects(bucket_id,name,owner_id) values($1,$2,$3),($1,$4,$3)',['files',materialPath,admin.auth,pdfPath]);

 const assignment=(await c.query('insert into assignments(institution_id,class_id,title,published) values($1,$2,$3,true) returning id',[inst,cls.id,'Portal rollback task'])).rows[0].id;
 const submission=(await c.query('insert into submissions(institution_id,assignment_id,student_id,student_notes) values($1,$2,$3,$4) returning id',[inst,assignment,student.id,'Initial delivery'])).rows[0].id;
 const conversation=(await c.query('insert into conversations(institution_id,kind,created_by) values($1,$2,$3) returning id',[inst,'individual',parent.id])).rows[0].id;
 await c.query('insert into conversation_participants(conversation_id,user_id) values($1,$2)',[conversation,parent.id]);
 async function as(actor){await c.query('reset role');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:actor.auth,role:'authenticated',app_metadata:{institution_id:actor.institution}})]);await c.query('set local role authenticated');}
 async function deny(fn){await c.query('savepoint denial');await assert.rejects(fn());await c.query('rollback to savepoint denial');}
 async function manage(action,payload){return(await c.query('select manage_portal_access($1,$2) data',[action,payload])).rows[0].data;}
 const can=async(code)=>(await c.query('select portal_can($1) ok',[code])).rows[0].ok;
 const visible=async(period)=>(await c.query('select portal_can_view_grades($1,$2) ok',[student.id,period])).rows[0].ok;
 const gradeCount=async()=>(await c.query('select count(*)::int n from grades where id=any($1::bigint[])',[grades])).rows[0].n;
 await as(pupil);assert.equal(await gradeCount(),2);await deny(()=>manage('save_permission',{scope:'user',userId:pupil.id,permission:'grades.view',allowed:false}));
 await deny(()=>c.query('insert into portal_permission_rules(institution_id,scope,user_id,permission,allowed) values($1,$2,$3,$4,true)',[inst,'user',pupil.id,'grades.view']));
 await as(admin);const revision=(await c.query('select revision from portal_access_revisions where institution_id=$1',[inst])).rows[0].revision;
 await manage('save_permission',{scope:'role',role:'parent',permission:'grades.view',allowed:false});
 assert.ok(BigInt((await c.query('select revision from portal_access_revisions where institution_id=$1',[inst])).rows[0].revision)>BigInt(revision),'Saving a rule emits a revision change');
 await deny(()=>c.query('update portal_access_revisions set revision=0 where institution_id=$1',[inst]));
 await as(parent);assert.equal(await can('grades.view'),false);assert.equal(await gradeCount(),0);assert.equal((await c.query('select id from report_cards where id=$1',[card])).rowCount,0);
 await as(pupil);assert.equal(await gradeCount(),2,'Parent denial does not block the child account');
 await as(admin);await manage('save_permission',{scope:'user',userId:parent.id,permission:'grades.view',allowed:true});
 await as(parent);assert.equal(await gradeCount(),2,'Specific user grant overrides role denial');
 assert.equal((await c.query('select name from storage.objects where bucket_id=$1 and name=any($2::text[])',['files',[materialPath,pdfPath]])).rowCount,2,'Allowed materials and report objects are visible');
 await as(admin);await manage('save_visibility',{scope:'institution',allowed:false});
 await as(pupil);assert.equal(await gradeCount(),0);assert.equal(await visible(null),false);
 await as(parent);assert.equal(await gradeCount(),0);
 await as(admin);assert.equal(await gradeCount(),2,'Administration retains academic access');
 await manage('save_visibility',{scope:'group',groupId:student.group_id,allowed:true});
 await as(parent);assert.equal(await gradeCount(),2,'Group rule overrides the institution');
 await as(admin);await manage('save_visibility',{scope:'student',studentId:student.id,allowed:false});
 await as(parent);assert.equal(await gradeCount(),0,'Student rule overrides the group');
 await as(admin);
 await manage('save_visibility',{scope:'student',studentId:student.id,allowed:true});
 await as(pupil);assert.equal(await gradeCount(),2);
 await as(parent);assert.equal(await gradeCount(),2,'A student visibility rule also applies to linked parents');
 await as(admin);await manage('save_permission',{scope:'user',userId:parent.id,permission:'reports.download',allowed:false});
 await as(parent);assert.equal(await gradeCount(),2);assert.equal((await c.query('select id from report_cards where id=$1',[card])).rowCount,0,'Download denial protects stored PDF URLs even when grades remain visible');
 await as(admin);let cfg=(await c.query('select portal_access_admin() data')).rows[0].data;
 await manage('delete_permission',{id:cfg.permissionRules.find(r=>String(r.user_id)===String(parent.id)&&r.permission==='reports.download').id});
 await manage('save_permission',{scope:'user',userId:pupil.id,permission:'assignments.submit',allowed:false});
 await as(pupil);assert.equal((await c.query('select id from submissions where id=$1',[submission])).rowCount,1,'Disabling submit preserves reading');
 assert.equal((await c.query('update submissions set student_notes=$1 where id=$2 returning id',['Blocked change',submission])).rowCount,0);
 await as(parent);assert.equal((await c.query('update submissions set student_notes=$1 where id=$2 returning id',['Parent change',submission])).rowCount,0,'A parent cannot submit for the student');
 await as(admin);await manage('save_permission',{scope:'user',userId:pupil.id,permission:'assignments.submit',allowed:true});
 await as(pupil);assert.equal((await c.query('update submissions set student_notes=$1 where id=$2 returning id',['Allowed change',submission])).rowCount,1);
 await as(admin);await manage('save_visibility',{scope:'user',userId:parent.id,periodId:periods[0].id,allowed:false});
 await as(parent);assert.equal(await gradeCount(),1);assert.equal(await visible(periods[0].id),false);assert.equal(await visible(periods[1].id),true);assert.equal(await visible(null),false,'Annual reports cannot disclose a hidden period');
 assert.equal((await c.query('select id from report_cards where id=$1',[card])).rowCount,0);
 assert.equal((await c.query('select id from files where id=$1',[pdfFile])).rowCount,0,'Hidden PDF metadata is blocked');
 assert.equal((await c.query('select name from storage.objects where bucket_id=$1 and name=$2',['files',pdfPath])).rowCount,0,'Hidden PDF Storage object is blocked');
 assert.equal((await c.query('select * from student_weighted_averages where student_id=$1 and academic_period_id=$2',[student.id,periods[0].id])).rowCount,0);
 await as(pupil);assert.equal(await gradeCount(),2,'Parent-specific period rule does not hide child notes');
 await as(admin);
 for(const permission of ['payments.view','attendance.view','schedule.view','assignments.view','assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view'])await manage('save_permission',{scope:'user',userId:parent.id,permission,allowed:false});
 await as(parent);
 for(const permission of ['payments.view','attendance.view','schedule.view','assignments.view','assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view'])assert.equal(await can(permission),false);
 for(const table of ['charges','payments','attendances','schedules','assignments','announcements','report_cards'])assert.equal((await c.query(`select count(*)::int n from ${table}`)).rows[0].n,0,`Direct ${table} reads must be blocked`);
 await deny(()=>c.query('insert into messages(conversation_id,sender_id,content) values($1,$2,$3)',[conversation,parent.id,'Blocked test message']));
 assert.equal((await c.query('select id from conversations where id=$1',[conversation])).rowCount,1,'Disabling send preserves incoming conversations');
 assert.equal((await c.query('select id from files where id=$1',[file])).rowCount,0,'Materials metadata is restricted');
 assert.equal((await c.query('select name from storage.objects where bucket_id=$1 and name=$2',['files',materialPath])).rowCount,0,'Materials Storage object is restricted');
 assert.equal((await c.query('update files set uploaded_by=$1 where id=$2 returning id',[parent.id,file])).rowCount,0,'An invisible file cannot be claimed');
 assert.equal((await c.query('delete from parent_students where parent_id=$1 returning id',[parentId])).rowCount,0,'Users cannot rewrite child scope');
 await as(foreign);assert.equal((await c.query('select institution_id from portal_access_revisions where institution_id=$1',[inst])).rowCount,0,'Revision events are isolated by institution');assert.equal(await visible(periods[1].id),false);assert.equal(await gradeCount(),0);
 await as(admin);await deny(()=>manage('save_permission',{scope:'user',userId:foreign.id,permission:'grades.view',allowed:false}));
 // Removing overrides restores inherited access; it does not modify grades.
 let config=(await c.query('select portal_access_admin() data')).rows[0].data;
 for(const rule of config.permissionRules.filter(r=>String(r.user_id)===String(parent.id)&&r.permission!=='grades.view'))await manage('delete_permission',{id:rule.id});
 await as(parent);assert.equal(await can('payments.view'),true);assert.equal(await can('messages.send'),true);
 const me=(await c.query('select portal_access_me() data')).rows[0].data;assert.ok(me.students.some(s=>String(s.studentId)===String(student.id)));
 await c.query('reset role');assert.ok((await c.query("select count(*)::int n from audit_log where user_id=$1 and table_name in ('portal_permission_rules','grade_visibility_rules')",[admin.id])).rows[0].n>0,'Settings record the authenticated admin in the audit');assert.equal((await c.query('select count(*)::int n from grades where id=any($1::bigint[])',[grades])).rows[0].n,2);
 console.log('Portal access DB checks passed: role/user precedence, institution/student/parent/period grade rules, annual aggregate/PDF protection, direct module/Storage metadata guards, tenant isolation, immutable family scope, audit-backed settings and reversible rules. All fixtures rolled back.');
}finally{await c.query('rollback').catch(()=>{});await c.end();}
