import assert from 'node:assert/strict';
import {test} from 'node:test';
import {AssignmentsService} from '../src/modules/assignments/assignments.service';
import {AssignmentsRepository} from '../src/modules/assignments/assignments.repository';
import type {AppContext} from '../src/types/app-context';
class Repository extends AssignmentsRepository {
  calls: {id:number|null;data:Record<string,unknown>;files:number[]|null;key:string}[]=[];
  override async writeAssignment(id:number|null,data:Record<string,unknown>,files:number[]|null,key:string) {
    this.calls.push({id,data,files,key});return {id:'42'};
  }
}
const ctx:AppContext={authUserId:'fixture',userId:1,institutionId:2,personId:3,fullName:'Fixture',roles:new Set(['teacher']),adminPermissions:null};
const payload={classId:4,title:'Task',dueAt:'2026-11-01T12:00:00Z',maxScore:100,idempotencyKey:'a0b82166-cb05-487f-a631-04764bff3737'};
test('assignment save makes one repository call with a stable receipt key and canonical attachment IDs',async()=>{
  const repository=new Repository(),service=new AssignmentsService(repository);
  assert.deepEqual(await service.upsertAssignment(ctx,{...payload,attachments:[{id:'8'},{id:7},{id:8}]}),{assignment:{id:'42'}});
  assert.equal(repository.calls.length,1);assert.deepEqual(repository.calls[0].files,[7,8]);
  assert.equal(repository.calls[0].key,payload.idempotencyKey);
  await service.upsertAssignment(ctx,payload);assert.equal(repository.calls[1].files,null);
  await service.upsertAssignment(ctx,{...payload,attachments:[]});assert.deepEqual(repository.calls[2].files,[]);
});
test('malformed attachments cannot silently become an empty replacement or cause a partial write',async()=>{
  const repository=new Repository(),service=new AssignmentsService(repository);
  for(const attachments of ['bad',{},[{}],[null],[{id:'invalid'}],Array.from({length:101},()=>({id:1}))]) {
    await assert.rejects(service.upsertAssignment(ctx,{...payload,attachments}),{status:400});
  }
  assert.equal(repository.calls.length,0);
});
