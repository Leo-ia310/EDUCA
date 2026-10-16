import { assertNoDbError, expectSingle } from "../../lib/db";
import { supabaseAdmin } from "../../lib/supabase";

const db = supabaseAdmin as any;

export class PaymentsRepository {
  async paidPaymentsByCharge(chargeId: number, institutionId: number) {
    return db
      .from("payments")
      .select("amount")
      .eq("charge_id", chargeId)
      .eq("institution_id", institutionId)
      .eq("status", "paid");
  }

  async findPaymentForHydration(id: number, institutionId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("payments")
        .select(
          "id, uuid, charge_id, student_id, payment_method, amount, reference, receipt_number, status, paid_at, " +
            "catalog_currencies(iso_code), charges(description, payment_concepts(name)), students(persons(first_name, last_name))",
        )
        .eq("id", id)
        .eq("institution_id", institutionId)
        .single(),
      "Pago no encontrado.",
    );
  }

  async findPaymentByUuid(uuid: string, institutionId: number) {
    const { data } = await db
      .from("payments")
      .select("id")
      .eq("uuid", uuid)
      .eq("institution_id", institutionId)
      .maybeSingle();
    return data == null ? null : data as Record<string, unknown>;
  }

  async findChargeForPayment(chargeId: number, institutionId: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("charges")
        .select(
          "id, student_id, amount, discount, late_fee, total_amount, status, payment_concepts(currency_id)",
        )
        .eq("id", chargeId)
        .eq("institution_id", institutionId)
        .single(),
      "Cargo no encontrado.",
    );
  }

  async insertPayment(payload: Record<string, unknown>) {
    return expectSingle<Record<string, unknown>>(
      db.from("payments").insert(payload).select("id").single(),
      "No se pudo registrar el pago.",
    );
  }

  async updateChargeStatus(
    chargeId: number,
    institutionId: number,
    status: string,
  ) {
    return db
      .from("charges")
      .update({ status })
      .eq("id", chargeId)
      .eq("institution_id", institutionId);
  }

  async cancelCharge(chargeId: number, institutionId: number) {
    return db
      .from("charges")
      .update({ status: "cancelled" })
      .eq("id", chargeId)
      .eq("institution_id", institutionId);
  }

  // ---------- Administración (panel web) ----------

  private readonly chargeSelect =
    "id, student_id, concept_id, description, amount, discount, late_fee, total_amount, due_at, status, created_at, students(persons(first_name, last_name)), payment_concepts(name, catalog_currencies(iso_code))";

  async listCharges(institutionId: number, studentIds: number[] | null) {
    if (studentIds != null && studentIds.length === 0) return [] as Record<string, unknown>[];
    let query = db
      .from("charges")
      .select(this.chargeSelect)
      .eq("institution_id", institutionId)
      .order("due_at", { ascending: false })
      .order("id", { ascending: false });
    if (studentIds != null) query = query.in("student_id", studentIds);
    const { data, error } = await query;
    assertNoDbError(error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async findCharge(institutionId: number, id: number) {
    return expectSingle<Record<string, unknown>>(
      db.from("charges").select(this.chargeSelect).eq("institution_id", institutionId).eq("id", id).single(),
      "Cargo no encontrado.",
    );
  }

  /** Pagos cobrados (status paid) de la institución; si se indica, desde una fecha. */
  async paidPayments(institutionId: number, sinceIso?: string) {
    let query = db
      .from("payments")
      .select("id, charge_id, amount, payment_method, receipt_number, reference, paid_at, status")
      .eq("institution_id", institutionId)
      .eq("status", "paid")
      .order("paid_at", { ascending: false });
    if (sinceIso) query = query.gte("paid_at", sinceIso);
    const { data, error } = await query;
    assertNoDbError(error);
    return (data ?? []) as Record<string, unknown>[];
  }

  async listConcepts(institutionId: number) {
    const { data, error } = await db
      .from("payment_concepts")
      .select("id, name, description, base_amount, recurring, periodicity, catalog_currencies(iso_code)")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .order("name");
    assertNoDbError(error);
    return (data ?? []) as Record<string, unknown>[];
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
    if (ids.length === 0) return [] as number[];
    const { data, error } = await db
      .from("students")
      .select("id")
      .eq("institution_id", institutionId)
      .eq("active", true)
      .in("id", ids);
    assertNoDbError(error);
    return ((data ?? []) as Record<string, unknown>[]).map((r) => Number(r.id));
  }

  async activeStudentIdsOfGroup(institutionId: number, groupId: number) {
    const { data, error } = await db
      .from("enrollments")
      .select("student_id, students!inner(active)")
      .eq("institution_id", institutionId)
      .eq("group_id", groupId)
      .eq("students.active", true);
    assertNoDbError(error);
    return ((data ?? []) as Record<string, unknown>[]).map((r) => Number(r.student_id));
  }

  async insertCharges(rows: Record<string, unknown>[]) {
    const { data, error } = await db.from("charges").insert(rows).select("id");
    assertNoDbError(error);
    return ((data ?? []) as Record<string, unknown>[]).map((r) => Number(r.id));
  }
}

export const paymentsRepository = new PaymentsRepository();

