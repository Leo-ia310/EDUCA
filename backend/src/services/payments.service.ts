import { randomUUID } from "node:crypto";

import { assertNoDbError } from "../lib/db";
import { HttpError } from "../lib/errors";
import {
  optionalString,
  requiredId,
  requiredNumber,
  requiredString,
} from "../validators/common.validators";
import {
  paymentsRepository,
  PaymentsRepository,
} from "../repositories/payments.repository";
import type { AppContext } from "../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "./permissions.service";

export class PaymentsService {
  constructor(
    private readonly repository: PaymentsRepository = paymentsRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async registerPayment(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["parent"]);
    const chargeId = requiredId(payload.chargeId, "Cargo");
    const amount = requiredNumber(payload.amount, "Monto");
    if (amount <= 0) {
      throw new HttpError(
        400,
        "El monto debe ser mayor que cero.",
        "validation_error",
      );
    }

    const charge = await this.repository.findChargeForPayment(
      chargeId,
      ctx.institutionId,
    );
    const studentId = Number(charge.student_id);
    if (!this.permissions.isAdmin(ctx)) {
      await this.permissions.normalizeStudentId(ctx, studentId, "estudiante");
    }
    if (["paid", "cancelled"].includes(String(charge.status))) {
      throw new HttpError(400, "Este cargo ya está cerrado.", "validation_error");
    }

    const total = charge.total_amount == null
      ? Number(charge.amount ?? 0) - Number(charge.discount ?? 0) +
        Number(charge.late_fee ?? 0)
      : Number(charge.total_amount);
    const paid = await this.paidByCharge(chargeId);
    const pending = Math.max(total - paid, 0);
    if (amount > pending + 0.009) {
      throw new HttpError(
        400,
        "El monto excede el saldo pendiente.",
        "validation_error",
      );
    }

    const parentId = ctx.roles.has("parent")
      ? await this.permissions.currentParentId(ctx)
      : null;
    const paymentUuid = this.idempotencyKey(payload.idempotencyKey) ??
      randomUUID();
    const existing = await this.repository.findPaymentByUuid(
      paymentUuid,
      ctx.institutionId,
    );
    if (existing != null) {
      return {
        payment: await this.hydratePayment(Number(existing.id), {
          payerName: optionalString(payload.payerName, 150),
          gatewayName: optionalString(payload.gatewayName, 100),
        }),
      };
    }

    const currencyId =
      (charge.payment_concepts as Record<string, unknown> | null)
        ?.currency_id ?? null;
    const inserted = await this.repository.insertPayment({
      uuid: paymentUuid,
      institution_id: ctx.institutionId,
      charge_id: chargeId,
      student_id: studentId,
      parent_id: parentId,
      payment_method: this.methodFromPayload(payload.method),
      amount,
      currency_id: currencyId,
      reference: optionalString(payload.reference, 150),
      receipt_number: `RC-${Date.now()}`,
      status: "paid",
      paid_at: new Date().toISOString(),
      recorded_by: ctx.userId,
    });

    const newPaid = await this.paidByCharge(chargeId);
    const newStatus = newPaid >= total - 0.009 ? "paid" : "partial";
    const { error } = await this.repository.updateChargeStatus(
      chargeId,
      newStatus,
    );
    assertNoDbError(error);

    return {
      payment: await this.hydratePayment(Number(inserted.id), {
        payerName: optionalString(payload.payerName, 150),
        gatewayName: optionalString(payload.gatewayName, 100),
      }),
    };
  }

  async cancelCharge(ctx: AppContext, payload: Record<string, unknown>) {
    if (!this.permissions.isAdmin(ctx)) {
      throw new HttpError(
        403,
        "Solo administración puede anular cargos.",
        "forbidden",
      );
    }
    const chargeId = requiredId(payload.chargeId, "Cargo");
    const { error } = await this.repository.cancelCharge(
      chargeId,
      ctx.institutionId,
    );
    assertNoDbError(error);
    return { ok: true };
  }

  private methodFromPayload(value: unknown) {
    const method = requiredString(value, "Método de pago", 40);
    if (!["card", "transfer", "cash", "wallet"].includes(method)) {
      throw new HttpError(400, "Método de pago inválido.", "validation_error");
    }
    return method;
  }

  private idempotencyKey(value: unknown) {
    const key = optionalString(value, 80);
    if (key == null) return null;
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(key)
    ) {
      throw new HttpError(
        400,
        "La llave de idempotencia debe ser un UUID válido.",
        "validation_error",
      );
    }
    return key;
  }

  private async paidByCharge(chargeId: number) {
    const { data, error } = await this.repository.paidPaymentsByCharge(chargeId);
    if (error) throw new HttpError(400, error.message, "db_error");
    return (data ?? []).reduce(
      (sum: number, row: Record<string, unknown>) =>
        sum + Number(row.amount ?? 0),
      0,
    );
  }

  private async hydratePayment(
    id: number,
    extras: Record<string, unknown> = {},
  ) {
    const row = await this.repository.findPaymentForHydration(id);
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
}

export const paymentsService = new PaymentsService();
