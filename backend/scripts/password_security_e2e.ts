// Real Auth/HTTP checks on a temporary account. Recovery email is intercepted.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {createApp}=require('../src/app.ts') as typeof import('../src/app');
const {AuthFlowService}=require('../src/modules/auth/auth-flow.service.ts') as typeof import('../src/modules/auth/auth-flow.service');
const {requireSupabaseServiceRole}=require('../src/lib/supabase.ts') as typeof import('../src/lib/supabase');
const {env}=require('../src/lib/env.ts') as typeof import('../src/lib/env');
const {createClient}=require('@supabase/supabase-js') as typeof import('@supabase/supabase-js');
async function main(){
 const db=requireSupabaseServiceRole();
 const email=`password.${crypto.randomUUID()}@example.com`;
 const initial=`Initial-${crypto.randomBytes(10).toString('hex')}!`;
 const changed=`Changed-${crypto.randomBytes(10).toString('hex')}!`;
 const reset=`Reset-${crypto.randomBytes(10).toString('hex')}!`;
 let authId:string|undefined;let link='';
 const server=createApp().listen(0,'127.0.0.1');
 await new Promise<void>(r=>server.once('listening',r));
 const api=`http://127.0.0.1:${(server.address() as {port:number}).port}/api/auth`;
 const client=()=>createClient(env.supabaseUrl,env.supabaseAnonKey,{auth:{persistSession:false,autoRefreshToken:false}});
 async function call(path:string,body:unknown,token?:string){
  const r=await fetch(api+path,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:JSON.stringify(body)});
  return {status:r.status,json:await r.json() as any};
 }
 try{
  const inst=await db.from('institutions').select('id').eq('active',true).is('deleted_at',null).limit(1).single();assert.ifError(inst.error);
  const role=await db.from('roles').select('id').eq('code','admin').is('institution_id',null).single();assert.ifError(role.error);
  const created=await db.auth.admin.createUser({email,password:initial,email_confirm:true,app_metadata:{institution_id:inst.data.id,roles:['admin']}});assert.ifError(created.error);authId=created.data.user.id;
  const user=await db.from('users').insert({auth_user_id:authId,institution_id:inst.data.id,email,full_name:'Temporary password check'}).select('id').single();assert.ifError(user.error);
  assert.ifError((await db.from('user_roles').insert({user_id:user.data.id,role_id:role.data.id,institution_id:inst.data.id})).error);
  const login=await client().auth.signInWithPassword({email,password:initial});assert.ifError(login.error);
  const token=login.data.session!.access_token;
  assert.equal((await call('/change-password',{currentPassword:'wrong-password',newPassword:changed},token)).status,400);
  assert.equal((await call('/change-password',{currentPassword:initial,newPassword:'short'},token)).status,400);
  assert.equal((await call('/change-password',{currentPassword:initial,newPassword:initial},token)).status,400);
  const change=await call('/change-password',{currentPassword:initial,newPassword:changed},token);assert.equal(change.status,200,JSON.stringify(change.json));
  assert.ok((await client().auth.signInWithPassword({email,password:initial})).error,'Old password rejected');
  const newLogin=await client().auth.signInWithPassword({email,password:changed});assert.ifError(newLogin.error);
  // Recovery must keep second-factor settings and cannot return a login session.
  assert.ifError((await db.from('auth_two_factor_settings').upsert({user_id:user.data.id,enabled:true,method:'totp',secret:'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP'})).error);
  assert.ifError((await db.from('users').update({two_factor:true,two_factor_method:'totp'}).eq('id',user.data.id)).error);
  const service=new AuthFlowService(undefined,{async sendPasswordRecovery(_to:string,_name:string,url:string){link=url;}} as any);
  await service.recoverPassword({username:email});
  const url=new URL(link);assert.equal(url.origin,new URL(env.passwordResetRedirectUrl).origin);
  const hashRouting=url.hash.startsWith('#/');
  assert.equal(hashRouting?url.hash.split('?')[0]:url.pathname,hashRouting?'#/reset-password':'/reset-password');
  const tokenHash=hashRouting?new URLSearchParams(url.hash.split('?')[1]).get('token_hash'):url.searchParams.get('token_hash');assert.ok(tokenHash);
  assert.equal((await call('/reset-password',{tokenHash,newPassword:'short'})).status,400,'Validation must not consume token');
  const recovered=await call('/reset-password',{tokenHash,newPassword:reset});assert.equal(recovered.status,200,JSON.stringify(recovered.json));
  assert.equal(recovered.json.data.session,undefined);
  assert.equal((await call('/reset-password',{tokenHash,newPassword:changed})).status,400,'One-use link');
  assert.equal((await call('/reset-password',{tokenHash:'invalid',newPassword:changed})).status,400);
  assert.ok((await client().auth.signInWithPassword({email,password:changed})).error);
  assert.ifError((await client().auth.signInWithPassword({email,password:reset})).error);
  const settings=await db.from('auth_two_factor_settings').select('enabled,method').eq('user_id',user.data.id).single();assert.ifError(settings.error);assert.equal(settings.data.enabled,true);assert.equal(settings.data.method,'totp');
  const appLogin=await call('/login',{username:email,password:reset});assert.equal(appLogin.status,200,JSON.stringify(appLogin.json));assert.equal(appLogin.json.data.twoFactorRequired,true);assert.equal(appLogin.json.data.session,undefined);
  console.log('Password checks passed: current-password verification, real change, direct app recovery URL, one-use/invalid recovery links, validation before consumption, old password rejection, new password login and 2FA preserved. No real email sent.');
 }finally{
  try{if(authId)assert.ifError((await db.auth.admin.deleteUser(authId)).error);}finally{await new Promise<void>((resolve,reject)=>server.close(e=>e?reject(e):resolve()));}
  console.log('Temporary password account removed.');
 }
}
main().catch(e=>{console.error(e);process.exitCode=1;});
