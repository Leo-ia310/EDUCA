import assert from 'node:assert/strict';
import {test} from 'node:test';
import {AssignmentsService} from '../src/modules/assignments/assignments.service';
import {AssignmentsRepository} from '../src/modules/assignments/assignments.repository';
import type {AppContext} from '../src/types/app-context';
import type {PermissionsService} from '../src/services/permissions.service';
class Repository extends AssignmentsRepository {
  calls: {id:number|null;data:Record<string,unknown>;files:number[]|null;key:string}[]=[];
  flag=true;flagWrites:boolean[]=[];
  override async commentFlags(ids:number[]){return new Map(ids.map(id=>[id,this.flag]));}
  override async setCommentFlag(_id:number,allow:boolean){this.flag=allow;this.flagWrites.push(allow);}
  override async writeAssignment(id:number|null,data:Record<string,unknown>,files:number[]|null,key:string) {
    this.calls.push({id,data,files,key});return {id:'42'};
  }
}
const ctx:AppContext={authUserId:'fixture',userId:1,institutionId:2,personId:3,fullName:'Fixture',roles:new Set(['teacher']),adminPermissions:null};
const payload={classId:4,title:'Task',dueAt:'2026-11-01T12:00:00Z',maxScore:100,idempotencyKey:'a0b82166-cb05-487f-a631-04764bff3737'};
test('assignment save makes one repository call with a stable receipt key and canonical attachment IDs',async()=>{
  const repository=new Repository(),service=new AssignmentsService(repository);
  assert.deepEqual(await service.upsertAssignment(ctx,{...payload,attachments:[{id:'8'},{id:7},{id:8}]}),{assignment:{id:'42',allowStudentComments:true}});
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

test('attachment response failures retain dependency status and never expose database details',async()=>{
  class Attachments extends AssignmentsRepository {
    override async unlinkAssignmentFile() {}
    override async attachmentRows() {return {data:null,error:{code:'57014',message:'private SQL relation'}};}
  }
  const permissions={requireRole(){},async assertTeacherCanUseAssignment(){}} as unknown as PermissionsService;
  const service=new AssignmentsService(new Attachments(),permissions);
  await assert.rejects(service.removeAttachment(ctx,42,8),(error:any)=>error.status===503&&!error.message.includes('private SQL'));
});

test('grading rejects a score above the assignment maximum and never reaches the grade RPC',async()=>{
  let graded=0;
  class Grading extends AssignmentsRepository {
    override async findSubmissionWithAssignment(){return {id:5,assignment_id:9,assignments:{class_id:4,max_score:20}};}
    override async gradeSubmissionRpc(){graded++;return {error:null} as never;}
  }
  const permissions={requireRole(){},async assertTeacherCanUseClass(){}} as unknown as PermissionsService;
  const service=new AssignmentsService(new Grading(),permissions);
  await assert.rejects(service.gradeSubmission(ctx,{submissionId:5,score:999}),{status:400});
  await assert.rejects(service.gradeSubmission(ctx,{submissionId:5,score:-1}),{status:400});
  assert.equal(graded,0);
});

test('allowStudentComments is persisted only when sent and is echoed back',async()=>{
  const repository=new Repository(),service=new AssignmentsService(repository);
  const off=await service.upsertAssignment(ctx,{...payload,allowStudentComments:false});
  assert.equal((off.assignment as any).allowStudentComments,false);
  assert.deepEqual(repository.flagWrites,[false]);
  await service.upsertAssignment(ctx,payload);
  assert.deepEqual(repository.flagWrites,[false]);
  assert.equal(repository.calls[1].data.allow_student_comments,undefined);
});
