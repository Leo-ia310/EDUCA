import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { after, afterEach, before, beforeEach, test } from 'node:test';
import { asUser, database } from './helpers/database.mjs';

let db, tenant, student, otherStudent, concept, adminUser, parentUser, teacherUser, academicFixture;
let originalInstitutions,originalPresentId;
before(async () => {
  db = await database();
  originalInstitutions=(await db.admin.query('select id from institutions')).rows.map(row=>row.id);
  originalPresentId=(await db.admin.query("select id from catalog_attendance_statuses where code='PRE'")).rows[0].id;
}, { timeout: 120000 });
beforeEach(async()=>{
  const q = (sql, params) => db.admin.query(sql, params);
  tenant = (await q("insert into institutions(code,name) values($1,'Local payment test') returning id",['PAYMENT-'+randomUUID()])).rows[0].id;
  async function person(name) {
    return (await q("insert into persons(institution_id,first_name,last_name) values($1,$2,'Test') returning id", [tenant, name])).rows[0].id;
  }
  student = (await q('insert into students(institution_id,person_id) values($1,$2) returning id', [tenant, await person('Student')])).rows[0].id;
  otherStudent = (await q('insert into students(institution_id,person_id) values($1,$2) returning id', [tenant, await person('Other')])).rows[0].id;
  async function user(role) {
    const auth = randomUUID(), personId = await person(role);
    await q('insert into auth.users(id) values($1)', [auth]);
    const id = (await q('insert into users(auth_user_id,institution_id,person_id,email,full_name) values($1,$2,$3,$4,$5) returning id', [auth, tenant, personId, `${role}@test.invalid`, role])).rows[0].id;
    const roleId = (await q('insert into roles(institution_id,name,code) values($1,$2,$2) returning id', [tenant, role])).rows[0].id;
    await q('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)', [id, roleId, tenant]);
    return { auth, id, personId };
  }
  adminUser = await user('admin'); parentUser = await user('parent'); teacherUser = await user('teacher');
  const parentId = (await q('insert into parents(institution_id,person_id) values($1,$2) returning id', [tenant, parentUser.personId])).rows[0].id;
  await q('insert into parent_students(parent_id,student_id) values($1,$2)', [parentId, student]);
  concept = (await q("insert into payment_concepts(institution_id,name,base_amount) values($1,'Tuition',100) returning id", [tenant])).rows[0].id;
  await q('insert into teachers(institution_id,person_id) values($1,$2)',[tenant,teacherUser.personId]);
  const year=(await q("insert into academic_years(institution_id,name,year,is_current) values($1,'Current',2026,true) returning id",[tenant])).rows[0].id;
  const oldYear=(await q("insert into academic_years(institution_id,name,year) values($1,'Past',2025) returning id",[tenant])).rows[0].id;
  const groups=(await q("insert into groups(institution_id,academic_year_id,name) values($1,$2,'A'),($1,$2,'B') returning id",[tenant,year])).rows;
  const classes=(await q('insert into classes(institution_id,academic_year_id,group_id) select $1,$2,unnest($3::bigint[]) returning id',[tenant,year,groups.map(g=>g.id)])).rows;
  const activeStatus=(await q("select id from catalog_enrollment_statuses where code='ACT'")).rows[0].id;
  await q('insert into enrollments(institution_id,student_id,group_id,academic_year_id,enrollment_status_id) values($1,$2,$4,$6,$8),($1,$3,$4,$6,$8),($1,$2,$5,$7,$8)',[tenant,student,otherStudent,groups[0].id,groups[1].id,year,oldYear,activeStatus]);
  academicFixture={year,oldYear,groups,classes,activeStatus};
}, { timeout: 120000 });
after(async () => { if (db) await db.close(); });
afterEach(async()=>{if(db){
  await db.release();
  await db.admin.query('delete from institutions where not(id=any($1::bigint[]))',[originalInstitutions]);
  await db.admin.query("update catalog_attendance_statuses set id=$1 where code='PRE'",[originalPresentId]);
}});

async function charge(studentId = student) {
  return (await db.admin.query("insert into charges(institution_id,student_id,concept_id,amount,total_amount,status) values($1,$2,$3,100,100,'pending') returning id", [tenant, studentId, concept])).rows[0].id;
}
async function connection(user = adminUser, institutionId = tenant) {
  const client = await db.connect(); await asUser(client, user.auth, institutionId); return client;
}
async function pay(client, id, amount, key = randomUUID(), method = 'cash', reference = null) {
  return (await client.query('select register_charge_payment($1,$2,$3,$4,$5) payment', [id, amount, method, reference, key])).rows[0].payment;
}

test('two simultaneous 60 payments against 100 cannot overpay', async () => {
  const id = await charge(), a = await connection(), b = await connection();
  const results = await Promise.allSettled([pay(a, id, 60), pay(b, id, 60)]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.find(r => r.status === 'rejected').reason.code, '22023');
  const row = (await db.admin.query('select c.status,(select sum(amount) from payments where charge_id=c.id) paid from charges c where id=$1', [id])).rows[0];
  assert.deepEqual(row, { status: 'partial', paid: '60.00' });
});

test('same key concurrent retry and retry after closing return the original receipt', async () => {
  const id = await charge(), key = randomUUID(), a = await connection(), b = await connection();
  const results = await Promise.all([pay(a, id, 100, key), pay(b, id, 100, key)]);
  assert.deepEqual(results[0], results[1]);
  assert.deepEqual(await pay(a, id, 100, key), results[0]);
  assert.equal((await db.admin.query('select count(*) from payments where charge_id=$1', [id])).rows[0].count, '1');
});

test('same key with different amount, charge, method or reference conflicts', async () => {
  const id = await charge(), other = await charge(), key = randomUUID(), client = await connection();
  await pay(client, id, 20, key);
  for (const args of [[id, 21, key], [other, 20, key], [id, 20, key, 'transfer'], [id, 20, key, 'cash', 'changed']]) {
    await assert.rejects(pay(client, ...args), { code: '23505' });
  }
});

test('parent can pay linked child, cannot pay other child or replay another actor key', async () => {
  const client = await connection(parentUser), id = await charge(), key = randomUUID();
  const receipt = await pay(client, id, 10, key); assert.equal(receipt.amount, 10);
  await assert.rejects(pay(client, await charge(otherStudent), 10), { code: '42501' });
  await assert.rejects(pay(await connection(), id, 10, key), { code: '23505' });
});

test('wrong tenant, teacher, inactive account and missing MFA are denied', async () => {
  const id = await charge();
  await assert.rejects(pay(await connection(teacherUser), id, 10), { code: '42501' });
  await assert.rejects(pay(await connection(adminUser, 999999), id, 10), { code: '42501' });
  await db.admin.query('update users set active=false where id=$1', [adminUser.id]);
  await assert.rejects(pay(await connection(), id, 10), { code: '42501' });
  await db.admin.query('update users set active=true where id=$1', [adminUser.id]);
  await db.admin.query("insert into auth_two_factor_settings(user_id,enabled,method) values($1,true,'totp')", [adminUser.id]);
  await assert.rejects(pay(await connection(), id, 10), { code: '42501' });
  await db.admin.query('update auth_two_factor_settings set enabled=false where user_id=$1', [adminUser.id]);
});

test('explicit create permission can receive own receipt without ledger-view permission', async () => {
  await db.admin.query("update users set admin_permissions=array['payments.create'] where id=$1", [adminUser.id]);
  const id = await charge();
  assert.equal((await pay(await connection(), id, 10)).amount, 10);
  await db.admin.query("update users set admin_permissions=array['payments.view'] where id=$1", [adminUser.id]);
  await assert.rejects(pay(await connection(), id, 10), { code: '42501' });
  await db.admin.query('update users set admin_permissions=null where id=$1', [adminUser.id]);
});

test('payment racing cancellation yields either a payment or an unpaid cancelled charge', async () => {
  for (let i = 0; i < 8; i++) {
    const id = await charge(), a = await connection(), b = await connection();
    const results = await Promise.allSettled([pay(a, id, 20), b.query('select cancel_unpaid_charge($1)', [id])]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    const row = (await db.admin.query('select status,(select coalesce(sum(amount),0) from payments where charge_id=charges.id) paid from charges where id=$1', [id])).rows[0];
    assert.ok((row.status === 'partial' && row.paid === '20.00') || (row.status === 'cancelled' && Number(row.paid) === 0));
  }
});

test('direct table inserts share balance protection and invalid money is rejected', async () => {
  const id = await charge();
  const insert = () => db.admin.query("insert into payments(institution_id,charge_id,student_id,amount,status) values($1,$2,$3,60,'paid')", [tenant, id, student]);
  // Separate connections are required to exercise concurrent writers.
  const other = await db.connect();
  const results = await Promise.allSettled([insert(), other.query("insert into payments(institution_id,charge_id,student_id,amount,status) values($1,$2,$3,60,'paid')", [tenant, id, student])]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const client = await connection();
  for (const amount of [0, -1, 0.001, 'NaN']) await assert.rejects(pay(client, await charge(), amount), { code: '22023' });
  await assert.rejects(client.query('select charge_payment_receipt(1)'), { code: '42501' });
});

test('SQL balances and collection metrics include more than 1000 installments and subtract partial payments', async () => {
  const client = await connection();
  const summary = async () => (await client.query('select payment_collection_summary() summary')).rows[0].summary;
  const before = await summary(), id = await charge();
  await db.admin.query("update charges set amount=2000,total_amount=2000,due_at=current_date-1 where id=$1", [id]);
  await db.admin.query("insert into payments(institution_id,charge_id,student_id,amount,status,paid_at) select $1,$2,$3,1,'paid',now() from generate_series(1,1105)", [tenant, id, student]);
  const totals = (await client.query('select * from payment_charge_totals($1)', [[id]])).rows;
  assert.equal(totals[0].paid, '1105.00');
  const after = await summary();
  assert.equal(after.collectedThisMonth - before.collectedThisMonth, 1105);
  assert.equal(after.overdueAmount - before.overdueAmount, 895);
  assert.equal(after.overdueCount - before.overdueCount, 1);
  assert.equal(after.byCurrency.USD.overdueAmount, after.overdueAmount);
});

test('aggregate RPCs retain parent scope, administrative grants and tenant isolation', async () => {
  const own = await charge(), other = await charge(otherStudent), client = await connection();
  await pay(client, own, 10); await pay(client, other, 20);
  const parent = await connection(parentUser);
  const rows = (await parent.query('select * from payment_charge_totals($1)', [[own, other]])).rows;
  assert.deepEqual(rows, [{ charge_id: own, paid: '10.00' }]);
  await assert.rejects(parent.query('select payment_collection_summary()'), { code: '42501' });
  await assert.rejects((await connection(adminUser, 999999)).query('select payment_collection_summary()'), { code: '42501' });
  await db.admin.query("update users set admin_permissions=array['payments.create'] where id=$1", [adminUser.id]);
  await assert.rejects(client.query('select payment_collection_summary()'), { code: '42501' });
  await db.admin.query('update users set admin_permissions=null where id=$1', [adminUser.id]);
});

test('summary separates currencies and excludes future paid_at from this month', async () => {
  const client = await connection();
  const before = (await client.query('select payment_collection_summary() value')).rows[0].value;
  const nio = (await db.admin.query("insert into payment_concepts(institution_id,name,currency_id) select $1,'NIO tuition',id from catalog_currencies where iso_code='NIO' returning id", [tenant])).rows[0].id;
  const id = await charge();
  await db.admin.query('update charges set concept_id=$1 where id=$2', [nio, id]);
  await pay(client, id, 20);
  const future = await charge();
  await db.admin.query("insert into payments(institution_id,charge_id,student_id,amount,status,paid_at) values($1,$2,$3,10,'paid',now()+interval '2 months')", [tenant, future, student]);
  const result = (await client.query('select payment_collection_summary() value')).rows[0].value;
  assert.equal(result.collectedThisMonth, before.collectedThisMonth);
  assert.equal(result.byCurrency.NIO.collectedThisMonth, 20);
});

test('dashboard counts use the assignment group and active enrollment year', async () => {
  const q = (sql, args) => db.admin.query(sql, args);
  const {year,oldYear,groups,classes}=academicFixture;
  const assignments = (await q("insert into assignments(institution_id,class_id,title,published) select $1,unnest($2::bigint[]),'Test',true returning id", [tenant, classes.map(c => c.id)])).rows;
  const client = await connection();
  const counts = (await client.query('select * from dashboard_assignment_counts($1) order by assignment_id', [assignments.map(a => a.id)])).rows;
  assert.equal(counts[0].total, '2'); assert.equal(counts[1].total, '0');
  // A pending submission is a draft, not a delivered task awaiting grading.
  await q("insert into submissions(institution_id,assignment_id,student_id,task_status_id) select $1,$2,$3,id from catalog_task_statuses where code='PEND'", [tenant, assignments[0].id, student]);
  assert.equal((await client.query('select dashboard_pending_grading($1) value', [classes.map(c => c.id)])).rows[0].value, '0');
  await q("update submissions set task_status_id=(select id from catalog_task_statuses where code='ENTR') where assignment_id=$1", [assignments[0].id]);
  assert.equal((await client.query('select dashboard_pending_grading($1) value', [classes.map(c => c.id)])).rows[0].value, '1');
  // PRE deliberately has a nonstandard ID; past-year marks must not affect it.
  await q("update catalog_attendance_statuses set id=501 where code='PRE'");
  const oldClass = (await q('insert into classes(institution_id,academic_year_id,group_id) values($1,$2,$3) returning id', [tenant, oldYear, groups[0].id])).rows[0].id;
  const sessions = (await q("insert into class_sessions(institution_id,class_id,group_id,date) values($1,$2,$4,current_date),($1,$3,$4,current_date-interval '1 year') returning id", [tenant, classes[0].id, oldClass, groups[0].id])).rows;
  await q("insert into attendances(institution_id,class_session_id,student_id,attendance_status_id) values($1,$2,$4,501),($1,$3,$4,(select id from catalog_attendance_statuses where code='AUS'))", [tenant, sessions[0].id, sessions[1].id, student]);
  assert.equal(Number((await client.query('select dashboard_attendance_pct() value')).rows[0].value), 100);
  await assert.rejects((await connection(parentUser)).query('select dashboard_attendance_pct($1)', [otherStudent]), { code: '42501' });
  const periods = (await q("insert into academic_periods(institution_id,academic_year_id,name) values($1,$2,'Current'),($1,$3,'Past') returning id", [tenant, year, oldYear])).rows;
  const evaluations = (await q('insert into evaluations(institution_id,class_id,academic_period_id,max_score,weight,published) values($1,$2,$4,100,1,true),($1,$3,$5,100,1,true) returning id', [tenant, classes[0].id, oldClass, periods[0].id, periods[1].id])).rows;
  await q('insert into grades(institution_id,evaluation_id,student_id,score) values($1,$2,$4,80),($1,$3,$4,0)', [tenant, evaluations[0].id, evaluations[1].id, student]);
  assert.equal(Number((await client.query('select dashboard_institutional_average() value')).rows[0].value), 8);
  const parent = await connection(parentUser);
  assert.equal(Number((await parent.query('select dashboard_student_average($1) value', [student])).rows[0].value), 80);
  await q("insert into grade_visibility_rules(institution_id,scope,user_id,academic_period_id,allowed) values($1,'user',$2,$3,false)", [tenant, parentUser.id, periods[0].id]);
  await assert.rejects(parent.query('select dashboard_student_average($1)', [student]), { code: '42501' });
});

test('assignment feed paginates ties and null dates, filters before paging and keeps student scope', async () => {
  const q = (sql, args) => db.admin.query(sql, args);
  let year = (await q('select id from academic_years where institution_id=$1 and is_current order by id limit 1', [tenant])).rows[0]?.id;
  if (!year) year = (await q("insert into academic_years(institution_id,name,year,is_current) values($1,'Feed',2026,true) returning id", [tenant])).rows[0].id;
  let group = (await q('select group_id from enrollments where institution_id=$1 and student_id=$2 and academic_year_id=$3', [tenant, student, year])).rows[0]?.group_id;
  if (!group) {
    group = (await q("insert into groups(institution_id,academic_year_id,name) values($1,$2,'Feed') returning id", [tenant, year])).rows[0].id;
    await q("insert into enrollments(institution_id,academic_year_id,student_id,group_id,enrollment_status_id) select $1,$2,$3,$4,id from catalog_enrollment_statuses where code='ACT'", [tenant, year, student, group]);
  }
  const classId = (await q('insert into classes(institution_id,academic_year_id,group_id) values($1,$2,$3) returning id', [tenant, year, group])).rows[0].id;
  const parent = await connection(parentUser);
  const beforeCounters = (await parent.query('select assignment_counters($1) value', [student])).rows[0].value;
  const tasks = (await q("insert into assignments(institution_id,class_id,title,due_at,kind,published) select $1,$2,'Feed '||i,case when i>6 then null else now()+interval '2 days' end,case when i=3 then 'exam' else 'homework' end,i<>5 from generate_series(1,8) i returning id", [tenant, classId])).rows;
  const client = await connection();
  const read = async (cursor = null) => (await client.query('select assignment_feed(p_class_id=>$1,p_limit=>2,p_after_due_at=>$2,p_after_id=>$3) value', [classId, cursor?.dueAt ?? null, cursor?.id ?? null])).rows[0].value;
  const ids = []; let cursor = null;
  do { const page = await read(cursor); ids.push(...page.assignments.map(a => a.id)); cursor = page.nextCursor; } while (cursor);
  assert.deepEqual(ids, tasks.map(t => t.id)); assert.equal(new Set(ids).size, 8);
  const searched = (await client.query("select assignment_feed(p_class_id=>$1,p_search=>'Feed 3',p_limit=>1) value", [classId])).rows[0].value;
  assert.equal(searched.assignments.length, 1); assert.equal(searched.assignments[0].kind, 'exam');
  assert.equal(searched.nextCursor, null);
  const exams = (await client.query("select assignment_feed(p_class_id=>$1,p_kinds=>array['exam'],p_limit=>1) value", [classId])).rows[0].value;
  assert.equal(exams.assignments[0].id, tasks[2].id);
  const page = (await parent.query('select assignment_feed(p_student_id=>$1,p_class_id=>$2,p_limit=>100) value', [student, classId])).rows[0].value;
  assert.equal(page.assignments.length, 7);
  assert.ok(!page.assignments.some(a => a.id === tasks[4].id));
  assert.ok(page.assignments.every(a => a.progress && a.progress.status === null));
  await assert.rejects(parent.query('select assignment_feed(p_student_id=>$1)', [otherStudent]), { code: '42501' });
  await assert.rejects(client.query('select assignment_feed(p_limit=>101)'), { code: '22023' });
  const counters = (await parent.query('select assignment_counters($1) value', [student])).rows[0].value;
  assert.equal(counters.pending, beforeCounters.pending + 7); assert.equal(counters.submitted, beforeCounters.submitted);
  const period = (await q("insert into academic_periods(institution_id,academic_year_id,name) values($1,$2,'Feed grades') returning id", [tenant, year])).rows[0].id;
  const evaluation = (await q('insert into evaluations(institution_id,class_id,academic_period_id,assignment_id,max_score,weight,published) values($1,$2,$3,$4,100,1,true) returning id', [tenant, classId, period, tasks[2].id])).rows[0].id;
  const type = async () => (await q('select t.code from evaluations e join catalog_evaluation_types t on t.id=e.evaluation_type_id where e.id=$1', [evaluation])).rows[0].code;
  assert.equal(await type(), 'EXM');
  await q("update assignments set kind='project' where id=$1", [tasks[2].id]);
  assert.equal(await type(), 'PRO');
  await q("insert into submissions(institution_id,assignment_id,student_id,task_status_id) select $1,$2,$3,id from catalog_task_statuses where code='CALI'", [tenant, tasks[2].id, student]);
  await q('insert into grades(institution_id,evaluation_id,student_id,score) values($1,$2,$3,80)', [tenant, evaluation, student]);
  const progress = async () => (await parent.query('select assignment_feed(p_student_id=>$1,p_class_id=>$2,p_search=>\'Feed 3\') value', [student, classId])).rows[0].value.assignments[0].progress;
  assert.deepEqual(await progress(), { status: 'graded', score: 80 });
  await q("insert into grade_visibility_rules(institution_id,scope,user_id,academic_period_id,allowed) values($1,'user',$2,$3,false)", [tenant, parentUser.id, period]);
  assert.deepEqual(await progress(), { status: 'graded', score: null });
  const open = (await parent.query('select assignment_feed(p_student_id=>$1,p_class_id=>$2,p_only_open=>true,p_limit=>100) value', [student, classId])).rows[0].value;
  assert.ok(!open.assignments.some(a => a.id === tasks[2].id));
  assert.equal(open.assignments.length, 6);
  const updated = (await parent.query('select assignment_counters($1) value', [student])).rows[0].value;
  assert.equal(updated.pending, beforeCounters.pending + 6); assert.equal(updated.graded, beforeCounters.graded + 1);
});
test('report context respects period dates, missing attendance and student/report scope', async () => {
  const q = (sql, args) => db.admin.query(sql, args);
  const year = (await q('select id from academic_years where institution_id=$1 and is_current', [tenant])).rows[0].id;
  const classRow = (await q('select id,group_id from classes where institution_id=$1 and academic_year_id=$2 order by id limit 1', [tenant, year])).rows[0];
  const period = (await q("insert into academic_periods(institution_id,academic_year_id,name,start_date,end_date) values($1,$2,'Report dates','2026-03-01','2026-03-31') returning id", [tenant, year])).rows[0].id;
  const client = await connection();
  const read = async (user = client, child = student) => (await user.query('select student_report_context($1,$2) value', [child, period])).rows[0].value;
  assert.equal((await read()).attendancePct, null);
  const sessions = (await q("insert into class_sessions(institution_id,class_id,group_id,date) values($1,$2,$3,'2026-03-01'),($1,$2,$3,'2026-03-02'),($1,$2,$3,'2026-04-01') returning id", [tenant, classRow.id, classRow.group_id])).rows;
  for (const [i, session] of sessions.entries()) {
    await q('insert into attendances(institution_id,class_session_id,student_id,attendance_status_id) select $1,$2,$3,id from catalog_attendance_statuses where code=$4', [tenant, session.id, student, i === 0 ? 'PRE' : 'AUS']);
  }
  const result = await read();
  assert.equal(result.attendancePct, 50); assert.equal(result.rank, null); assert.equal(result.totalPeers, null);
  const parent = await connection(parentUser);
  assert.equal((await read(parent)).attendancePct, 50);
  await assert.rejects(read(parent, otherStudent), {code:'42501'});
  await q("insert into grade_visibility_rules(institution_id,scope,user_id,academic_period_id,allowed) values($1,'user',$2,$3,false)", [tenant, parentUser.id, period]);
  await assert.rejects(read(parent), {code:'42501'});
  await q("update users set admin_permissions=array['dashboard.view'] where id=$1", [adminUser.id]);
  await assert.rejects(read(), {code:'42501'});
  await q('update users set admin_permissions=null where id=$1', [adminUser.id]);
});
test('chat aggregates all unread messages, paginates and atomically confirms missing reads', async () => {
  const admin = await connection(), parent = await connection(parentUser);
  const ensure = (client, user) => client.query('select chat_ensure_individual($1) id', [user]);
  const [a,b] = await Promise.all([ensure(admin,parentUser.id),ensure(parent,adminUser.id)]);
  const id = a.rows[0].id; assert.equal(id,b.rows[0].id);
  assert.equal((await db.admin.query('select count(*) from conversation_participants where conversation_id=$1',[id])).rows[0].count,'2');
  await db.admin.query("insert into messages(conversation_id,sender_id,content,created_at) select $1,$2,'Message '||i,'2026-01-01'::timestamptz from generate_series(1,1105) i",[id,parentUser.id]);
  const inbox = async () => (await admin.query('select chat_conversations() value')).rows[0].value;
  const first = await inbox(); assert.equal(first.totalUnread,1105); assert.equal(first.conversations[0].unreadCount,1105);
  assert.equal(first.conversations[0].lastMessage.content,'Message 1105');
  const ids=[];let before=null;
  do {
    const page=(await admin.query('select chat_messages($1,p_limit=>100,p_before_id=>$2) value',[id,before])).rows[0].value;
    ids.push(...page.messages.map(m=>m.id));before=page.hasMore?page.nextBeforeId:null;
  }while(before);
  assert.equal(ids.length,1105);assert.equal(new Set(ids).size,1105);
  const last=first.conversations[0].lastMessage.id;
  await admin.query('select chat_mark_read($1)',[id]);
  assert.equal((await inbox()).totalUnread,0);
  const readCount=async()=> (await db.admin.query('select count(*) from message_reads where user_id=$1',[adminUser.id])).rows[0].count;
  assert.equal(await readCount(),'1105');
  await admin.query('select chat_mark_read($1)',[id]);assert.equal(await readCount(),'1105');
  await db.admin.query("insert into messages(conversation_id,sender_id,content) values($1,$2,'New')",[id,parentUser.id]);
  const delta=(await admin.query('select chat_messages($1,p_after_id=>$2) value',[id,last])).rows[0].value;
  assert.equal(delta.messages.length,1); assert.equal(delta.messages[0].content,'New');
  assert.equal((await inbox()).totalUnread,1);
  const outsider=await connection(teacherUser);
  await assert.rejects(outsider.query('select chat_messages($1)',[id]),{code:'42501'});
  await assert.rejects(outsider.query('select chat_mark_read($1)',[id]),{code:'42501'});
  assert.equal((await outsider.query('select chat_conversations() value')).rows[0].value.conversations.length,0);
  await assert.rejects(admin.query('select chat_messages($1,p_before_id=>1,p_after_id=>2)',[id]),{code:'22023'});
});
test('chat conversation cursors and search paginate before hydration and preserve global unread', async () => {
  const client=await connection();
  const previous=(await client.query('select chat_ensure_individual($1) id',[parentUser.id])).rows[0].id;
  await db.admin.query("insert into messages(conversation_id,sender_id,content) values($1,$2,'Unread fixture')",[previous,parentUser.id]);
  await client.query('select chat_ensure_individual($1)',[teacherUser.id]);
  const first=(await client.query('select chat_conversations(p_limit=>1) value')).rows[0].value;
  assert.equal(first.conversations.length,1); assert.ok(first.nextCursor);
  const next=(await client.query('select chat_conversations(p_limit=>1,p_after_updated_at=>$1,p_after_id=>$2) value',[first.nextCursor.updatedAt,first.nextCursor.id])).rows[0].value;
  assert.equal(next.conversations.length,1);assert.notEqual(first.conversations[0].id,next.conversations[0].id);
  assert.equal(next.nextCursor,null);assert.equal(first.totalUnread,next.totalUnread);
  const search=(await client.query("select chat_conversations(p_search=>'teacher',p_limit=>1) value")).rows[0].value;
  assert.equal(search.conversations.length,1);assert.equal(search.totalUnread,first.totalUnread);
  await db.admin.query('update users set active=false where id=$1',[adminUser.id]);
  await assert.rejects(client.query('select chat_conversations()'),{code:'42501'});
  await db.admin.query('update users set active=true where id=$1',[adminUser.id]);
});
test('service-only request context shares quotas across connections and keeps live session/MFA/portal checks', async () => {
  const session=randomUUID();
  await db.admin.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,parentUser.auth]);
  const a=await db.connect(),b=await db.connect();
  await a.query('set role service_role');await b.query('set role service_role');
  const read=(client,limit=3,sid=session)=>client.query('select backend_request_context($1,$2,900000,$3) value',[parentUser.auth,sid,limit]);
  const contexts=await Promise.all([read(a),read(b),read(a),read(b)]);
  assert.equal(contexts.filter(r=>r.rows[0].value.allowed).length,3);
  const denied=contexts.find(r=>!r.rows[0].value.allowed).rows[0].value;
  assert.equal(denied.remaining,0);assert.ok(denied.retryAfterSeconds>0);
  const context=contexts.find(r=>r.rows[0].value.allowed).rows[0].value;
  assert.deepEqual(context.roles,['parent']);assert.ok(context.parentId);assert.equal(context.authUserId,parentUser.auth);
  const ordinary=await connection(parentUser);
  await assert.rejects(ordinary.query('select backend_request_context($1,$2)',[parentUser.auth,session]),{code:'42501'});
  await assert.rejects(ordinary.query('select * from backend_user_quotas'),{code:'42501'});
  await db.admin.query("update backend_user_quotas set resets_at=now()-interval '1 second' where user_id=$1",[parentUser.id]);
  assert.equal((await read(a)).rows[0].value.remaining,2);
  await db.admin.query("insert into portal_permission_rules(institution_id,scope,user_id,permission,allowed) values($1,'user',$2,'payments.view',false)",[tenant,parentUser.id]);
  assert.equal((await read(a)).rows[0].value.portalPermissions['payments.view'],false);
  await db.admin.query('delete from portal_permission_rules where user_id=$1',[parentUser.id]);
  await assert.rejects(read(a,3,randomUUID()),{code:'28000'});
  await db.admin.query('insert into auth_two_factor_settings(user_id,enabled,method) values($1,true,\'totp\')',[parentUser.id]);
  await assert.rejects(read(a),{code:'42501',detail:'two_factor_required'});
  await db.admin.query('insert into auth_two_factor_verified_sessions(session_id,user_id) values($1,$2)',[session,parentUser.id]);
  assert.equal((await read(a)).rows[0].value.allowed,true);
  await db.admin.query('update users set active=false where id=$1',[parentUser.id]);
  await assert.rejects(read(a),{code:'42501'});
  await db.admin.query('update users set active=true where id=$1',[parentUser.id]);
  await db.admin.query('update auth_two_factor_settings set enabled=false where user_id=$1',[parentUser.id]);
  await db.admin.query('delete from auth.sessions where id=$1',[session]);
  await assert.rejects(read(a),{code:'28000'});
});
test('request context accepts global system roles and immediately observes role and institution revocation', async () => {
  const session=randomUUID();
  await db.admin.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,teacherUser.auth]);
  const original=(await db.admin.query('select role_id,institution_id from user_roles where user_id=$1',[teacherUser.id])).rows;
  await db.admin.query('delete from user_roles where user_id=$1',[teacherUser.id]);
  await db.admin.query("insert into user_roles(user_id,role_id,institution_id) select $1,id,null from roles where institution_id is null and code='teacher' order by id limit 1",[teacherUser.id]);
  const client=await db.connect();await client.query('set role service_role');
  const read=()=>client.query('select backend_request_context($1,$2) value',[teacherUser.auth,session]);
  assert.deepEqual((await read()).rows[0].value.roles,['teacher']);
  await db.admin.query('delete from user_roles where user_id=$1',[teacherUser.id]);
  await assert.rejects(read(),{code:'42501'});
  for (const row of original) await db.admin.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)',[teacherUser.id,row.role_id,row.institution_id]);
  await db.admin.query('update institutions set active=false where id=$1',[tenant]);
  await assert.rejects(read(),{code:'42501'});
  await db.admin.query('update institutions set active=true where id=$1',[tenant]);
});
async function seedPagedStudents(){
  const ids=(await db.admin.query("insert into persons(institution_id,first_name,last_name,email) select $1,'Paged '||lpad(i::text,4,'0'),'Person','page'||i||'@test.invalid' from generate_series(1,1105) i returning id",[tenant])).rows.map(r=>r.id);
  await db.admin.query('insert into students(institution_id,person_id) select $1,unnest($2::bigint[])',[tenant,ids]);
  return ids;
}
async function seedProfileUsers(){
  const users=(await db.admin.query("insert into users(institution_id,email,full_name) select $1,'profile'||i||'@test.invalid',case when i=1105 then 'Admin beyond 1000' else 'Ordinary user '||i end from generate_series(1,1105) i returning id",[tenant])).rows;
  const studentRole=(await db.admin.query("select id from roles where code='student' and institution_id is null order by id limit 1")).rows[0].id;
  const adminRole=(await db.admin.query("select id from roles where code='admin' and institution_id is null order by id limit 1")).rows[0].id;
  await db.admin.query('insert into user_roles(user_id,role_id,institution_id) select unnest($1::bigint[]),$2,$3',[users.slice(0,-1).map(u=>u.id),studentRole,tenant]);
  await db.admin.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)',[users.at(-1).id,adminRole,tenant]);
  return users;
}

test('admin people search filters before paging beyond 1000 records and hydrates current relationships only', async () => {
  await seedPagedStudents();
  const client=await db.connect();await client.query('set role service_role');
  const query=(search=null,page=1)=>client.query('select admin_people_page($1,\'students\',$2,p_page=>$3,p_page_size=>100) value',[tenant,search,page]);
  const searched=(await query('page1105@test.invalid')).rows[0].value;
  assert.equal(searched.pageInfo.total,1);assert.equal(searched.items.length,1);assert.equal(searched.items[0].persons.email,'page1105@test.invalid');
  const names=[];let page=1,info;
  do {const data=(await query('Paged',page++)).rows[0].value;info=data.pageInfo;names.push(...data.items.map(p=>p.id));}while(info.hasNextPage);
  assert.equal(info.total,1105);assert.equal(names.length,1105);assert.equal(new Set(names).size,1105);
  const parent=(await client.query('select admin_people_page($1,\'parents\') value',[tenant])).rows[0].value.items[0];
  assert.ok(parent.child_ids.includes(student));assert.ok(parent.children.some(c=>c.id===student));
  const scope=(await client.query('select admin_people_page($1,\'students\') value',[999999])).rows[0].value;
  assert.equal(scope.items.length,0);assert.equal(scope.pageInfo.total,0);
  await assert.rejects((await connection()).query('select admin_people_page($1,\'students\')',[tenant]),{code:'42501'});
});
test('directory options and catalog stay bounded, preserve selections and count groups without downloading students', async () => {
  const selectedPerson=(await db.admin.query("insert into persons(institution_id,first_name,last_name,email) values($1,'Selected','Student','page1105@test.invalid') returning id",[tenant])).rows[0].id;
  await db.admin.query('insert into students(institution_id,person_id) values($1,$2)',[tenant,selectedPerson]);
  const year=(await db.admin.query('select id from academic_years where institution_id=$1 and is_current',[tenant])).rows[0].id;
  const group=(await db.admin.query("insert into groups(institution_id,academic_year_id,name) values($1,$2,'Catalog group') returning id",[tenant,year])).rows[0].id;
  const classes=(await db.admin.query('insert into classes(institution_id,academic_year_id,group_id) select $1,$2,$3 from generate_series(1,105) returning id',[tenant,year,group])).rows;
  const client=await db.connect();await client.query('set role service_role');
  const options=(await client.query("select admin_directory_options($1,'classes',p_include_ids=>$2) value",[tenant,[classes.at(-1).id]])).rows[0].value;
  assert.ok(options.items.length<=50);assert.ok(options.selected.some(item=>item.id===classes.at(-1).id));
  const beyond=(await client.query("select admin_directory_options($1,'students',p_search=>'page1105@test.invalid') value",[tenant])).rows[0].value;
  assert.equal(beyond.items.length,1);assert.equal(beyond.pageInfo.total,1);
  const catalog=(await client.query("select admin_catalog_page($1,p_group_id=>$2) value",[tenant,group])).rows[0].value;
  assert.equal(catalog.classes.length,50);assert.equal(catalog.people.length,0);assert.equal(catalog.pageInfo.total,105);
  assert.equal(catalog.groups[0].class_count,105);assert.equal(catalog.groups[0].student_count,0);
  const empty=(await db.admin.query("insert into groups(institution_id,academic_year_id,name) values($1,$2,'Empty catalog group') returning id",[tenant,year])).rows[0].id;
  const detail=(await client.query("select admin_catalog_page($1,p_group_id=>$2) value",[tenant,empty])).rows[0].value;
  assert.equal(detail.classes.length,0);assert.equal(detail.groups[0].id,Number(empty));
  await assert.rejects((await connection()).query("select admin_directory_options($1,'students')",[tenant]),{code:'42501'});
});

test('administrative profile filtering occurs before pagination and counts include records after 1000 users', async () => {
  const users=await seedProfileUsers();
  await seedPagedStudents();
  const client=await db.connect();await client.query('set role service_role');
  const result=(await client.query("select admin_profiles_page($1,p_search=>'Admin beyond') value",[tenant])).rows[0].value;
  assert.equal(result.items.length,1);assert.equal(result.items[0].id,Number(users.at(-1).id));assert.equal(result.pageInfo.total,1);
  const counts=(await client.query('select admin_directory_counts($1) value',[tenant])).rows[0].value;
  assert.equal(counts.student,1107);assert.equal(counts.admin,2);
  await assert.rejects((await connection()).query('select admin_profiles_page($1)',[tenant]),{code:'42501'});
});
test('contact search reaches users beyond 1000 and never exposes another tenant', async () => {
  await seedProfileUsers();
  const client=await connection(parentUser);
  const contacts=(await client.query("select chat_contacts('Admin beyond') value")).rows[0].value.contacts;
  assert.equal(contacts.length,1);assert.equal(contacts[0].name,'Admin beyond 1000');
  const tenant2=(await db.admin.query("insert into institutions(code,name) values('CONTACT-OTHER','Other contact tenant') returning id")).rows[0].id;
  await db.admin.query("insert into users(institution_id,email,full_name) values($1,'other@fixture.invalid','Admin beyond another tenant')",[tenant2]);
  assert.equal((await client.query("select chat_contacts('Admin beyond') value")).rows[0].value.contacts.length,1);
  assert.ok((await client.query("select chat_contacts('Maestro') value")).rows[0].value.contacts.some(c=>c.userId===teacherUser.id));
});

test('teacher dashboard keeps only current assigned classes while management retains history', async () => {
  const teacher=(await db.admin.query('select id from teachers where institution_id=$1 and person_id=$2',[tenant,teacherUser.personId])).rows[0].id;
  const current=(await db.admin.query('select id from academic_years where institution_id=$1 and is_current',[tenant])).rows[0].id;
  const old=(await db.admin.query('select id from academic_years where institution_id=$1 and not is_current order by id limit 1',[tenant])).rows[0].id;
  const group=(await db.admin.query('select id from groups where institution_id=$1 and academic_year_id=$2 order by id limit 1',[tenant,current])).rows[0].id;
  const classes=(await db.admin.query('insert into classes(institution_id,teacher_id,group_id,academic_year_id) values($1,$2,$3,$4),($1,$2,$3,$5) returning id',[tenant,teacher,group,current,old])).rows;
  const client=await connection(teacherUser);
  const data=(await client.query('select teacher_dashboard_classes() value')).rows[0].value;
  assert.ok(data.classes.some(c=>String(c.classId)===classes[0].id));
  assert.ok(!data.classes.some(c=>String(c.classId)===classes[1].id));
  assert.ok(data.classes.every(c=>String(c.academicYearId)===current));
});

test('issued report list deduplicates in SQL before paging and respects parent grade visibility', async () => {
  const year=(await db.admin.query('select id from academic_years where institution_id=$1 and is_current',[tenant])).rows[0].id;
  const period=(await db.admin.query("insert into academic_periods(institution_id,academic_year_id,name) values($1,$2,'Issued reports') returning id",[tenant,year])).rows[0].id;
  await db.admin.query("insert into report_cards(institution_id,student_id,academic_period_id,overall_average,generated_at,status) select $1,$2,$3,80,now()+i*interval '1 second','generated' from generate_series(1,1105) i",[tenant,student,period]);
  const other=(await db.admin.query("insert into report_cards(institution_id,student_id,academic_period_id,overall_average,generated_at,status) values($1,$2,$3,70,now(),'generated') returning id",[tenant,otherStudent,period])).rows[0].id;
  const client=await connection();
  const first=(await client.query('select latest_report_cards(p_period_id=>$1,p_page_size=>1) value',[period])).rows[0].value;
  assert.equal(first.pageInfo.total,2);assert.equal(first.reportCards.length,1);assert.equal(first.pageInfo.hasNextPage,true);
  const second=(await client.query('select latest_report_cards(p_period_id=>$1,p_page_size=>1,p_page=>2) value',[period])).rows[0].value;
  assert.equal(second.reportCards[0].id,other);
  const parent=await connection(parentUser);
  const mine=(await parent.query('select latest_report_cards(p_student_id=>$1,p_period_id=>$2) value',[student,period])).rows[0].value;
  assert.equal(mine.reportCards.length,1);
  await assert.rejects(parent.query('select latest_report_cards(p_student_id=>$1)',[otherStudent]),{code:'42501'});
  await db.admin.query("insert into grade_visibility_rules(institution_id,scope,user_id,academic_period_id,allowed) values($1,'user',$2,$3,false)",[tenant,parentUser.id,period]);
  assert.equal((await parent.query('select latest_report_cards(p_student_id=>$1,p_period_id=>$2) value',[student,period])).rows[0].value.reportCards.length,0);
});

async function scheduleFixture() {
  const q=(sql,args)=>db.admin.query(sql,args);
  const year=(await q('select id from academic_years where institution_id=$1 and is_current',[tenant])).rows[0].id;
  const person=(await q("insert into persons(institution_id,first_name,last_name) values($1,'Schedule','Teacher') returning id",[tenant])).rows[0].id;
  const teacher=(await q('insert into teachers(institution_id,person_id) values($1,$2) returning id',[tenant,person])).rows[0].id;
  const groups=(await q("insert into groups(institution_id,academic_year_id,name) values($1,$2,'Schedule A'),($1,$2,'Schedule B') returning id",[tenant,year])).rows.map(r=>r.id);
  const classes=(await q('insert into classes(institution_id,academic_year_id,group_id,teacher_id) values($1,$2,$3,$5),($1,$2,$4,$5) returning id',[tenant,year,...groups,teacher])).rows.map(r=>r.id);
  const write=async(client,payload,action='create',id=null)=>(await client.query('select schedule_write($1,$2,$3::jsonb,$4) value',[tenant,action,JSON.stringify(payload),id])).rows[0].value;
  const payload=(classId,day=1)=>({kind:'class',classId,weekdayIds:[day],startTime:'08:00',endTime:'09:00'});
  return {year,teacher,groups,classes,write,payload};
}

test('schedule exclusion serializes concurrent teacher/group writes and accepts adjacent slots',async()=>{
  const f=await scheduleFixture(),a=await connection(),b=await connection();
  const results=await Promise.allSettled([f.write(a,f.payload(f.classes[0])),f.write(b,f.payload(f.classes[1]))]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(results.find(r=>r.status==='rejected').reason.code,'23P01');
  const winner=results.find(r=>r.status==='fulfilled').value.schedules[0];
  await f.write(a,{...f.payload(f.classes[0]),startTime:'09:00',endTime:'10:00'});
  await assert.rejects(f.write(a,{...f.payload(f.classes[0]),startTime:'08:59',endTime:'09:30'}),{code:'23P01'});
  const updated=await f.write(a,{shift:'morning'},'update',winner.id);
  assert.equal(updated.schedule.startTime,'08:00');assert.equal(updated.schedule.shift,'morning');
});

test('schedule batch rolls back earlier days and newly created rooms on a later conflict',async()=>{
  const f=await scheduleFixture(),a=await connection();
  await f.write(a,f.payload(f.classes[0],2));
  await assert.rejects(f.write(a,{...f.payload(f.classes[1]),weekdayIds:[1,2],room:'Atomic room fixture'}),{code:'23P01'});
  assert.equal((await db.admin.query('select count(*) from schedules where class_id=$1',[f.classes[1]])).rows[0].count,'0');
  assert.equal((await db.admin.query("select count(*) from classrooms where name='Atomic room fixture'")).rows[0].count,'0');
  await assert.rejects(f.write(a,{kind:'break',weekdayIds:[2],startTime:'08:30',endTime:'08:45'}),{code:'23P01'});
  await assert.rejects(f.write(a,{...f.payload(f.classes[0]),startTime:'08:00:30'}),{code:'22023'});
});

test('physical room names and class reassignment cannot bypass schedule conflicts',async()=>{
  const f=await scheduleFixture(),g=await scheduleFixture(),a=await connection();
  await f.write(a,{...f.payload(f.classes[0],3),room:' Shared Fixture Room '});
  await assert.rejects(g.write(a,{...g.payload(g.classes[0],3),room:'shared fixture room'}),{code:'23P01'});
  await g.write(a,g.payload(g.classes[0],3));
  await assert.rejects(db.admin.query('update classes set teacher_id=$1 where id=$2',[f.teacher,g.classes[0]]),{code:'23P01'});
  assert.equal((await db.admin.query('select teacher_id from classes where id=$1',[g.classes[0]])).rows[0].teacher_id,g.teacher);
  // A forged denormalized teacher ID is recomputed by the trigger.
  await db.admin.query('update schedules set teacher_id=null where class_id=$1',[f.classes[0]]);
  assert.equal((await db.admin.query('select teacher_id from schedules where class_id=$1',[f.classes[0]])).rows[0].teacher_id,f.teacher);
});

test('schedule filtering happens before paging; parent scope, MFA and explicit administrative grants remain enforced',async()=>{
  const f=await scheduleFixture(),a=await connection();
  await f.write(a,{...f.payload(f.classes[0],4),weekdayIds:[4,5]});
  const list=async(client,filters,mine=false,studentId=null)=>(await client.query('select schedule_list($1,$2::jsonb,$3,$4) value',[tenant,JSON.stringify(filters),mine,studentId])).rows[0].value;
  const page=await list(a,{groupId:f.groups[0],pageSize:1});
  assert.equal(page.schedules.length,1);assert.equal(page.pageInfo.total,2);assert.equal(page.pageInfo.hasNextPage,true);
  assert.equal((await list(a,{groupId:f.groups[0],weekdayId:5})).schedules.length,1);
  const parent=await connection(parentUser);
  await assert.rejects(list(parent,{}),{code:'42501'});
  await assert.rejects(list(parent,{},true,otherStudent),{code:'42501'});
  await assert.rejects(f.write(parent,f.payload(f.classes[1],6)),{code:'42501'});
  await db.admin.query("update users set admin_permissions=array['schedules.view'] where id=$1",[adminUser.id]);
  await assert.rejects(f.write(a,f.payload(f.classes[1],6)),{code:'42501'});
  assert.equal((await list(a,{groupId:f.groups[0]})).schedules.length,2);
  await db.admin.query('update users set admin_permissions=null where id=$1',[adminUser.id]);
  await assert.rejects(parent.query('select schedule_view($1)',[page.schedules[0].id]),{code:'42501'});
  await assert.rejects(parent.query('select teacher_dashboard_classes()'),{code:'42501'});
});

test('a full assigned week exceeds 1000 slots without truncation and excludes historical schedules',async()=>{
  const f=await scheduleFixture(),a=await connection(),parent=await connection(parentUser),teacher=await connection(teacherUser);
  const owner=(await db.admin.query('select id from teachers where person_id=$1 and institution_id=$2',[teacherUser.personId,tenant])).rows[0].id;
  await db.admin.query('update classes set teacher_id=$1 where id=$2',[owner,f.classes[0]]);
  await db.admin.query("insert into schedules(institution_id,class_id,weekday_id,start_time,end_time) select $1,$2,7,time '00:00'+i*interval '1 minute',time '00:00'+(i+1)*interval '1 minute' from generate_series(0,1104) i",[tenant,f.classes[0]]);
  const before=(await db.admin.query('select id,group_id from enrollments where student_id=$1 and academic_year_id=$2',[student,f.year])).rows[0];
  await db.admin.query('update enrollments set group_id=$1 where id=$2',[f.groups[0],before.id]);
  try {
    const mine=async(client,id=null)=>(await client.query("select schedule_list($1,'{}',true,$2) value",[tenant,id])).rows[0].value.schedules;
    assert.equal((await mine(parent,student)).length,1105);
    assert.equal((await mine(teacher)).length,1105);
    const page=(await a.query('select schedule_list($1,$2::jsonb) value',[tenant,JSON.stringify({groupId:f.groups[0],page:12,pageSize:100})])).rows[0].value;
    assert.equal(page.pageInfo.total,1105);assert.equal(page.schedules.length,5);assert.equal(page.pageInfo.hasNextPage,false);
    const oldYear=(await db.admin.query('select id from academic_years where institution_id=$1 and not is_current order by id limit 1',[tenant])).rows[0].id;
    const oldGroup=(await db.admin.query("insert into groups(institution_id,academic_year_id,name) values($1,$2,'Old timetable') returning id",[tenant,oldYear])).rows[0].id;
    const oldClass=(await db.admin.query('insert into classes(institution_id,academic_year_id,group_id,teacher_id) values($1,$2,$3,$4) returning id',[tenant,oldYear,oldGroup,owner])).rows[0].id;
    await db.admin.query("insert into schedules(institution_id,class_id,weekday_id,start_time,end_time) values($1,$2,7,'08:00','09:00')",[tenant,oldClass]);
    assert.equal((await mine(teacher)).length,1105);
    assert.equal((await mine(parent,student)).length,1105);
    await assert.rejects(f.write(a,f.payload(oldClass)),{code:'22023'});
  } finally {await db.admin.query('update enrollments set group_id=$1 where id=$2',[before.group_id,before.id]);}
});

test('read-only schedule preflight identifies a legacy overlap without deleting source data',async()=>{
  const f=await scheduleFixture(),client=await connection();
  await f.write(client,f.payload(f.classes[0]));
  const script=await readFile(new URL('../scripts/schedules-preflight.sql',import.meta.url),'utf8');
  const clean=await db.admin.query(script);
  assert.equal(clean[0].rows.length,0);assert.equal(clean[1].rows.length,0);
  await db.admin.query('begin');
  try {
    // Simulate the pre-migration schema/data inside a rolled-back local transaction.
    await db.admin.query('alter table schedules drop constraint schedules_group_overlap, drop constraint schedules_teacher_overlap, drop constraint schedules_room_overlap');
    const inserted=(await db.admin.query("insert into schedules(institution_id,class_id,weekday_id,start_time,end_time) values($1,$2,1,'08:30','09:30') returning id",[tenant,f.classes[0]])).rows[0].id;
    const result=await db.admin.query(script);
    assert.ok(result[1].rows.some(r=>r.first_id===inserted||r.second_id===inserted));
    assert.equal((await db.admin.query('select count(*) from schedules where id=$1',[inserted])).rows[0].count,'1');
  } finally {await db.admin.query('rollback');}
});

test('RLS statement helpers use one-time plans while row-dependent grants keep tenant and MFA isolation',async()=>{
  await db.admin.query("insert into persons(institution_id,first_name,last_name) select $1,'RLS '||n,'Fixture' from generate_series(1,1105) n",[tenant]);
  await db.admin.query("insert into auth_two_factor_settings(user_id,enabled,method) values($1,false,'totp')",[adminUser.id]);
  const client=await connection(),plan=(await client.query('explain (analyze,verbose,buffers,format json) select id from persons where institution_id=$1',[tenant])).rows[0]['QUERY PLAN'][0].Plan;
  const nodes=[];
  function visit(node){nodes.push(node);for(const child of node.Plans??[])visit(child);} visit(plan);
  const mfa=nodes.filter(n=>n['Subplan Name']?.startsWith('InitPlan')&&n.Output?.some(s=>s.includes('auth_2fa_session_allowed')));
  assert.ok(mfa.length>0,JSON.stringify(plan));assert.ok(mfa.every(n=>n['Actual Loops']===1));
  assert.ok(plan['Actual Rows']>1000);
  assert.equal((await (await connection(adminUser,999999)).query('select id from persons')).rows.length,0);
  await db.admin.query("update auth_two_factor_settings set enabled=true where user_id=$1",[adminUser.id]);
  try {assert.equal((await client.query('select id from persons')).rows.length,0);}
  finally {await db.admin.query('update auth_two_factor_settings set enabled=false where user_id=$1',[adminUser.id]);}
});

test('mixed parent/admin payments retain actual family scope instead of staff-wide access',async()=>{
  const role=(await db.admin.query("select id from roles where code='admin' and institution_id is null order by id limit 1")).rows[0].id;
  const grant=(await db.admin.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3) returning id',[parentUser.id,role,tenant])).rows[0].id;
  await db.admin.query("update users set admin_permissions=array['dashboard.view'] where id=$1",[parentUser.id]);
  try {
    const client=await connection(parentUser),own=await charge(),other=await charge(otherStudent);
    const key=randomUUID(),receipt=await pay(client,own,10,key);
    assert.deepEqual(await pay(client,own,10,key),receipt);
    await assert.rejects(pay(client,other,10),{code:'42501'});
    assert.equal((await client.query('select id from charges where id=$1',[other])).rows.length,0);
    assert.equal((await client.query('select id from charges where id=$1',[own])).rows.length,1);
    assert.deepEqual((await client.query('select * from payment_charge_totals($1)',[[own,other]])).rows,[{charge_id:own,paid:'10.00'}]);
    await assert.rejects(client.query("insert into payments(institution_id,charge_id,student_id,amount,status) values($1,$2,$3,10,'paid')",[tenant,other,otherStudent]),{code:'42501'});
    await assert.rejects(client.query("select manage_portal_access('delete_permission','{\"id\":999999}')"),{code:'42501'});
    assert.equal((await client.query("select admin_can('roles.edit') value")).rows[0].value,false);
    const superRole=(await db.admin.query("select id from roles where institution_id is null and code='super_admin' order by id limit 1")).rows[0].id;
    await assert.rejects(client.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)',[parentUser.id,superRole,tenant]),{code:'42501'});
    await assert.rejects(client.query('update users set active=false where id=$1',[teacherUser.id]),{code:'42501'});
    assert.equal((await client.query('delete from users where id=$1 returning id',[teacherUser.id])).rows.length,0);
  } finally {
    await db.admin.query('delete from user_roles where id=$1',[grant]);
    await db.admin.query('update users set admin_permissions=null where id=$1',[parentUser.id]);
  }
});

test('role authorization ignores cross-tenant grants and stale JWT roles and observes live revocation',async()=>{
  const otherTenant=(await db.admin.query("insert into institutions(code,name) values('ROLE-SCOPE','Other roles') returning id")).rows[0].id;
  const otherRole=(await db.admin.query("insert into roles(institution_id,name,code) values($1,'Foreign admin','admin') returning id",[otherTenant])).rows[0].id;
  const grant=(await db.admin.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3) returning id',[parentUser.id,otherRole,otherTenant])).rows[0].id;
  const client=await connection(parentUser);
  const check=async()=>(await client.query("select has_role('admin') admin,class_admin_actor() admin_actor,portal_staff($1) staff",[parentUser.id])).rows[0];
  try {
    assert.deepEqual(await check(),{admin:false,admin_actor:false,staff:false});
    await db.admin.query('update user_roles set institution_id=$1 where id=$2',[tenant,grant]);
    assert.deepEqual(await check(),{admin:false,admin_actor:false,staff:false});
    const global=(await db.admin.query("select id from roles where code='admin' and institution_id is null order by id limit 1")).rows[0].id;
    await db.admin.query('update user_roles set role_id=$1,institution_id=$2 where id=$3',[global,otherTenant,grant]);
    assert.deepEqual(await check(),{admin:false,admin_actor:false,staff:false});
    await client.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({sub:parentUser.auth,institution_id:tenant,role:'authenticated',app_metadata:{roles:['super_admin','admin']}})]);
    assert.deepEqual(await check(),{admin:false,admin_actor:false,staff:false});
    await db.admin.query('update user_roles set institution_id=$1 where id=$2',[tenant,grant]);
    assert.deepEqual(await check(),{admin:true,admin_actor:true,staff:true});
    await db.admin.query('delete from user_roles where id=$1',[grant]);
    assert.deepEqual(await check(),{admin:false,admin_actor:false,staff:false});
    await db.admin.query('update institutions set active=false where id=$1',[tenant]);
    assert.equal((await client.query('select current_institution_id() value')).rows[0].value,null);
    assert.equal((await client.query('select id from persons')).rows.length,0);
  } finally {
    await db.admin.query('update institutions set active=true where id=$1',[tenant]);
    await db.admin.query('delete from user_roles where id=$1',[grant]);
  }
});

test('inactive last role revokes both direct data access and the backend request context',async()=>{
  const role=(await db.admin.query("select r.id from roles r join user_roles ur on ur.role_id=r.id where ur.user_id=$1 and r.code='parent'",[parentUser.id])).rows[0].id;
  const client=await connection(parentUser),session=randomUUID();
  await db.admin.query('insert into auth.sessions(id,user_id) values($1,$2)',[session,parentUser.auth]);
  const service=await db.connect();await service.query('set role service_role');
  await db.admin.query('update roles set active=false where id=$1',[role]);
  try {
    assert.equal((await client.query('select current_institution_id() value')).rows[0].value,null);
    assert.equal((await client.query('select id from persons')).rows.length,0);
    await assert.rejects(service.query('select backend_request_context($1,$2)',[parentUser.auth,session]),{code:'42501'});
  } finally {await db.admin.query('update roles set active=true where id=$1',[role]);}
});

test('direct schedule RLS scopes class slots and general breaks to assigned current groups',async()=>{
  const f=await scheduleFixture(),admin=await connection(),parent=await connection(parentUser),teacher=await connection(teacherUser);
  const a=(await f.write(admin,{...f.payload(f.classes[0],6),startTime:'11:00',endTime:'12:00'})).schedules[0];
  const b=(await f.write(admin,{...f.payload(f.classes[1],6),startTime:'12:00',endTime:'13:00'})).schedules[0];
  const pause=(await f.write(admin,{kind:'break',weekdayIds:[6],startTime:'14:00',endTime:'14:30'})).schedules[0];
  const before=(await db.admin.query('select id,group_id from enrollments where student_id=$1 and academic_year_id=$2',[student,f.year])).rows[0];
  await db.admin.query('update enrollments set group_id=$1 where id=$2',[f.groups[0],before.id]);
  try {
    assert.equal((await parent.query('select id from schedules where id=$1',[a.id])).rows.length,1);
    assert.equal((await parent.query('select id from schedules where id=$1',[b.id])).rows.length,0);
    assert.equal((await parent.query('select id from schedules where id=$1',[pause.id])).rows.length,1);
    assert.equal((await teacher.query('select id from schedules where id=$1',[a.id])).rows.length,0);
    await f.write(admin,{},'delete',a.id);
    assert.equal((await parent.query('select id from schedules where id=$1',[pause.id])).rows.length,0);
  } finally {await db.admin.query('update enrollments set group_id=$1 where id=$2',[before.group_id,before.id]);}
});

test('private administrative full-name search uses its expression index with selective server filters',async(t)=>{
  for(let start=1;start<=10000;start+=500){
    await db.admin.query("insert into persons(institution_id,first_name,last_name) select $1,'Indexneedle'||lpad(i::text,5,'0'),'Scalability' from generate_series($2::integer,$3::integer) i",[tenant,start,start+499]);
  }
  await db.admin.query("insert into students(institution_id,person_id) select institution_id,id from persons where institution_id=$1 and last_name='Scalability'",[tenant]);
  await db.admin.query('vacuum (analyze) persons');
  await db.admin.query('vacuum (analyze) students');
  // Explain the private SECURITY DEFINER directory query as its owner. RLS
  // authorization is tested separately, not disabled to accelerate public reads.
  const result=(await db.admin.query("explain (analyze,verbose,buffers,format json) select s.id from students s join persons p on p.id=s.person_id and p.institution_id=s.institution_id where s.institution_id=$1 and p.deleted_at is null and p.first_name||' '||p.last_name ilike '%Indexneedle09876 Scalability%'",[tenant])).rows[0]['QUERY PLAN'][0];
  const names=[];function visit(node){if(node['Index Name'])names.push(node['Index Name']);for(const child of node.Plans??[])visit(child);}visit(result.Plan);
  assert.ok(names.includes('persons_full_name_search'),JSON.stringify(result.Plan));
  assert.equal(result.Plan['Actual Rows'],1);
  const client=await db.connect();await client.query('set role service_role');
  const page=(await client.query("select admin_people_page($1,'students',p_search=>'Indexneedle09876 Scalability') value",[tenant])).rows[0].value;
  assert.equal(page.items.length,1);assert.equal(page.pageInfo.total,1);
  t.diagnostic(`Full-name lookup: ${result['Execution Time']}ms; indexes: ${names.join(', ')}`);
});

test('a mixed teacher/admin retains own class grading without bypassing the limited administrative profile',async()=>{
  const f=await scheduleFixture(),owner=(await db.admin.query('select id from teachers where institution_id=$1 and person_id=$2',[tenant,teacherUser.personId])).rows[0].id;
  await db.admin.query('update classes set teacher_id=$1 where id=$2',[owner,f.classes[0]]);
  const role=(await db.admin.query("select id from roles where institution_id is null and code='admin' order by id limit 1")).rows[0].id;
  const grant=(await db.admin.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3) returning id',[teacherUser.id,role,tenant])).rows[0].id;
  await db.admin.query("update users set admin_permissions=array['dashboard.view'] where id=$1",[teacherUser.id]);
  const evals=(await db.admin.query('insert into evaluations(institution_id,class_id,max_score,published) values($1,$2,100,true),($1,$3,100,true) returning id',[tenant,...f.classes])).rows;
  const assignment=(await db.admin.query("insert into assignments(institution_id,class_id,title,max_score) values($1,$2,'Forbidden class grading',100) returning id",[tenant,f.classes[1]])).rows[0].id;
  const submission=(await db.admin.query('insert into submissions(institution_id,assignment_id,student_id) values($1,$2,$3) returning id',[tenant,assignment,student])).rows[0].id;
  try {
    const client=await connection(teacherUser);
    assert.equal((await client.query("select class_permission($1,'grades.write') value",[f.classes[0]])).rows[0].value,true);
    assert.equal((await client.query("select class_permission($1,'grades.write') value",[f.classes[1]])).rows[0].value,false);
    assert.equal((await client.query('select id from evaluations where id=$1',[evals[0].id])).rows.length,1);
    assert.equal((await client.query('select id from evaluations where id=$1',[evals[1].id])).rows.length,0);
    await client.query('insert into grades(institution_id,evaluation_id,student_id,score) values($1,$2,$3,55)',[tenant,evals[0].id,student]);
    await assert.rejects(client.query('insert into grades(institution_id,evaluation_id,student_id,score) values($1,$2,$3,55)',[tenant,evals[1].id,student]),{code:'42501'});
    await assert.rejects(client.query('select grade_submission($1,55)',[submission]),{code:'42501'});
  } finally {
    await db.admin.query('delete from user_roles where id=$1',[grant]);
    await db.admin.query('update users set admin_permissions=null where id=$1',[teacherUser.id]);
  }
});

test('ordinary administrators cannot mint or assign platform super-admin privileges through the Data API',async()=>{
  const client=await connection(),superRole=(await db.admin.query("select id from roles where code='super_admin' and institution_id is null order by id limit 1")).rows[0].id;
  await assert.rejects(client.query('insert into user_roles(user_id,role_id,institution_id) values($1,$2,$3)',[adminUser.id,superRole,tenant]),{code:'42501'});
  await assert.rejects(client.query("insert into roles(institution_id,name,code) values($1,'Escalation fixture','super_admin')",[tenant]),{code:'42501'});
  await assert.rejects(client.query('update users set person_id=$1 where id=$2',[parentUser.personId,adminUser.id]),{code:'42501'});
});

test('current-year aggregates remain visible when only a historical year is hidden; old and unknown-year documents stay protected',async()=>{
  const years=(await db.admin.query('select id,is_current from academic_years where institution_id=$1 order by id',[tenant])).rows;
  const current=years.find(y=>y.is_current).id,old=years.find(y=>!y.is_current).id,auth=randomUUID();
  const person=(await db.admin.query("insert into persons(institution_id,first_name,last_name) values($1,'Year','Visibility') returning id",[tenant])).rows[0].id;
  await db.admin.query('insert into auth.users(id) values($1)',[auth]);
  const user=(await db.admin.query("insert into users(institution_id,person_id,auth_user_id,full_name,email) values($1,$2,$3,'Year Visibility','year@fixture.invalid') returning id",[tenant,person,auth])).rows[0].id;
  await db.admin.query("insert into user_roles(user_id,role_id,institution_id) select $1,id,$2 from roles where institution_id=$2 and code='parent'",[user,tenant]);
  const parent=(await db.admin.query('insert into parents(institution_id,person_id) values($1,$2) returning id',[tenant,person])).rows[0].id;
  await db.admin.query('insert into parent_students(parent_id,student_id) values($1,$2)',[parent,student]);
  const period=(await db.admin.query("insert into academic_periods(institution_id,academic_year_id,name) values($1,$2,'Hidden historical year') returning id",[tenant,old])).rows[0].id;
  await db.admin.query("insert into grade_visibility_rules(institution_id,scope,user_id,academic_period_id,allowed) values($1,'user',$2,$3,false)",[tenant,user,period]);
  const reports=(await db.admin.query("insert into report_cards(institution_id,student_id,academic_year_id,status) values($1,$2,$3,'generated'),($1,$2,$4,'generated'),($1,$2,null,'generated') returning id",[tenant,student,current,old])).rows;
  const client=await db.connect();await asUser(client,auth,tenant);
  const visibility=(await client.query('select portal_can_view_year_grades($1,$2) current,portal_can_view_year_grades($1,$3) old,portal_can_view_grades($1,null) legacy',[student,current,old])).rows[0];
  assert.deepEqual(visibility,{current:true,old:false,legacy:false});
  assert.ok(Number.isFinite(Number((await client.query('select dashboard_student_average($1) value',[student])).rows[0].value)));
  assert.ok((await client.query('select student_report_context($1) value',[student])).rows[0].value);
  assert.equal((await client.query('select id from report_cards where id=$1',[reports[0].id])).rows.length,1);
  for(const report of reports.slice(1))assert.equal((await client.query('select id from report_cards where id=$1',[report.id])).rows.length,0);
  for(const [index,report] of reports.entries()){
    const url=`fixture://year-report/${report.id}`;
    await db.admin.query('update report_cards set pdf_url=$1 where id=$2',[url,report.id]);
    const file=(await db.admin.query("insert into files(institution_id,original_name,url,storage_path) values($1,'Year fixture.pdf',$2,$3) returning id",[tenant,url,`fixture/year/${report.id}.pdf`])).rows[0].id;
    assert.equal((await client.query('select portal_file_read($1) value',[file])).rows[0].value,index===0);
  }
  const access=(await client.query('select portal_access_me() value')).rows[0].value;
  assert.equal(access.students[0].annualVisible,true);assert.equal(String(access.students[0].academicYearId),current);
});

test('payment deletion refreshes balances and institution cascades handle already deleted charges',async()=>{
 const client=await connection(),id=await charge();await pay(client,id,20);
 await db.admin.query('delete from payments where charge_id=$1',[id]);
 assert.equal((await db.admin.query('select status from charges where id=$1',[id])).rows[0].status,'pending');
 await pay(client,id,20);
 await assert.rejects(db.admin.query('delete from charges where id=$1',[id]),{code:'22023'});
 await db.admin.query('delete from institutions where id=$1',[tenant]);
 assert.equal((await db.admin.query('select count(*) from payments where charge_id=$1',[id])).rows[0].count,'0');
});
