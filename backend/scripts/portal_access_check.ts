import assert from "node:assert/strict";
import { PortalAccessService } from "../src/modules/portal-access/portal-access.service";
import type { AppContext } from "../src/types/app-context";
import { HttpError } from "../src/lib/errors";

const parent = { institutionId: 2, userId: 7, roles: new Set(["parent"]) } as AppContext;
const calls: Array<{name: string; args: Record<string,unknown>}> = [];
let allowed = false;
let error: {code: string; message: string} | null = null;
const client = {
  async rpc(name: string, args: Record<string,unknown> = {}) {
    calls.push({name,args});
    return {data: name === "portal_can" || name === "portal_can_view_grades" ? allowed : {},error};
  },
};
const service = new PortalAccessService(client);
const forbidden = (e: unknown) => (e as HttpError)?.status === 403;
async function main() {
  for (const [path,method,body,permission] of [
    ["/api/payments/charges","GET",{},"payments.view"],
    ["/api/assignments/2/submit","POST",{},"assignments.view"],
    ["/api/reports/report-cards/preview","GET",{},"reports.view"],
    ["/api/attendance/sessions","GET",{},"attendance.view"],
    ["/api/schedules","GET",{},"schedule.view"],
    ["/api/events/announcements","GET",{},"announcements.view"],
    ["/api/files/42","GET",{},"materials.view"],
    ["/api/chats/2/messages","POST",{},"messages.send"],
    ["/api/business-api","POST",{action:"chat.sendMessage"},"messages.send"],
  ] as const) {
    calls.length=0;
    await assert.rejects(service.enforceRequest(parent,path,method,body),forbidden);
    assert.equal(calls[0].args.p_permission,permission);
  }
  for (const body of [{action:"chat.markAsRead"},{action:"chat.markConversationAsRead"}]) {
    calls.length=0;
    await service.enforceRequest(parent,"/api/business-api","POST",body);
    assert.equal(calls.length,0,"Reading must remain available when sending is restricted");
  }
  calls.length=0;
  await service.enforceRequest(parent,"/api/chats/2/read","POST",{});
  await service.enforceRequest({...parent,roles:new Set(["teacher"])},"/api/payments/charges","GET",{});
  assert.equal(calls.length,0,"Staff retain their existing permission boundaries");
  await assert.rejects(service.requireGrades(parent,10,2),forbidden);
  assert.deepEqual(calls.at(-1)?.args,{p_student_id:10,p_period_id:2});
  allowed=true;
  calls.length=0;
  await service.enforceRequest(parent,"/api/business-api","POST",{action:"assignments.submit"});
  assert.deepEqual(calls.map(c=>c.args.p_permission),["assignments.view","assignments.submit"]);
  calls.length=0;
  await service.enforceRequest(parent,"/api/reports/report-cards/12","GET",{});
  assert.deepEqual(calls.map(c=>c.args.p_permission),["reports.view","reports.download"]);
  for (const payload of [{action:"unknown"},{action:"save_permission",allowed:"false",permission:"grades.view"},{action:"save_permission",allowed:true,permission:"all"}]) {
    assert.throws(()=>service.manage(payload),e=>(e as HttpError)?.status === 400);
  }
  error={code:"42501",message:"No tienes permiso para gestionar accesos."};
  await assert.rejects(service.config(),forbidden);
  await assert.rejects(service.manage({action:"save_permission",scope:"user",userId:7,permission:"grades.view",allowed:false}),forbidden);
  console.log("Portal API checks passed: HTTP 403 restrictions, REST and business actions, read-only chat, submission/export checks, staff access, RPC authorization and payload validation.");
}
void main().catch(error=>{ console.error(error);process.exitCode=1; });
