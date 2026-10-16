// Integration checks exercise the real database functions inside a rollback.
// The email transport is injected: this never sends a real email or push.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import pg from 'pg';
import {AuthFlowService} from '../src/modules/auth/auth-flow.service';
import {AuthFlowRepository} from '../src/modules/auth/auth-flow.repository';
import {loadEnv,pgConfig} from './env.mjs';
const c=new pg.Client({...pgConfig(loadEnv()),query_timeout:20000});
let uid:number,authId:string;
let failEmail=false;
const sent:Array<{code:string;purpose:string}>=[];
const A='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function totp(secret:string) {
 const bits=[...secret].map(ch=>A.indexOf(ch).toString(2).padStart(5,'0')).join('');
 const key=Buffer.from(bits.match(/.{8}/g)!.map(v=>parseInt(v,2)));
 const counter=Buffer.alloc(8);counter.writeBigUInt64BE(BigInt(Math.floor(Date.now()/30000)));
 const h=crypto.createHmac('sha1',key).update(counter).digest(),off=h.at(-1)!&15;
 return String((h.readUInt32BE(off)&0x7fffffff)%1000000).padStart(6,'0');
}
class Repo extends AuthFlowRepository {
 async findUserForTwoFactor(id:number):Promise<Record<string,unknown>> {
  const u=(await c.query('select * from users where id=$1',[id])).rows[0];
  const s=(await c.query('select * from auth_two_factor_settings where user_id=$1',[id])).rows[0] ?? {};
  const inst=(await c.query('select * from institutions where id=$1',[u.institution_id])).rows[0];
  return {...u,institutions:inst,user_roles:[{roles:{code:'student'}}],two_factor:s.enabled===true,two_factor_method:s.method??'email',
   two_factor_secret:s.secret,two_factor_pending_secret:s.pending_secret,two_factor_pending_method:s.pending_method,
   two_factor_recovery_codes:s.recovery_codes??[],two_factor_locked_until:s.locked_until,two_factor_verified_at:s.verified_at};
 }
 async findLoginUserByIdentifier(){return this.findUserForTwoFactor(uid);}
 async findTwoFactorChallenge(id:string){return(await c.query('select * from auth_two_factor_challenges where id=$1',[id])).rows[0]??null;}
 async latestTwoFactorChallenge(id:number,purpose:string){return(await c.query('select * from auth_two_factor_challenges where user_id=$1 and purpose=$2 and consumed_at is null order by created_at desc limit 1',[id,purpose])).rows[0]??null;}
 async beginTwoFactor(args:Record<string,unknown>){
  const result=await c.query('select auth_2fa_begin($1,$2,$3,$4,$5,$6,$7,$8,$9) data',Object.values(args));
  return (this as any).factorResult({data:result.rows[0].data,error:null});
 }
 async verifyTwoFactor(args:Record<string,unknown>){
  const result=await c.query('select auth_2fa_verify($1,$2,$3,$4,$5,$6,$7,$8,$9) data',Object.values({...args,p_recovery_codes:JSON.stringify(args.p_recovery_codes)}));
  return (this as any).factorResult({data:result.rows[0].data,error:null});
 }
 async finishTwoFactorDelivery(id:string,success:boolean){await c.query("update auth_two_factor_challenges set delivery_status=$2,consumed_at=case when $3 then null else now() end where id=$1",[id,success?'sent':'failed',success]);}
 async updateLastSignIn(){}
}
const emails={async sendTwoFactorCode(_to:string,_name:string,code:string,purpose:string){if(failEmail)throw Error('Simulated provider failure');sent.push({code,purpose});}};
let lastSession:string;
const auth={async signInWithPassword(){lastSession=crypto.randomUUID();await c.query('insert into auth.sessions(id,user_id) values($1,$2)',[lastSession,authId]);return{data:{session:{access_token:`eyJhbGciOiJIUzI1NiJ9.${Buffer.from(JSON.stringify({sub:authId,session_id:lastSession})).toString('base64url')}.test`,refresh_token:'withheld-fixture-token'},user:{id:authId,email:'fixture@invalid.test'}},error:null};}};
const repo=new Repo(),service=new AuthFlowService(repo,emails as any,auth as any);
const rejects=async(fn:()=>Promise<unknown>,status:number)=>{await assert.rejects(fn,e=>(e as any).status===status);};
async function claims(sessionId:string){await c.query('reset role');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:authId,role:'authenticated',session_id:sessionId,app_metadata:{institution_id:2}})]);await c.query('set local role authenticated');}
async function maintenance(){await c.query('reset role');await c.query("select set_config('request.jwt.claims','{}',true)");}
async function denySQL(sql:string){await c.query('savepoint denial');await assert.rejects(c.query(sql));await c.query('rollback to savepoint denial');}
async function cooldown(){await c.query("update auth_two_factor_challenges set created_at=least(created_at,now()-interval '61 seconds') where user_id=$1",[uid]);}
async function main(){
 const originalNow=Date.now;try {Date.now=()=>59000;assert.equal((service as any).verifyTotp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ','287082'),true,'RFC TOTP reference vector');} finally {Date.now=originalNow;}
 await c.connect();await c.query('begin');authId=crypto.randomUUID();
 await c.query('insert into auth.users(id) values($1)',[authId]);
 uid=Number((await c.query('insert into users(institution_id,auth_user_id,email,full_name) values(2,$1,$2,$3) returning id',[authId,`${authId}@invalid.test`,'Rollback MFA fixture'])).rows[0].id);
 const current=crypto.randomUUID();await c.query('insert into auth.sessions(id,user_id) values($1,$2)',[current,authId]);
 const setup=await service.setupTwoFactor(uid,{method:'totp'});
 assert.match(setup.secret!,/^[A-Z2-7]{32}$/);assert.equal(new URL(setup.otpauthUrl!).searchParams.get('secret'),setup.secret);assert.equal(sent.length,0);
 const wrong=totp(setup.secret!)==='000000'?'999999':'000000';
 await rejects(()=>service.enableTwoFactor(uid,{challengeId:setup.id,code:wrong},current),401);
 const enabled=await service.enableTwoFactor(uid,{challengeId:setup.id,code:totp(setup.secret!)},current);
 assert.equal(enabled.method,'totp');assert.equal(enabled.recoveryCodes.length,10);
 assert.equal((await service.twoFactorStatus(uid)).enabled,true);
 await rejects(()=>service.setupTwoFactor(uid,{method:'email'}),409);
 await claims(current);
 assert.equal((await c.query('select auth_2fa_session_allowed() ok')).rows[0].ok,true);
 await denySQL('select * from auth_two_factor_settings');await denySQL('select * from auth_two_factor_challenges');
 await denySQL(`update users set two_factor=false where id=${uid}`);
 assert.equal((await c.query('select two_factor_secret from users where id=$1',[uid])).rows[0].two_factor_secret,null);
 await maintenance();
 const login=await service.login({username:'fixture@invalid.test',password:'fixture'});
 assert.equal(login.twoFactorRequired,true);assert.equal((login as any).session,undefined);
 await claims(lastSession);assert.equal((await c.query('select id from users where id=$1',[uid])).rowCount,0,'Password-only tokens cannot read protected data');assert.equal((await c.query('select current_institution_id() inst')).rows[0].inst,null);
 await maintenance();
 const responses=await Promise.allSettled([service.verifyTwoFactorLogin({challengeId:login.challenge.id,code:totp(setup.secret!)}),service.verifyTwoFactorLogin({challengeId:login.challenge.id,code:totp(setup.secret!)})]);
 assert.equal(responses.filter(r=>r.status==='fulfilled').length,1,'A challenge succeeds once even under competing confirmations');
 await claims(lastSession);assert.equal((await c.query('select id from users where id=$1',[uid])).rowCount,1);await maintenance();
 const rLogin=await service.login({username:'fixture',password:'fixture'});await service.verifyTwoFactorLogin({challengeId:rLogin.challenge.id,recoveryCode:enabled.recoveryCodes[0]});
 const again=await service.login({username:'fixture',password:'fixture'});await rejects(()=>service.verifyTwoFactorLogin({challengeId:again.challenge.id,recoveryCode:enabled.recoveryCodes[0]}),401);
 await service.disableTwoFactor(uid,{recoveryCode:enabled.recoveryCodes[1]});
 let email=await service.setupTwoFactor(uid,{method:'email'});assert.equal(sent.at(-1)!.purpose,'setup');assert.equal(email.secret,null);assert.equal(JSON.stringify(email).includes(sent.at(-1)!.code),false);
 await rejects(()=>service.setupTwoFactor(uid,{method:'email'}),429);
 await cooldown();const old=email;email=await service.setupTwoFactor(uid,{method:'email'});
 await rejects(()=>service.enableTwoFactor(uid,{challengeId:old.id,code:sent[0].code},current),401);
 await c.query("update auth_two_factor_challenges set expires_at=now()-interval '1 second' where id=$1",[email.id]);
 await rejects(()=>service.enableTwoFactor(uid,{challengeId:email.id,code:sent.at(-1)!.code},current),401);
 await cooldown();email=await service.setupTwoFactor(uid,{method:'email'});
 const emailEnabled=await service.enableTwoFactor(uid,{challengeId:email.id,code:sent.at(-1)!.code},current);
 assert.equal(emailEnabled.method,'email');assert.equal((await service.twoFactorStatus(uid)).hasAuthenticator,false);
 await cooldown();const emailLogin=await service.login({username:'fixture',password:'fixture'});assert.equal(emailLogin.challenge.method,'email');assert.equal((emailLogin.challenge as any).debugCode,undefined);
 const loginWrong=sent.at(-1)!.code==='000000'?'999999':'000000';
 await rejects(()=>service.verifyTwoFactorLogin({challengeId:emailLogin.challenge.id,code:loginWrong}),401);
 const failuresBefore=(await c.query('select failed_attempts from auth_two_factor_settings where user_id=$1',[uid])).rows[0].failed_attempts;
 await cooldown();const resend=await service.resendTwoFactorLogin({challengeId:emailLogin.challenge.id});
 assert.notEqual(resend.challenge.id,emailLogin.challenge.id);
 assert.equal((await c.query('select failed_attempts from auth_two_factor_settings where user_id=$1',[uid])).rows[0].failed_attempts,failuresBefore,'Resending never resets the account attempt counter');
 await rejects(()=>service.verifyTwoFactorLogin({challengeId:emailLogin.challenge.id,code:sent.at(-2)!.code}),401);
 await service.verifyTwoFactorLogin({challengeId:resend.challenge.id,code:sent.at(-1)!.code});
 await cooldown();await rejects(()=>service.sendTwoFactorEmailCode(uid,{purpose:'disable'}),429);
 await c.query("update auth_two_factor_challenges set created_at=now()-interval '2 hours' where user_id=$1",[uid]);
 let disable=await service.sendTwoFactorEmailCode(uid,{purpose:'disable'});
 const bad=sent.at(-1)!.code==='000000'?'999999':'000000';
 for(let i=0;i<5;i++)await assert.rejects(service.disableTwoFactor(uid,{challengeId:disable.id,code:bad}));
 await rejects(()=>service.disableTwoFactor(uid,{challengeId:disable.id,code:sent.at(-1)!.code}),423);
 await c.query("update auth_two_factor_settings set locked_until=now()-interval '1 second' where user_id=$1",[uid]);await cooldown();
 disable=await service.sendTwoFactorEmailCode(uid,{purpose:'disable'});await service.disableTwoFactor(uid,{challengeId:disable.id,code:sent.at(-1)!.code});
 assert.equal((await service.twoFactorStatus(uid)).enabled,false);
 await cooldown();failEmail=true;
 await rejects(()=>service.setupTwoFactor(uid,{method:'email'}),502);
 assert.equal((await service.twoFactorStatus(uid)).enabled,false);
 assert.equal((await c.query("select count(*)::int n from auth_two_factor_challenges where user_id=$1 and delivery_status='failed' and consumed_at is not null",[uid])).rows[0].n,1);
 console.log('2FA checks passed: TOTP URI/secret, both enrollments, login, expiry, atomic one-time challenges and recovery codes, resend/cooldown/hour cap, lockouts, provider failure, private secrets and password-only API/RLS denial. No real email sent; all fixtures rolled back.');
}
main().finally(async()=>{await c.query('reset role').catch(()=>{});await c.query('rollback').catch(()=>{});await c.end();}).catch(e=>{console.error(e);process.exitCode=1;});
