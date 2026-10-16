import { expectSingle } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import { supabaseAdmin } from "../../lib/supabase";
import { permissionsService } from "../../services/permissions.service";
import type { AppContext } from "../../types/app-context";
import { requiredId, requiredString } from "../../validators/common.validators";

export const CLASS_PERMISSIONS = ["class.view", "students.view", "assignments.create", "assignments.review", "assignments.grade", "grades.write", "attendance.write"];
export class CollaborationService {
  constructor(private readonly client: any = supabaseAdmin) {}
  async workspace(ctx: AppContext) {
    permissionsService.requireRole(ctx, ["teacher"]);
    return expectSingle<Record<string, any>>(this.client.rpc("collaboration_workspace"), "No se pudieron cargar las colaboraciones.");
  }
  async manage(ctx: AppContext, payload: Record<string, unknown>) {
    permissionsService.requireRole(ctx, ["teacher"]);
    const action = requiredString(payload.action, "Acción", 20);
    if (!["invite", "accept", "decline", "revoke", "update"].includes(action)) throw new HttpError(400, "Acción inválida.", "validation_error");
    const args: Record<string, unknown> = { p_action: action };
    if (["invite", "update"].includes(action)) {
      if (!Array.isArray(payload.permissions) || payload.permissions.some((p) => !CLASS_PERMISSIONS.includes(String(p)))) {
        throw new HttpError(400, "Permisos de colaboración inválidos.", "validation_error");
      }
      args.p_permissions = payload.permissions;
    }
    if (action === "invite") {
      if (!Array.isArray(payload.classIds) || payload.classIds.length === 0 || payload.classIds.length > 100) {
        throw new HttpError(400, "Selecciona entre una y cien clases.", "validation_error");
      }
      args.p_class_ids = [...new Set(payload.classIds.map((id) => requiredId(id, "Clase")))];
      args.p_teacher_user_id = requiredId(payload.teacherUserId, "Profesor");
    } else args.p_invitation_id = requiredId(payload.invitationId, "Invitación");
    // RPC checks actor/tenant/ownership again and applies the batch atomically.
    return expectSingle<Record<string, any>>(this.client.rpc("manage_class_collaboration", args), "No se pudo actualizar la colaboración.");
  }
}
export const collaborationService = new CollaborationService();
