import { expectSingle } from "../lib/db";
import { supabaseAdmin } from "../lib/supabase";

const db = supabaseAdmin as any;

export class PaymentsRepository {
  async paidPaymentsByCharge(chargeId: number) {
    return db
      .from("payments")
      .select("amount")
      .eq("charge_id", chargeId)
      .eq("status", "paid");
  }

  async findPaymentForHydration(id: number) {
    return expectSingle<Record<string, unknown>>(
      db
        .from("payments")
        .select(
          "id, uuid, charge_id, student_id, payment_method, amount, reference, receipt_number, status, paid_at, " +
            "catalog_currencies(iso_code), charges(description, payment_concepts(name)), students(persons(first_name, last_name))",
        )
        .eq("id", id)
        .single(),
      "Pago no encontrado.",
    );
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

  async updateChargeStatus(chargeId: number, status: string) {
    return db.from("charges").update({ status }).eq("id", chargeId);
  }

  async cancelCharge(chargeId: number, institutionId: number) {
    return db
      .from("charges")
      .update({ status: "cancelled" })
      .eq("id", chargeId)
      .eq("institution_id", institutionId);
  }
}

export const paymentsRepository = new PaymentsRepository();
