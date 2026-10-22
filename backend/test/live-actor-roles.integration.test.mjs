import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import {database} from './helpers/database.mjs';

test('batched live actor roles preserve legacy authorization across tenants, revocations and optional MFA', {timeout:120000}, async()=>{
 const db=await database({through:'0055_atomic_assignment_write.sql'}),q=(s,p)=>db.admin.query(s,p);
 try {
  const inst=(await q("insert into institutions(code,name) values($1,'Role fixture') returning id",[randomUUID()])).rows[0].id;
  const other=(await q("insert into institutions(code,name) values($1,'Other fixture') returning id",[randomUUID()])).rows[0].id;
  const actors=[];
  for(const code of ['teacher','admin','student','parent']) {
   const auth=randomUUID(),session=randomUUID();
   await q('insert into auth.users(id) values($1)',[auth]);
   await q('insert into auth.sessions(id,user_id) values($1,$2)',[session,auth]);
   const id=(await q('insert into users(institution_id,auth_user_id,email,full_name) values($1,$2,$3,$4) returning id',[inst,auth,auth+'@fixture.invalid',code])).rows[0].id;
   await q('insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code=$3',[inst,id,code]);
   actors.push({id,auth,session,code});
  }
  const t=actors[0];
  const cases=[
   ['normal',async()=>{}],
   ['inactive-user',()=>q('update users set active=false where id=$1',[t.id])],
   ['archived-user',()=>q('update users set deleted_at=now() where id=$1',[t.id])],
   ['inactive-institution',()=>q('update institutions set active=false where id=$1',[inst])],
   ['archived-institution',()=>q('update institutions set deleted_at=now() where id=$1',[inst])],
   ['revoked-role',()=>q('delete from user_roles where user_id=$1',[t.id])],
   ['inactive-role',()=>q("update roles set active=false where institution_id is null and code='teacher'")],
   ['foreign-grant',()=>q('update user_roles set institution_id=$2 where user_id=$1',[t.id,other])],
   ['foreign-role',async()=>{const r=(await q("insert into roles(institution_id,name,code) values($1,'Foreign teacher','teacher') returning id",[other])).rows[0].id;await q('update user_roles set role_id=$2 where user_id=$1',[t.id,r]);}],
   ['mixed-admin',()=>q("insert into user_roles(institution_id,user_id,role_id) select $1,$2,id from roles where institution_id is null and code='admin'",[inst,t.id])],
   ['global-grant',()=>q('update user_roles set institution_id=null where user_id=$1',[t.id])],
   ['disabled-MFA',()=>q('insert into auth_two_factor_settings(user_id,enabled) values($1,false)',[t.id])],
   ['unverified-MFA',()=>q('insert into auth_two_factor_settings(user_id,enabled) values($1,true)',[t.id])],
   ['verified-MFA',async()=>{await q('insert into auth_two_factor_settings(user_id,enabled) values($1,true)',[t.id]);await q('insert into auth_two_factor_verified_sessions(session_id,user_id) values($1,$2)',[t.session,t.id]);}],
  ];
  async function matrix() {
   const rows=[];
   for(const [name,mutate] of cases) {
    await q('begin');
    try {
     await mutate();
     for(const a of actors) for(const scope of [inst,other]) {
      await q("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:a.auth,session_id:a.session,institution_id:scope,role:'authenticated'})]);
      await q('set local role authenticated');
      const row=(await q('select current_roles() roles,class_admin_actor() admin,is_teacher_actor() teacher,portal_staff($1) staff,admin_can($2) reports',[a.id,'reports.view'])).rows[0];
      rows.push({name,actor:a.code,scope,...row});
      await q('reset role');
     }
    } finally {await q('rollback');}
   }
   return rows;
  }
  const before=await matrix();
  await q(await readFile(new URL('../../supabase/migrations/0056_live_actor_role_queries.sql',import.meta.url),'utf8'));
  const after=await matrix();
  assert.deepEqual(after,before);
  assert.equal(after.find(x=>x.name==='normal'&&x.actor==='teacher'&&x.scope===inst).teacher,true);
  assert.deepEqual(after.find(x=>x.name==='unverified-MFA'&&x.actor==='teacher'&&x.scope===inst).roles,[]);
  assert.equal(after.find(x=>x.name==='verified-MFA'&&x.actor==='teacher'&&x.scope===inst).teacher,true);
  assert.equal(after.find(x=>x.name==='mixed-admin'&&x.actor==='teacher'&&x.scope===inst).teacher,false);
 } finally {await db.close();}
});
