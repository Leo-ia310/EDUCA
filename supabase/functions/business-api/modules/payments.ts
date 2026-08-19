import {
  AppContext,
  currentParentId,
  isAdmin,
  normalizeStudentId,
  requireRole,
} from "../shared/auth.ts";
import { expectSingle } from "../shared/db.ts";
import { HttpError } from "../shared/http.ts";
import { db } from "../shared/supabase.ts";
import {
  optionalString,
  requiredId,
  requiredNumber,
  requiredString,
} from "../shared/validators.ts";

function methodFromPayload(value: unknown) {
  const method = requiredString(value, "Método de pago", 40);
  if (!["card", "transfer", "cash", "wallet"].includes(method)) {
    throw new HttpError(400, "Método de pago inválido.", "validation_error");
  }
  return method;
}

async function paidByCharge(chargeId: number) {
  const { data, error } = await db
    .from("payments")
    .select("amount")
    .eq("charge_id", chargeId)
    .eq("status", "paid");
  if (error) throw new HttpError(400, error.message, "db_error");
  return (data ?? []).reduce(
    (sum, row) => sum + Number((row as Record<string, unknown>).amount ?? 0),
    0,
  );
}

async function hydratePayment(
  id: number,
  extras: Record<string, unknown> = {},
) {
  const row = await expectSingle<Record<string, unknown>>(
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
  const person = ((row.students as Record<string, unknown> | null)?.persons ??
    null) as Record<string, unknown> | null;
  const charge = row.charges as Record<string, unknown> | null;
  const conceptName =
    (charge?.payment_concepts as Record<string, unknown> | null)?.name;
  return {
    id: String(row.id),
    uuid: String(row.uuid),
    chargeId: row.charge_id == null ? "" : String(row.charge_id),
    chargeConcept: String(conceptName ?? charge?.description ?? "Pago"),
    studentName:
      `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim() ||
      "Estudiante",
    method: String(row.payment_method ?? "cash"),
    amount: Number(row.amount ?? 0),
    currencyCode: String(
      (row.catalog_currencies as Record<string, unknown> | null)?.iso_code ??
        "USD",
    ),
    status: String(row.status ?? "pending"),
    paidAt: String(row.paid_at ?? new Date().toISOString()),
    receiptNumber: String(row.receipt_number ?? ""),
    reference: row.reference ?? null,
    ...extras,
  };
}

export async function registerPayment(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  requireRole(ctx, ["parent"]);
  const chargeId = requiredId(payload.chargeId, "Cargo");
  const amount = requiredNumber(payload.amount, "Monto");
  if (amount <= 0) {
    throw new HttpError(
      400,
      "El monto debe ser mayor que cero.",
      "validation_error",
    );
  }

  const charge = await expectSingle<Record<string, unknown>>(
    db
      .from("charges")
      .select(
        "id, student_id, amount, discount, late_fee, total_amount, status, payment_concepts(currency_id)",
      )
      .eq("id", chargeId)
      .eq("institution_id", ctx.institutionId)
      .single(),
    "Cargo no encontrado.",
  );
  const studentId = Number(charge.student_id);
  if (!isAdmin(ctx)) {
    await normalizeStudentId(ctx, studentId, "estudiante");
  }
  if (["paid", "cancelled"].includes(String(charge.status))) {
    throw new HttpError(400, "Este cargo ya está cerrado.", "validation_error");
  }

  const total = charge.total_amount == null
    ? Number(charge.amount ?? 0) - Number(charge.discount ?? 0) +
      Number(charge.late_fee ?? 0)
    : Number(charge.total_amount);
  const paid = await paidByCharge(chargeId);
  const pending = Math.max(total - paid, 0);
  if (amount > pending + 0.009) {
    throw new HttpError(
      400,
      "El monto excede el saldo pendiente.",
      "validation_error",
    );
  }

  const parentId = ctx.roles.has("parent") ? await currentParentId(ctx) : null;
  const currencyId =
    (charge.payment_concepts as Record<string, unknown> | null)?.currency_id ??
      null;
  const inserted = await expectSingle<Record<string, unknown>>(
    db
      .from("payments")
      .insert({
        uuid: crypto.randomUUID(),
        institution_id: ctx.institutionId,
        charge_id: chargeId,
        student_id: studentId,
        parent_id: parentId,
        payment_method: methodFromPayload(payload.method),
        amount,
        currency_id: currencyId,
        reference: optionalString(payload.reference, 150),
        receipt_number: `RC-${Date.now()}`,
        status: "paid",
        paid_at: new Date().toISOString(),
        recorded_by: ctx.userId,
      })
      .select("id")
      .single(),
    "No se pudo registrar el pago.",
  );

  const newPaid = await paidByCharge(chargeId);
  const newStatus = newPaid >= total - 0.009 ? "paid" : "partial";
  const { error } = await db.from("charges").update({ status: newStatus }).eq(
    "id",
    chargeId,
  );
  if (error) throw new HttpError(400, error.message, "db_error");

  return {
    payment: await hydratePayment(Number(inserted.id), {
      payerName: optionalString(payload.payerName, 150),
      gatewayName: optionalString(payload.gatewayName, 100),
    }),
  };
}

export async function cancelCharge(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  if (!isAdmin(ctx)) {
    throw new HttpError(
      403,
      "Solo administración puede anular cargos.",
      "forbidden",
    );
  }
  const chargeId = requiredId(payload.chargeId, "Cargo");
  const { error } = await db
    .from("charges")
    .update({ status: "cancelled" })
    .eq("id", chargeId)
    .eq("institution_id", ctx.institutionId);
  if (error) throw new HttpError(400, error.message, "db_error");
  return { ok: true };
}
