import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test, mock } from 'node:test';
import express from 'express';
import type { AppContext, AppRequest } from '../src/types/app-context';
process.env.NODE_ENV='test';process.env.SUPABASE_URL='https://fixture.supabase.co';process.env.SUPABASE_ANON_KEY='fixture-public';
const { originalityReport, originalityRetry } = require('../src/modules/assignments/originality/originality.controller') as typeof import('../src/modules/assignments/originality/originality.controller');
const { originalityService } = require('../src/modules/assignments/originality/originality.service') as typeof import('../src/modules/assignments/originality/originality.service');
const { requireRoles } = require('../src/middleware/permissions.middleware') as typeof import('../src/middleware/permissions.middleware');
const { asyncHandler, errorHandler } = require('../src/middleware/error.middleware') as typeof import('../src/middleware/error.middleware');
test('HTTP contract validates ID/query/body and protects role/missing session before exposing report',async()=>{
 const app=express();app.use(express.json());
 app.use((req:AppRequest,_res,next)=>{
  if(req.header('x-test-role'))req.appContext={userId:1,institutionId:1,roles:new Set([req.header('x-test-role')!]),authUserId:'fixture',personId:1,fullName:'Teacher',adminPermissions:null} satisfies AppContext;
  next();
 });
 app.get('/submissions/:submissionId/originality',requireRoles(['teacher']),asyncHandler(originalityReport));
 app.post('/submissions/:submissionId/originality/retry',requireRoles(['teacher']),asyncHandler(originalityRetry));app.use(errorHandler);
 const calls:unknown[][]=[];
 const report=mock.method(originalityService,'report',async(...args:unknown[])=>{calls.push(args);return {documents:[],notice:'Orientativo'};});
 const server=app.listen(0,'127.0.0.1');await once(server,'listening');const url=`http://127.0.0.1:${(server.address() as {port:number}).port}/submissions/5/originality`;
 try{
  assert.equal((await fetch(url)).status,401);
  assert.equal((await fetch(url,{headers:{'x-test-role':'student'}})).status,403);
  assert.equal((await fetch(url+'?evidence=all',{headers:{'x-test-role':'teacher'}})).status,400);
  const response=await fetch(url+'?evidence=true',{headers:{'x-test-role':'teacher'}});
  assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'private, no-store');
  assert.deepEqual(await response.json(),{ok:true,data:{documents:[],notice:'Orientativo'}});
  assert.equal(calls[0][1],5);assert.equal(calls[0][2],true);
  assert.equal((await fetch(url+'/retry',{method:'POST',headers:{'x-test-role':'teacher','content-type':'application/json'},body:'{"institutionId":2}'})).status,400);
  const retried=await fetch(url+'/retry',{method:'POST',headers:{'x-test-role':'teacher','content-type':'application/json'},body:'{}'});
  assert.equal(retried.status,200);assert.equal(retried.headers.get('cache-control'),'private, no-store');
  assert.equal(calls.at(-1)![3],true);
 }finally{report.mock.restore();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});
