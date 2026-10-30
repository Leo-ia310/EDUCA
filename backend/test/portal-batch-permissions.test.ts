import assert from 'node:assert/strict';
import {test} from 'node:test';
process.env.NODE_ENV='test';
process.env.SUPABASE_URL='https://fixture.supabase.co';
process.env.SUPABASE_ANON_KEY='fixture';
const {PortalAccessService}=require('../src/modules/portal-access/portal-access.service') as typeof import('../src/modules/portal-access/portal-access.service');

test('user editor loads effective permissions and saves independent states in one scoped RPC',async()=>{
  const calls:unknown[]=[];
  const service=new PortalAccessService({rpc:async(name:string,args:unknown)=>{calls.push({name,args});return {data:{userId:13,permissions:{},overrides:{}},error:null};}});
  await service.userPermissions('13');
  const changes=[{permission:'reports.view',allowed:true},{permission:'reports.download',allowed:false}];
  await service.manage({action:'save_user_permissions',userId:13,permissions:changes});
  assert.deepEqual(calls,[
    {name:'portal_user_permissions',args:{p_user_id:13}},
    {name:'manage_portal_user_permissions',args:{p_user_id:13,p_changes:changes}},
  ]);
});

test('user editor rejects missing targets, duplicate codes and non-boolean states before writing',()=>{
  const service=new PortalAccessService({rpc:()=>{throw Error('Unexpected database call');}});
  for(const permissions of [undefined,[],[null],[{permission:'reports.view',allowed:'false'}],['reports.view'],
    [{permission:'bad',allowed:false}],[{permission:'reports.view',allowed:false},{permission:'reports.view',allowed:true}]]) {
    assert.throws(()=>service.manage({action:'save_user_permissions',userId:13,permissions}),{status:400});
  }
  assert.throws(()=>service.userPermissions('invalid'),{status:400});
  assert.throws(()=>service.manage({action:'save_user_permissions',permissions:[{permission:'reports.view',allowed:true}]}),{status:400});
});

test('multiple permission changes use one atomic RPC and preserve explicit false',async()=>{
  const calls:unknown[]=[];
  const service=new PortalAccessService({rpc:async(name:string,args:unknown)=>{
    calls.push({name,args});return {data:{permissionRules:[]},error:null};
  }});
  const payload={action:'save_permissions',scope:'user',userId:13,permissions:['reports.view','reports.download','payments.view'],allowed:false};
  await service.manage(payload);
  assert.deepEqual(calls,[{name:'manage_portal_permissions',args:{p_payload:payload}}]);
});

test('invalid batches are rejected before any database write',()=>{
  const service=new PortalAccessService({rpc:()=>{throw Error('No database calls allowed');}});
  for(const permissions of [undefined,[],['reports.view','reports.view'],['reports.view','unknown'],[1],Array(12).fill('reports.view')]) {
    assert.throws(()=>service.manage({action:'save_permissions',permissions,allowed:false}),{status:400});
  }
  assert.throws(()=>service.manage({action:'save_permissions',permissions:['reports.view'],allowed:'false'}),{status:400});
});

test('batch authorization faults remain forbidden and single-rule clients still work',async()=>{
  const denied=new PortalAccessService({rpc:async()=>({data:null,error:{code:'42501',message:'denied'}})});
  await assert.rejects(denied.manage({action:'save_permissions',permissions:['reports.download'],allowed:false}),{status:403});
  const calls:string[]=[];
  const compatible=new PortalAccessService({rpc:async(name:string)=>{calls.push(name);return {data:{},error:null};}});
  await compatible.manage({action:'save_permission',permission:'reports.view',allowed:true});
  assert.deepEqual(calls,['manage_portal_access']);
});
