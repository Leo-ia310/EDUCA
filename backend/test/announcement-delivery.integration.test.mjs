import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { after,afterEach,before,test } from 'node:test';
import { asUser,database } from './helpers/database.mjs';

let db,legacy;const jobs=new Set();
async function school(count=2){
  const code=randomUUID().slice(0,8),tenant=(await db.admin.query('insert into institutions(code,name) values($1,$2) returning id',[`ANN-${code}`,'Announcement fixture'])).rows[0].id;
  const auth=randomUUID();await db.admin.query('insert into auth.users(id) values($1)',[auth]);
  const author=(await db.admin.query("insert into users(institution_id,auth_user_id,email,full_name) values($1,$2,$3,'Fixture author') returning id",[tenant,auth,`author-${code}@fixture.invalid`])).rows[0].id;
  await db.admin.query("insert into user_roles(user_id,role_id,institution_id) select $1,id,$2 from roles where institution_id is null and code='teacher' order by id limit 1",[author,tenant]);
  const recipients=(await db.admin.query("insert into users(institution_id,email,full_name,email_notifications_enabled) select $1,$2||i||'@fixture.invalid','Recipient '||i,true from generate_series(1,$3::integer) i returning id",[tenant,`recipient-${code}-`,count])).rows.map(r=>r.id);
  await db.admin.query("insert into user_roles(user_id,role_id,institution_id) select u.id,r.id,$1 from unnest($2::bigint[]) u(id) cross join lateral(select id from roles where institution_id is null and code='student' order by id limit 1) r",[tenant,recipients]);
  return {tenant,author,auth,recipients};
}
async function job(fixture){
  const announcement=(await db.admin.query("insert into announcements(institution_id,title,content,created_by,published) values($1,'Fixture announcement','Fixture content',$2,true) returning id",[fixture.tenant,fixture.author])).rows[0].id;
  const id=(await db.admin.query("insert into announcement_delivery_jobs(announcement_id,institution_id,created_by,payload) values($1,$2,$3,$4::jsonb) returning id",[announcement,fixture.tenant,fixture.author,JSON.stringify({title:'Fixture announcement',description:'Fixture content',audience:'students'})])).rows[0].id;
  jobs.add(id);return id;
}
async function rpc(name,args=[]){return (await db.admin.query(`select ${name}(${args.map((_,i)=>`$${i+1}`).join(',')}) value`,args)).rows[0].value;}
const claim=()=>rpc('claim_announcement_delivery');
const prepare=j=>rpc('prepare_announcement_delivery',[j.id,j.lock_token]);
const record=(j,user,email='sent',push='sent')=>rpc('record_announcement_delivery',[j.id,j.lock_token,user,email,push,`fixture-${user}`,null]);
const state=id=>db.admin.query('select * from announcement_delivery_jobs where id=$1',[id]).then(r=>r.rows[0]);
before(async()=>{
  db=await database({through:'0044_year_grade_visibility.sql'});
  const fixture=await school(),id=await job(fixture),claimed=await claim();
  await prepare(claimed);await record(claimed,fixture.recipients[0]);
  await db.admin.query("update announcement_delivery_jobs set created_at=now()-interval '2 days',updated_at=now(),status='failed',phase='failed',lock_token=null,lease_until=null where id=$1",[id]);
  legacy={fixture,id};
  await db.admin.query(await readFile(new URL('../../supabase/migrations/0045_announcement_delivery_scaling.sql',import.meta.url),'utf8'));
  await db.admin.query(await readFile(new URL('../../supabase/migrations/0046_announcement_feed.sql',import.meta.url),'utf8'));
},{timeout:120000});
afterEach(async()=>{if(db){await db.admin.query('delete from announcement_delivery_jobs where id=any($1::bigint[])',[[...jobs]]);jobs.clear();await db.release();}});
after(async()=>{if(db)await db.close();});

test('upgrading an old partial job preserves checkpoints and fences stale provider keys',async()=>{
  const {fixture,id}=legacy,initial=await state(id);
  assert.equal(initial.emailed,1);assert.equal(initial.processed,1);assert.ok(initial.prepared_at);
  await rpc('retry_announcement_delivery',[id]);const j=await claim();await prepare(j);
  const attempt=await rpc('begin_announcement_email',[j.id,j.lock_token,fixture.recipients[1]]);
  assert.deepEqual(attempt,{send:false,status:'needs_review'});
  await record(j,fixture.recipients[1],'needs_review','skipped');
  const done=await rpc('finish_announcement_delivery',[j.id,j.lock_token,null]);
  assert.equal(done.status,'completed_with_errors');assert.equal(done.email_review,1);assert.equal(done.emailed,1);assert.equal(done.processed,2);
  const unchanged=await rpc('retry_announcement_delivery',[id]);assert.equal(unchanged.status,'completed_with_errors');
  assert.equal(await claim(),null);
  assert.equal((await state(id)).email_review,1);
  const resolved=await rpc('resolve_announcement_email_review',[id,fixture.recipients[1],'confirmed_not_sent','Fixture provider records confirm no delivery',null]);
  assert.equal(resolved.email_review,0);assert.equal(resolved.email_failed,0);assert.equal(resolved.processed,1);
  const retried=await claim(),authorized=await rpc('begin_announcement_email',[retried.id,retried.lock_token,fixture.recipients[1]]);
  assert.equal(authorized.send,true);assert.ok(authorized.idempotencyKey.includes('/review/'));
  assert.equal((await rpc('begin_announcement_email',[retried.id,retried.lock_token,fixture.recipients[1]])).idempotencyKey,authorized.idempotencyKey);
});

test('claim admission is global, one job per tenant, and successful slices yield fairly',async()=>{
  const schools=await Promise.all(Array.from({length:5},()=>school(1)));
  const first=await job(schools[0]),second=await job(schools[0]);
  for(const fixture of schools.slice(1))await job(fixture);
  const clients=await Promise.all(Array.from({length:4},()=>db.connect()));
  const claimed=await Promise.all(clients.map(client=>client.query('select claim_announcement_delivery() value').then(r=>r.rows[0].value)));
  assert.ok(claimed.every(Boolean));assert.equal(new Set(claimed.map(j=>j.institution_id)).size,4);
  assert.equal(await claim(),null);
  const owner=claimed.find(j=>String(j.id)===first);assert.ok(owner);
  await rpc('pause_announcement_delivery',[owner.id,owner.lock_token,false,0]);
  const next=await claim();assert.equal(String(next.id),second);assert.notEqual(next.lock_token,owner.lock_token);
});

test('recipient checkpoints maintain exact counters across replay, retry and account erasure',async()=>{
  const fixture=await school(3),id=await job(fixture),j=await claim();await prepare(j);
  await record(j,fixture.recipients[0]);await record(j,fixture.recipients[0]);
  await record(j,fixture.recipients[1],'failed','failed');await record(j,fixture.recipients[2],'skipped','skipped');
  let row=await state(id);assert.equal(row.total,3);assert.equal(row.processed,3);assert.equal(row.emailed,1);assert.equal(row.email_failed,1);assert.equal(row.email_skipped,1);assert.equal(row.push_failed,1);
  const deliveries=(await db.admin.query('select count(*) from notification_deliveries d join announcement_delivery_recipients r on r.notification_id=d.notification_id where r.job_id=$1',[id])).rows[0].count;
  assert.equal(deliveries,'2');
  await rpc('finish_announcement_delivery',[j.id,j.lock_token,null]);await rpc('retry_announcement_delivery',[id]);
  const retry=await claim();await prepare(retry);row=await state(id);assert.equal(row.processed,2);assert.equal(row.email_failed,0);assert.equal(row.email_skipped,1);
  await record(retry,fixture.recipients[1]);await rpc('finish_announcement_delivery',[retry.id,retry.lock_token,null]);
  await db.admin.query('delete from users where id=$1',[fixture.recipients[0]]);
  row=await state(id);assert.equal(row.total,2);assert.equal(row.processed,2);assert.equal(row.emailed,1);assert.equal(row.notified,2);assert.equal(row.email_skipped,1);
});

test('delivery rechecks consent and roles and rejects stale leases and browser JWTs',async()=>{
  const fixture=await school(),id=await job(fixture),j=await claim();await prepare(j);
  await db.admin.query('update users set email_notifications_enabled=false where id=$1',[fixture.recipients[0]]);
  assert.deepEqual(await rpc('begin_announcement_email',[j.id,j.lock_token,fixture.recipients[0]]),{send:false,status:'skipped'});
  await db.admin.query('delete from user_roles where user_id=$1',[fixture.recipients[1]]);
  const page=await rpc('announcement_pending_page',[j.id,j.lock_token]);assert.equal(page.find(r=>String(r.user_id)===fixture.recipients[1]).eligible,false);
  const browser=await db.connect();await asUser(browser,fixture.auth,fixture.tenant);
  await assert.rejects(browser.query('select claim_announcement_delivery()'),{code:'42501'});
  await assert.rejects(browser.query('select reserve_provider_request(\'resend\')'),{code:'42501'});
  await assert.rejects(browser.query("select resolve_announcement_email_review($1,$2,'confirmed_not_sent','Fixture proof')",[id,fixture.recipients[0]]),{code:'42501'});
  await db.admin.query("update announcement_delivery_jobs set lease_until=now()-interval '1 second' where id=$1",[id]);
  const replacement=await claim();assert.notEqual(replacement.lock_token,j.lock_token);
  await assert.rejects(record(j,fixture.recipients[1]),/delivery_lease_lost/);
});

test('operator-confirmed delivery reconciles review counters and records provider evidence once',async()=>{
  const fixture=await school(1),id=await job(fixture),j=await claim();await prepare(j);
  await record(j,fixture.recipients[0],'needs_review','skipped');await rpc('finish_announcement_delivery',[j.id,j.lock_token,null]);
  await assert.rejects(rpc('resolve_announcement_email_review',[id,fixture.recipients[0],'confirmed_sent','',null]),{code:'22023'});
  const fixed=await rpc('resolve_announcement_email_review',[id,fixture.recipients[0],'confirmed_sent','Fixture provider log reference','confirmed-provider-id']);
  assert.equal(fixed.email_review,0);assert.equal(fixed.email_failed,0);assert.equal(fixed.emailed,1);assert.equal(fixed.processed,1);
  const next=await claim();assert.deepEqual(await rpc('announcement_pending_page',[next.id,next.lock_token]),[]);
  assert.equal((await db.admin.query("select count(*) from audit_log where action='RECONCILE_EMAIL' and record_id=$1",[id])).rows[0].count,'1');
});

test('provider request reservations share slots across connections and bound the waiting queue',async()=>{
  await db.admin.query('delete from provider_request_budgets');
  const clients=await Promise.all(Array.from({length:6},()=>db.connect()));
  const slots=await Promise.all(clients.map(client=>client.query("select reserve_provider_request('resend',600,5000) value").then(r=>r.rows[0].value)));
  assert.ok(slots.every(s=>s.allowed));const times=slots.map(s=>Date.parse(s.slotAt)).sort((a,b)=>a-b);
  for(let i=1;i<times.length;i++)assert.ok(times[i]-times[i-1]>=599);
  const before=(await db.admin.query('select next_available_at from provider_request_budgets')).rows[0].next_available_at;
  assert.equal((await rpc('reserve_provider_request',['resend',600,0])).allowed,false);
  assert.deepEqual((await db.admin.query('select next_available_at from provider_request_budgets')).rows[0].next_available_at,before);
  await rpc('defer_provider_requests',['resend',30000]);assert.equal((await rpc('reserve_provider_request',['resend',600,5000])).allowed,false);
  await assert.rejects(rpc('reserve_provider_request',['resend',99,5000]),{code:'22023'});
});

test('more than 1000 recipients retain complete counters without per-recipient recounts',async()=>{
  const fixture=await school(1105),id=await job(fixture),j=await claim();await prepare(j);
  await db.admin.query("select record_announcement_delivery($1,$2,u,'sent','skipped','fixture-'||u,null) from unnest($3::bigint[]) u",[id,j.lock_token,fixture.recipients]);
  const row=await state(id);assert.equal(row.total,1105);assert.equal(row.emailed,1105);assert.equal(row.processed,1105);assert.equal(row.notified,1105);
  assert.deepEqual(await rpc('announcement_pending_page',[j.id,j.lock_token]),[]);
});

test('announcement pages filter audience before limiting beyond 1000 rows and scope direct calendar reads',async()=>{
  const fixture=await school(1),auth=randomUUID();await db.admin.query('insert into auth.users(id) values($1)',[auth]);
  await db.admin.query('update users set auth_user_id=$1 where id=$2',[auth,fixture.recipients[0]]);
  await db.admin.query("insert into announcements(institution_id,title,content,created_by,published,audience) select $1,'Teacher secret '||i,'Private fixture',$2,true,'teachers' from generate_series(1,1105) i",[fixture.tenant,fixture.author]);
  const ids=(await db.admin.query("insert into announcements(institution_id,title,content,created_by,published,audience) values($1,'Student one','Visible',$2,true,'students'),($1,'Student two','Visible',$2,true,'students'),($1,'All','Visible',$2,true,'all') returning id",[fixture.tenant,fixture.author])).rows.map(r=>r.id);
  const client=await db.connect();await asUser(client,auth,fixture.tenant);
  const seen=[];let cursor=null;
  do {const result=(await client.query('select announcement_feed($1,1) value',[cursor])).rows[0].value;seen.push(...result.announcements.map(r=>r.id));cursor=result.nextBeforeId;if(!result.hasMore)break;}while(true);
  assert.deepEqual(seen,[...ids].reverse());
  assert.equal((await client.query("select id from announcements where audience='teachers'")).rows.length,0);
  const event=(await db.admin.query("insert into calendar_events(institution_id,title,description,type,audience,created_by,start_at) values($1,'Private calendar','Private','announcement','teachers',$2,now()) returning id",[fixture.tenant,fixture.author])).rows[0].id;
  await db.admin.query("insert into announcements(institution_id,event_id,title,content,audience,created_by,published) values($1,$2,'Private calendar','Private','teachers',$3,true)",[fixture.tenant,event,fixture.author]);
  assert.equal((await client.query('select id from calendar_events where id=$1',[event])).rows.length,0);
  await assert.rejects(client.query("insert into announcements(institution_id,title,published,created_by) values($1,'Forbidden',true,$2)",[fixture.tenant,fixture.recipients[0]]),{code:'42501'});
  const author=await db.connect();await asUser(author,fixture.auth,fixture.tenant);
  const published=(await author.query("select publish_school_announcement($1,$2,'Atomic publication','Fixture',now(),'students',$3) value",[fixture.tenant,fixture.author,randomUUID()])).rows[0].value;
  jobs.add(String(published.delivery.id));
  const latest=(await author.query('select announcement_feed(null,1) value')).rows[0].value;
  assert.equal(latest.announcements[0].id,String(published.announcement.id));
  assert.equal((await client.query('select announcement_delivery_state($1) value',[[published.announcement.id]])).rows[0].value.deliveries.length,0);
  assert.equal((await author.query('select announcement_delivery_state($1) value',[[published.announcement.id]])).rows[0].value.deliveries.length,1);
});

test('group publications require actual family enrollment, independent of audience-only matching',async()=>{
  const fixture=await school(1),auth=randomUUID();await db.admin.query('insert into auth.users(id) values($1)',[auth]);
  const person=(await db.admin.query("insert into persons(institution_id,first_name,last_name) values($1,'Group','Student') returning id",[fixture.tenant])).rows[0].id;
  await db.admin.query('update users set auth_user_id=$1,person_id=$2 where id=$3',[auth,person,fixture.recipients[0]]);
  const student=(await db.admin.query('insert into students(institution_id,person_id) values($1,$2) returning id',[fixture.tenant,person])).rows[0].id;
  const year=(await db.admin.query("insert into academic_years(institution_id,name,year,is_current) values($1,'Fixture',2026,true) returning id",[fixture.tenant])).rows[0].id;
  const groups=(await db.admin.query("insert into groups(institution_id,academic_year_id,name) values($1,$2,'Own'),($1,$2,'Other') returning id",[fixture.tenant,year])).rows.map(r=>r.id);
  await db.admin.query("insert into enrollments(institution_id,academic_year_id,group_id,student_id,enrollment_status_id) select $1,$2,$3,$4,id from catalog_enrollment_statuses where code='ACT'",[fixture.tenant,year,groups[0],student]);
  const anns=(await db.admin.query("insert into announcements(institution_id,title,content,audience,group_id,created_by,published) values($1,'Own group','Visible','groups',$2,$4,true),($1,'Other group','Private','groups',$3,$4,true) returning id",[fixture.tenant,...groups,fixture.author])).rows.map(r=>r.id);
  const client=await db.connect();await asUser(client,auth,fixture.tenant);
  assert.deepEqual((await client.query('select announcement_feed() value')).rows[0].value.announcements.map(r=>r.id),[anns[0]]);
});

test('recipient pages prioritize remaining emails over users waiting only for push devices',async()=>{
 const f=await school(25);await job(f);const j=await claim();await prepare(j);
 for(const user of f.recipients.slice(0,20))await record(j,user,'sent','pending');
 const page=await rpc('announcement_pending_page',[j.id,j.lock_token,5]);
 assert.deepEqual(page.map(r=>String(r.user_id)).sort(),f.recipients.slice(20).map(String).sort());
});
