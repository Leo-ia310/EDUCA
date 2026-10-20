import { HttpError } from "../../lib/errors";
import { supabaseAdmin } from "../../lib/supabase";

export class SchedulesRepository {
  constructor(private readonly db: any = supabaseAdmin) {}

  async list(institutionId: number, filters: Record<string, unknown>, mine = false, studentId: number | null = null) {
    return this.call("schedule_list", { p_institution_id: institutionId, p_filters: filters, p_mine: mine, p_student_id: studentId });
  }
  async write(institutionId: number, action: string, payload: Record<string, unknown>, id: number | null = null) {
    return this.call("schedule_write", { p_institution_id: institutionId, p_action: action, p_payload: payload, p_id: id });
  }
  private async call(name: string, args: Record<string, unknown>) {
    const { data, error } = await this.db.rpc(name, args);
    if (error) {
      const conflict = error.code === "23P01";
      const invalid = ["22023", "22P02", "22007", "22008", "23514", "22001"].includes(error.code);
      throw new HttpError(conflict ? 409 : error.code === "42501" ? 403 : error.code === "P0002" ? 404 : invalid ? 400 : 503,
        conflict ? "Choque de horario: grupo, maestro o aula ocupados." : error.code === "42501" ? "Acceso denegado." : error.code === "P0002" ? "Horario no encontrado." : invalid ? "Datos de horario inválidos." : "No se pudo procesar el horario.",
        conflict ? "schedule_conflict" : invalid ? "validation_error" : "schedule_error");
    }
    return data;
  }
}
export const schedulesRepository = new SchedulesRepository();
