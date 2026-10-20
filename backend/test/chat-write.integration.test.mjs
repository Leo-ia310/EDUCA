import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {before,after,afterEach,test} from 'node:test';
import {database,asUser} from './helpers/database.mjs';
let db;
const ownedInstitutions=new Set();
before(async()=>{db=await database();},{timeout:120000});
afterEach(async()=>{if(db){await db.release();await db.admin.query('delete from announcement_delivery_jobs where institution_id=any($1::bigint[])',[[...ownedInstitutions]]);await db.admin.query('delete from institutions where id=any($1::bigint[])',[[...ownedInstitutions]]);ownedInstitutions.clear();}});after(async()=>{if(db)await db.close();});
async function fixture(devices=1){
 const q=(sql,args)=>db.admin.query(sql,args),inst=(await q("insert into institutions(code,name) values($1,'Chat fixture') returning id",['CHAT-'+randomUUID()])).rows[0].id;
 ownedInstitutions.add(inst);
 const users=[];
 for(let i=0;i<3;i++){
  const auth=randomUUID();await q('insert into auth.users(id) values($1)',[auth]);
  const id=(await q("insert into users(institution_id,auth_user_id,email,full_name) values($1,$2,$3,'Chat user') returning id",[inst,auth,auth+'@fixture.invalid'])).rows[0].id;
  await q("insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code='admin' order by id limit 1",[inst,id]);users.push({id,auth});
 }
 const conv=(await q("insert into conversations(institution_id,kind,title) values($1,'group','Fixture') returning id",[inst])).rows[0].id;
 await q('insert into conversation_participants(conversation_id,user_id) values($1,$2),($1,$3)',[conv,users[0].id,users[1].id]);
 await q("insert into devices(user_id,platform,device_uuid,push_token) select $1,'web','device-'||n,'{}' from generate_series(1,$2) n",[users[1].id,devices]);
 const client=await db.connect();await asUser(client,users[0].auth,inst);
 return {inst,users,conv,client,q};
}
async function send(f,key=randomUUID(),content='Repeated text',client=f.client){return (await client.query('select chat_send_message($1,$2,$3,null) result',[f.conv,key,content])).rows[0].result;}
async function service(){const client=await db.connect();await client.query('set role service_role');return client;}
async function claim(client){return (await client.query('select notification_push_claim() result')).rows[0].result;}
async function finish(client,job,outcome='sent',retry=0){return (await client.query('select notification_push_finish($1,$2,$3,$4) result',[job.id,job.token,outcome,retry])).rows[0].result;}

test('concurrent UUID retries create one message, one inbox notification and all 1105 device jobs',async()=>{
 const f=await fixture(1105),key=randomUUID(),second=await db.connect();await asUser(second,f.users[0].auth,f.inst);
 const [a,b]=await Promise.all([send(f,key),send(f,key,'Repeated text',second)]);assert.deepEqual(a,b);
 assert.equal(a.uuid,key);assert.equal(a.senderId,f.users[0].id);
 assert.equal((await f.q('select count(*) from notification_push_outbox where institution_id=$1',[f.inst])).rows[0].count,'1105');
 assert.equal((await f.q('select count(*) from notifications where institution_id=$1',[f.inst])).rows[0].count,'1');
 await assert.rejects(send(f,key,'Changed'),{code:'23505'});
 const different=await send(f);assert.notEqual(different.id,a.id);
 await assert.rejects(f.client.query("insert into messages(conversation_id,sender_id,content) values($1,$2,'Bypass')",[f.conv,f.users[0].id]),{code:'42501'});
 await assert.rejects(f.client.query('select notification_push_claim()'),{code:'42501'});
 await assert.rejects(f.client.query('select * from notification_push_outbox'),{code:'42501'});
});
test('notification failure rolls back the message and membership is rechecked for every replay',async()=>{
 const f=await fixture(),key=randomUUID();
 await f.q("create function fixture_chat_failure() returns trigger language plpgsql as $$ begin raise exception 'fixture' using errcode='22023'; end $$");
 await f.q('create trigger fixture_chat_fail before insert on notification_push_outbox for each row execute function fixture_chat_failure()');
 try {await assert.rejects(send(f,key),{code:'22023'});}finally{await f.q('drop trigger fixture_chat_fail on notification_push_outbox;drop function fixture_chat_failure()');}
 assert.equal((await f.q('select count(*) from messages where uuid=$1',[key])).rows[0].count,'0');
 await send(f,key);await f.q('delete from conversation_participants where conversation_id=$1 and user_id=$2',[f.conv,f.users[0].id]);
 await assert.rejects(send(f,key),{code:'42501'});
 await asUser(f.client,f.users[2].auth,f.inst);await assert.rejects(send(f),{code:'42501'});
});
test('shared admission allows four tenants, one job per tenant, and stale leases cannot acknowledge new attempts',async()=>{
 const fixtures=[];for(let i=0;i<5;i++){const f=await fixture(2);await send(f);fixtures.push(f);}
 const a=await service(),b=await service();
 const jobs=await Promise.all([claim(a),claim(b)]);jobs.push(await claim(a),await claim(b));
 assert.equal(jobs.filter(Boolean).length,4);assert.equal(await claim(a),null);
 const tenants=(await db.admin.query('select distinct institution_id from notification_push_outbox where id=any($1::bigint[])',[jobs.map(j=>j.id)])).rows;assert.equal(tenants.length,4);
 const old=jobs[0];assert.equal(await finish(a,{...old,token:randomUUID()}),false);
 await db.admin.query("update notification_push_outbox set lease_until=now()-interval '1 second' where id=$1",[old.id]);
 // Release the other admissions and prevent unrelated pending jobs competing.
 await db.admin.query("update notification_push_outbox set status='skipped' where id<>$1 and status in ('pending','sending')",[old.id]);
 const retry=await claim(b);assert.equal(retry.id,old.id);assert.notEqual(retry.token,old.token);
 assert.equal(await finish(a,old),false);assert.equal(await finish(b,retry),true);assert.equal(await finish(b,retry),false);
 assert.equal((await db.admin.query("select count(*) from notification_deliveries where notification_id=$1 and destination=$2 and status='sent'",[retry.notificationId,retry.deviceId])).rows[0].count,'1');
});
test('push retries are bounded, revoked recipients are skipped, and an expired subscription cannot deactivate its replacement',async()=>{
 const f=await fixture(2);await send(f);const client=await service(),first=await claim(client);
 assert.equal(await finish(client,first,'retry',10),true);assert.equal((await f.q('select status from notification_push_outbox where id=$1',[first.id])).rows[0].status,'pending');
 await f.q("update devices set push_token='new subscription' where id=$1",[first.deviceId]);
 const next=await claim(client);assert.notEqual(next.id,first.id);assert.equal(await finish(client,next,'gone'),true);
 await f.q('update notification_push_outbox set available_at=now() where id=$1',[first.id]);
 const retried=await claim(client);await f.q("update devices set push_token='replacement' where id=$1",[retried.deviceId]);
 assert.equal(await finish(client,retried,'gone'),true);assert.equal((await f.q('select active from devices where id=$1',[retried.deviceId])).rows[0].active,true);
 await send(f);await f.q('delete from conversation_participants where conversation_id=$1 and user_id=$2',[f.conv,f.users[1].id]);
 assert.equal(await claim(client),null);assert.equal((await f.q("select count(*) from notification_push_outbox where institution_id=$1 and status in ('pending','sending')",[f.inst])).rows[0].count,'0');
});

test('third push failure is terminal and undelivered notifications expire after 24 hours',async()=>{
 const f=await fixture(),client=await service();await send(f);
 for(let attempt=1;attempt<=3;attempt++){
  const job=await claim(client);assert.ok(job);assert.equal(await finish(client,job,'retry'),true);
  const state=(await f.q('select status,attempts from notification_push_outbox where id=$1',[job.id])).rows[0];
  assert.equal(state.attempts,attempt);assert.equal(state.status,attempt===3?'failed':'pending');
  await f.q('update notification_push_outbox set available_at=now() where id=$1',[job.id]);
 }
 assert.equal(await claim(client),null);
 await send(f);await f.q("update notification_push_outbox set created_at=now()-interval '25 hours' where institution_id=$1 and status='pending'",[f.inst]);
 assert.equal(await claim(client),null);assert.equal((await f.q("select count(*) from notification_push_outbox where institution_id=$1 and status='skipped'",[f.inst])).rows[0].count,'1');
});

test('announcement push snapshots all devices once, preserves device checkpoints and rechecks audience',async()=>{
 const f=await fixture(1105),client=await service();
 const a=(await f.q("insert into announcements(institution_id,title,content,audience,published,created_by) values($1,'Push fixture','Body','all',true,$2) returning id",[f.inst,f.users[0].id])).rows[0].id;
 const n=(await f.q("insert into notifications(institution_id,user_id,title,message,data) values($1,$2,'Fixture','Body',$3::jsonb) returning id",[f.inst,f.users[1].id,JSON.stringify({module:'announcements',announcementId:a,deepLink:'/announcements'})])).rows[0].id;
 const enqueue=()=>client.query('select notification_push_enqueue($1) result',[n]).then(r=>r.rows[0].result.status);
 assert.equal(await enqueue(),'pending');assert.equal((await f.q('select count(*) from notification_push_outbox where notification_id=$1',[n])).rows[0].count,'1105');
 await f.q("insert into devices(user_id,platform,push_token) values($1,'web','{}')",[f.users[1].id]);assert.equal(await enqueue(),'pending');
 assert.equal((await f.q('select count(*) from notification_push_outbox where notification_id=$1',[n])).rows[0].count,'1105');
 const first=await claim(client);assert.equal(first.tag,'notification-'+n);assert.equal(await finish(client,first),true);
 // Changing the audience to teachers excludes this administrative recipient.
 await f.q("update announcements set audience='teachers' where id=$1",[a]);
 await f.q("update notification_push_outbox set status='skipped' where notification_id=$1 and id<>$2",[n,first.id]);
 assert.equal(await enqueue(),'sent');
 const newDevice=(await f.q("insert into devices(user_id,platform,push_token) values($1,'web','{}') returning id",[f.users[1].id])).rows[0].id;
 await f.q('insert into notification_push_outbox(institution_id,notification_id,device_id) values($1,$2,$3)',[f.inst,n,newDevice]);
 assert.equal(await claim(client),null);
});
test('device deletion and delivery checkpoint use compatible parent-first lock ordering',async()=>{
 const f=await fixture(),client=await service();await send(f);const job=await claim(client);
 const results=await Promise.allSettled([finish(client,job),f.q('delete from devices where id=$1',[job.deviceId])]);
 assert.equal(results.filter(r=>r.status==='rejected').length,0);assert.equal((await f.q('select count(*) from devices where id=$1',[job.deviceId])).rows[0].count,'0');
});

test('explicit announcement retry resets failed device jobs atomically and keeps confirmed devices',async()=>{
 const f=await fixture(2),client=await service();
 const a=(await f.q("insert into announcements(institution_id,title,content,audience,published,created_by) values($1,'Retry push','Body','all',true,$2) returning id",[f.inst,f.users[0].id])).rows[0].id;
 const jid=(await f.q("insert into announcement_delivery_jobs(announcement_id,institution_id,created_by,payload) values($1,$2,$3,'{\"title\":\"Retry push\",\"description\":\"Body\",\"audience\":\"all\"}') returning id",[a,f.inst,f.users[0].id])).rows[0].id;
 const j=(await client.query('select claim_announcement_delivery() result')).rows[0].result;assert.equal(String(j.id),jid);
 await client.query('select prepare_announcement_delivery($1,$2)',[jid,j.lock_token]);
 const rows=(await f.q('select user_id,notification_id from announcement_delivery_recipients where job_id=$1',[jid])).rows;
 const recipient=rows.find(row=>row.user_id===f.users[1].id);
 await client.query('select notification_push_enqueue($1)',[recipient.notification_id]);
 const first=await claim(client);await finish(client,first,'sent');const second=await claim(client);await finish(client,second,'failed');
 for(const row of rows)await client.query('select record_announcement_delivery($1,$2,$3,$4,$5,null,null)',[jid,j.lock_token,row.user_id,'skipped',row===recipient?'failed':'skipped']);
 await client.query('select finish_announcement_delivery($1,$2,null)',[jid,j.lock_token]);
 const retried=(await client.query('select retry_announcement_delivery($1) result',[jid])).rows[0].result;assert.equal(retried.status,'queued');
 const states=(await f.q('select status,attempts from notification_push_outbox where notification_id=$1 order by id',[recipient.notification_id])).rows;
 assert.equal(states[0].status,'sent');assert.equal(states[1].status,'pending');assert.equal(states[1].attempts,0);
 await assert.rejects(client.query('select announcement_retry_before_push_queue($1)',[jid]),{code:'42501'});
});

test('concurrent browser registration creates one active device and cannot write another account',async()=>{
 const f=await fixture(0),other=await db.connect();await asUser(other,f.users[0].auth,f.inst);
 const subscription={endpoint:'https://fcm.googleapis.com/wp/fixture',keys:{p256dh:'fixture',auth:'fixture'}};
 const save=client=>client.query('select notification_device_save($1::jsonb) result',[JSON.stringify(subscription)]).then(r=>r.rows[0].result);
 const [a,b]=await Promise.all([save(f.client),save(other)]);assert.deepEqual(a,b);
 assert.equal((await f.q("select count(*) from devices where user_id=$1 and active",[f.users[0].id])).rows[0].count,'1');
 await assert.rejects(f.client.query("update devices set user_id=$1 where id=$2",[f.users[1].id,a.id]),{code:'42501'});
 await assert.rejects(f.client.query("insert into devices(user_id,platform) values($1,'web')",[f.users[1].id]),{code:'42501'});
 await f.q("insert into devices(user_id,device_uuid,platform,push_token,active) select user_id,device_uuid,platform,push_token,active from devices where id=$1",[a.id]);
 await save(f.client);assert.equal((await f.q('select count(*) from devices where user_id=$1 and active',[f.users[0].id])).rows[0].count,'1');
});
