import { transactionRpc } from "../../lib/transaction-rpc";
import { HttpError } from "../../lib/errors";
import type { PageOptions } from "../../lib/pagination";
import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class ReportsRepository {
  async findStudent(institutionId: number, studentId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("students")
        .select("id, person_id, institution_id, persons(first_name, last_name)")
        .eq("institution_id", institutionId)
        .eq("id", studentId)
        .single(),
      "Estudiante no encontrado.",
    );
  }

  async listPeriodGrades(
    institutionId: number,
    studentId: number,
    academicPeriodId: number,
  ) {
    const { data, error } = await db
      .from("period_grades")
      .select("*, subjects(name), classes(id, subjects(name), teachers(id, persons(first_name, last_name)))")
      .eq("institution_id", institutionId)
      .eq("student_id", studentId)
      .eq("academic_period_id", academicPeriodId)
      .order("subject_id");
    assertNoDbError(error);
    return data ?? [];
  }

  async generateReportCard(studentId:number,periodId:number,notes:string|null,key:string) {
    return transactionRpc(db,"report_card_generate",{p_student:studentId,p_period:periodId,p_notes:notes,p_key:key});
  }

  /** Boletines de la institución, del más reciente al más antiguo; filtra por periodo y/o alumnos. */
  async listReportCards(filters: {academicPeriodId:number|null; studentId:number|null; groupId:number|null}, page:PageOptions) {
    const {data,error}=await db.rpc("latest_report_cards",{p_period_id:filters.academicPeriodId,p_student_id:filters.studentId,
      p_group_id:filters.groupId,p_page:page.page,p_page_size:page.pageSize});
    if(error)throw new HttpError(error.code==="42501"?403:error.code==="22023"?400:503,
      error.code==="42501"?"Acceso denegado.":error.code==="22023"?"Filtros inválidos.":"No se pudieron consultar los boletines.","report_query_error");
    return data;
  }

  async findReportCard(institutionId: number, id: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("report_cards")
        .select("*, report_card_lines(*, subjects(name))")
        .eq("institution_id", institutionId)
        .eq("id", id)
        .single(),
      "Boletín no encontrado.",
    );
  }
}

export const reportsRepository = new ReportsRepository();
