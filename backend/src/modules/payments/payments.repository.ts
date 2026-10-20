import {databaseError} from "../../lib/database-error";
import { transactionRpc } from "../../lib/transaction-rpc";
import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";
import { HttpError } from "../../lib/errors";
import { readAllPages } from "../../lib/read-all";

const db = supabaseAdmin as any;

export class PaymentsRepository {
  private assertPaymentError(error: { code?: string; message: string } | null) {
    if (!error) return;
    throw databaseError(error);
  }

  async registerChargePayment(chargeId: number, amount: number, method: string, reference: string | null, uuid: string) {
    const { data, error } = await db.rpc("register_charge_payment", {
      p_charge_id: chargeId, p_amount: amount, p_method: method, p_reference: reference, p_uuid: uuid,
    });
    this.assertPaymentError(error);
    if (data == null) throw new HttpError(503, "No se pudo confirmar el pago.", "payment_unavailable");
    return data as Record<string, unknown>;
  }

  async cancelCharge(chargeId: number) {
    // The RPC derives institution and actor from the verified JWT, never input.
    const { error } = await db.rpc("cancel_unpaid_charge", { p_charge_id: chargeId });
    this.assertPaymentError(error);
    return { error: null };
  }

  async collectionSummary() {
    const { data, error } = await db.rpc("payment_collection_summary");
    assertNoDbError(error);
    return data;
  }

  async paidTotals(chargeIds: number[]) {
    const totals = new Map<number, number>();
    for (let i = 0; i < chargeIds.length; i += 200) {
      const { data, error } = await db.rpc("payment_charge_totals", { p_charge_ids: chargeIds.slice(i, i + 200) });
      assertNoDbError(error);
      for (const row of data ?? []) totals.set(Number(row.charge_id), Number(row.paid));
    }
    return totals;
  }

  // ---------- Administración (panel web) ----------

  private readonly chargeSelect =
    "id, student_id, concept_id, description, amount, discount, late_fee, total_amount, due_at, status, created_at, institutions!charges_institution_id_fkey(timezone), students(persons(first_name, last_name)), payment_concepts(name, catalog_currencies(iso_code))";

  async listCharges(institutionId: number, studentIds: number[] | null) {
    if (studentIds != null && studentIds.length === 0) return [] as Record<string, unknown>[];
    return readAllPages<Record<string, unknown>>((from, to) => {
    let query = db
      .from("charges")
      .select(this.chargeSelect)
      .eq("institution_id", institutionId)
      .order("due_at", { ascending: false })
      .order("id", { ascending: false });
    if (studentIds != null) query = query.in("student_id", studentIds);
    return query.range(from, to);
    });
  }

  async findCharge(institutionId: number, id: number) {
    return expectSingle<Record<string, unknown>>(
      db.from("charges").select(this.chargeSelect).eq("institution_id", institutionId).eq("id", id).single(),
      "Cargo no encontrado.",
    );
  }

  /** Historial completo de un cargo, sin descargar pagos de otros alumnos. */
  async paidPayments(institutionId: number, chargeId: number) {
    return readAllPages<Record<string, unknown>>((from, to) => db
      .from("payments")
      .select("id, charge_id, amount, payment_method, receipt_number, reference, paid_at, status")
      .eq("institution_id", institutionId)
      .eq("status", "paid")
      .eq("charge_id", chargeId)
      .order("paid_at", { ascending: false })
      .order("id", { ascending: false })
      .range(from, to));
  }

  async listConcepts(institutionId: number) {
    return readAllPages<Record<string, unknown>>((from, to) => db
      .from("payment_concepts")
      .select("id, name, description, base_amount, recurring, periodicity, catalog_currencies(iso_code)")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .order("name").order("id").range(from, to));
  }

  async findConcept(institutionId: number, id: number) {
    return expectSingle<Record<string, unknown>>(
      db.from("payment_concepts").select("id, name, base_amount, active").eq("institution_id", institutionId).eq("id", id).single(),
      "Concepto de cobro no encontrado.",
    );
  }

  async currentAcademicYearId(institutionId: number) {
    const { data, error } = await db
      .from("academic_years")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("is_current", true)
      .maybeSingle();
    assertNoDbError(error);
    return data == null ? null : Number(data.id);
  }

  /** Alumnos activos de la institución (para validar altas de cargos). */
  async activeStudentIds(institutionId: number, ids: number[]) {
    const rows: Record<string, unknown>[] = [];
    for (let i = 0; i < ids.length; i += 150) {
    rows.push(...await readAllPages<Record<string, unknown>>((from, to) => db
      .from("students")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .in("id", ids.slice(i, i + 150)).order("id").range(from, to)));
    }
    return rows.map(row => Number(row.id));
  }

  async activeStudentIdsOfGroup(institutionId: number, groupId: number) {
    const rows = await readAllPages<Record<string, unknown>>((from, to) => db
      .from("enrollments")
      .select("student_id, students!inner(active), academic_years!inner(is_current), catalog_enrollment_statuses!inner(code)")
      .eq("institution_id", institutionId)
      .eq("group_id", groupId)
      .eq("students.active", true).eq("academic_years.is_current", true)
      .eq("catalog_enrollment_statuses.code", "ACT").order("id").range(from, to));
    return [...new Set(rows.map(row => Number(row.student_id)))];
  }

  async insertCharges(rows: Record<string, unknown>[],key:string) {
    return transactionRpc<string[]>(db,"charges_create_batch",{p_rows:rows,p_key:key});
  }
}

export const paymentsRepository = new PaymentsRepository();

