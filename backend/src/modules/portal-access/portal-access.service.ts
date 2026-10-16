import { assertNoDbError } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { supabaseAdmin } from "../../lib/supabase";
import { permissionsService } from "../../services/permissions.service";
import type { AppContext } from "../../types/app-context";
import { optionalId, requiredString } from "../../validators/common.validators";

export const PORTAL_PERMISSIONS = ["grades.view","payments.view","attendance.view","schedule.view","assignments.view","assignments.submit","reports.view","reports.download","announcements.view","messages.send","materials.view"];
export class PortalAccessService {
  constructor(private readonly client: any = supabaseAdmin) {}
  private staff(ctx: AppContext) { return [...ctx.roles].some((role) => ["teacher","admin","coordinator","director","super_admin"].includes(role)); }
  async require(ctx: AppContext, permission: string) {
    if (this.staff(ctx)) return;
    const {data,error} = await this.client.rpc("portal_can", {p_permission:permission});
    assertNoDbError(error);
    if (data !== true) throw new HttpError(403,"Esta sección está restringida por tu institución.","portal_access_restricted");
  }
  private async rpc(query: PromiseLike<{data: unknown; error: {code?: string; message: string} | null}>, message: string) {
    const {data,error}=await query;
    if(error) throw new HttpError(error.code === "42501" ? 403 : 400,error.message,error.code === "42501" ? "forbidden" : "db_error");
    if(data == null) throw new HttpError(500,message,"db_error");
    return data as Record<string,unknown>;
  }
  me() { return this.rpc(this.client.rpc("portal_access_me"),"No se pudieron consultar tus permisos."); }
  config() { return this.rpc(this.client.rpc("portal_access_admin"),"No se pudo consultar la configuración de accesos."); }
  manage(payload: Record<string,unknown>) {
    const action=requiredString(payload.action,"Acción",30);
    if (!["save_permission","delete_permission","save_visibility","delete_visibility"].includes(action)) throw new HttpError(400,"Acción inválida.","validation_error");
    if (action.startsWith("save_")) {
      if (typeof payload.allowed !== "boolean") throw new HttpError(400,"Indica si el acceso está habilitado.","validation_error");
      if (action === "save_permission" && !PORTAL_PERMISSIONS.includes(String(payload.permission))) throw new HttpError(400,"Permiso inválido.","validation_error");
    }
    return this.rpc(this.client.rpc("manage_portal_access",{p_action:action,p_payload:payload}),"No se pudo guardar la configuración de accesos.");
  }
  async requireGrades(ctx: AppContext, studentId: number, periodId: number | null) {
    if (this.staff(ctx)) return;
    const {data,error}=await this.client.rpc("portal_can_view_grades",{p_student_id:studentId,p_period_id:periodId});
    assertNoDbError(error);
    if (data !== true) throw new HttpError(403,"Las notas de este estudiante o periodo están ocultas por la institución.","grades_hidden");
  }
  async grades(ctx: AppContext, query: Record<string,unknown>) {
    const studentId=await permissionsService.normalizeStudentId(ctx,query.studentId);
    const periodId=optionalId(query.periodId);
    await this.requireGrades(ctx,studentId,periodId);
    let request=this.client.from("grades").select("id,score,notes,evaluations!inner(id,title,academic_period_id,max_score,classes(subjects(name)))")
      .eq("institution_id",ctx.institutionId).eq("student_id",studentId);
    if (periodId != null) request=request.eq("evaluations.academic_period_id",periodId);
    const {data,error}=await request.order("id"); assertNoDbError(error);
    return {grades:data ?? [],studentId,periodId};
  }
  async enforceRequest(ctx: AppContext, path: string, method: string, body: Record<string,unknown>) {
    if (this.staff(ctx)) return;
    const action=String(body.action ?? "");
    const route=path.split("?")[0];
    const target=(route.endsWith("/business-api") ? action : route).toLowerCase();
    if (target.includes("payments") || target.includes("charges")) await this.require(ctx,"payments.view");
    else if (target.includes("reports")) { await this.require(ctx,"reports.view"); if (method === "GET" && /\/report-cards\/\d+/.test(path)) await this.require(ctx,"reports.download"); }
    else if (target.includes("assignments")) { await this.require(ctx,"assignments.view"); if (target.includes("submit")) await this.require(ctx,"assignments.submit"); }
    else if (target.includes("attendance")) await this.require(ctx,"attendance.view");
    else if (target.includes("schedules")) await this.require(ctx,"schedule.view");
    else if (target.includes("events")) await this.require(ctx,"announcements.view");
    else if ((target.includes("chat") && (method === "POST" && !target.includes("read"))) || /chats\.(sendMessage|ensureIndividual)/.test(action)) await this.require(ctx,"messages.send");
    else if (path.includes("/files") && method === "GET") await this.require(ctx,"materials.view");
  }
}
export const portalAccessService=new PortalAccessService();
