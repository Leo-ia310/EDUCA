import assert from 'node:assert/strict';
import {test} from 'node:test';
process.env.NODE_ENV='test';process.env.SUPABASE_URL='https://fixture.supabase.co';process.env.SUPABASE_ANON_KEY='fixture';
const {PortalAccessService}=require('../src/modules/portal-access/portal-access.service') as typeof import('../src/modules/portal-access/portal-access.service');

test('portal permission queries distinguish dependency faults from invalid input without leaking SQL',async()=>{
  for(const [code,status] of [['57014',503],['42501',403],['22023',400],['42P01',503]] as const) {
    const service=new PortalAccessService({rpc:async()=>({data:null,error:{code,message:'private SQL relation password'}})});
    await assert.rejects(service.me(),(e:any)=>e.status===status&&!e.message.includes('private SQL'));
  }
  const empty=new PortalAccessService({rpc:async()=>({data:null,error:null})});
  await assert.rejects(empty.me(),{status:503,code:'database_unavailable'});
});
