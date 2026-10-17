import { randomUUID } from "node:crypto";

import { assertNoDbError } from "../../lib/db";
import { HttpError } from "../../lib/errors";
import {
  asList,
  optionalId,
  optionalString,
  requiredId,
  requiredNumber,
  requiredString,
} from "../../validators/common.validators";
import {
  paymentsRepository,
  PaymentsRepository,
} from "./payments.repository";
import type { AppContext } from "../../types/app-context";
import {
  permissionsService,
  PermissionsService,
} from "../../services/permissions.service";

export class PaymentsService {
  constructor(
    private readonly repository: PaymentsRepository = paymentsRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async registerPayment(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["parent"]);
    this.permissions.enforceAdminPermission(ctx, "payments.create", ["parent"]);
    return this.recordPayment(ctx, payload);
  }

  /** Pago registrado por la administración (p. ej. efectivo recibido en caja). */
  async registerPaymentAsAdmin(ctx: AppContext, chargeIdValue: unknown, payload: Record<string, unknown>) {
    this.requireAdminWith(ctx, "payments.create");
    return this.recordPayment(ctx, { ...payload, chargeId: chargeIdValue });
  }

  private async recordPayment(ctx: AppContext, payload: Record<string, unknown>) {
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
    const paid = await this.paidByCharge(chargeId, ctx.institutionId);
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
        payment: await this.hydratePayment(ctx.institutionId, Number(existing.id), {
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

    const newPaid = await this.paidByCharge(chargeId, ctx.institutionId);
    const newStatus = newPaid >= total - 0.009 ? "paid" : "partial";
    const { error } = await this.repository.updateChargeStatus(
      chargeId,
      ctx.institutionId,
      newStatus,
    );
    assertNoDbError(error);

    return {
      payment: await this.hydratePayment(ctx.institutionId, Number(inserted.id), {
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
    this.permissions.requireAdminPermission(ctx, "payments.cancel");
    const chargeId = requiredId(payload.chargeId, "Cargo");
    const { error } = await this.repository.cancelCharge(
      chargeId,
      ctx.institutionId,
    );
    assertNoDbError(error);
    return { ok: true };
  }

  // ---------- Administración (panel web) ----------

  private requireAdminWith(ctx: AppContext, code: string) {
    if (!this.permissions.isAdmin(ctx)) {
      throw new HttpError(403, "Solo administración puede gestionar pagos.", "forbidden");
    }
    this.permissions.requireAdminPermission(ctx, code);
  }

  /** Resumen de recaudación y mora (mismo cálculo que la app). */
  async summary(ctx: AppContext) {
    this.requireAdminWith(ctx, "payments.view");
    const now = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    const [charges, paidAll, paidMonth] = await Promise.all([
      this.repository.listCharges(ctx.institutionId, null),
      this.repository.paidPayments(ctx.institutionId),
      this.repository.paidPayments(ctx.institutionId, monthStart.toISOString()),
    ]);
    const paidBy = this.sumByCharge(paidAll);

    let currencyCode = "USD";
    let overdueAmount = 0;
    let overdueCount = 0;
    let pendingAmount = 0;
    let expectedThisMonth = 0;
    const byStatus: Record<string, number> = {};
    for (const c of charges as any[]) {
      const code = c.payment_concepts?.catalog_currencies?.iso_code;
      if (code) currencyCode = code;
      const status = this.effectiveStatus(c);
      byStatus[status] = (byStatus[status] ?? 0) + 1;
      const total = this.totalOf(c);
      const balance = Math.max(total - (paidBy.get(Number(c.id)) ?? 0), 0);
      if (status === "overdue") {
        overdueAmount += balance;
        overdueCount++;
      }
      if (status === "pending" || status === "partial") pendingAmount += balance;
      const due = c.due_at ? new Date(`${c.due_at}T00:00:00`) : null;
      if (due && due >= monthStart && due < nextMonth && status !== "cancelled") expectedThisMonth += total;
    }
    const collectedThisMonth = paidMonth.reduce((sum, p) => sum + Number(p.amount ?? 0), 0);
    return {
      currencyCode,
      collectedThisMonth: this.money(collectedThisMonth),
      expectedThisMonth: this.money(expectedThisMonth),
      overdueAmount: this.money(overdueAmount),
      overdueCount,
      pendingAmount: this.money(pendingAmount),
      chargesByStatus: byStatus,
    };
  }

  /** Cargos con alumno, pagado y saldo. Filtros: status (incluye overdue), studentId, groupId. */
  async listCharges(ctx: AppContext, query: Record<string, unknown>) {
    this.requireAdminWith(ctx, "payments.view");
    const status = optionalString(query.status, 20);
    const studentId = optionalId(query.studentId ?? query.student_id);
    const groupId = optionalId(query.groupId ?? query.group_id);

    let studentIds: number[] | null = studentId == null ? null : [studentId];
    if (groupId != null) {
      const inGroup = await this.repository.activeStudentIdsOfGroup(ctx.institutionId, groupId);
      studentIds = studentIds == null ? inGroup : inGroup.filter((id) => id === studentId);
    }
    const [rows, paidAll] = await Promise.all([
      this.repository.listCharges(ctx.institutionId, studentIds),
      this.repository.paidPayments(ctx.institutionId),
    ]);
    const paidBy = this.sumByCharge(paidAll);
    const charges = (rows as any[])
      .map((c) => this.chargeView(c, paidBy.get(Number(c.id)) ?? 0))
      .filter((c) => status == null || c.status === status);
    return { charges };
  }

  /** Cargos de un hijo (padre) o propios (alumno), con lo pagado y el saldo. Solo lectura. */
  async chargesOfStudent(ctx: AppContext, query: Record<string, unknown>) {
    const studentId = await this.permissions.normalizeStudentId(ctx, query.studentId ?? query.student_id, "estudiante");
    const [rows, paidAll] = await Promise.all([
      this.repository.listCharges(ctx.institutionId, [studentId]),
      this.repository.paidPayments(ctx.institutionId),
    ]);
    const paidBy = this.sumByCharge(paidAll);
    return { charges: (rows as any[]).map((c) => this.chargeView(c, paidBy.get(Number(c.id)) ?? 0)) };
  }

  async getCharge(ctx: AppContext, idValue: unknown) {
    this.requireAdminWith(ctx, "payments.view");
    const id = requiredId(idValue, "Cargo");
    const [row, paid] = await Promise.all([
      this.repository.findCharge(ctx.institutionId, id),
      this.repository.paidPayments(ctx.institutionId),
    ]);
    const mine = paid.filter((p) => Number(p.charge_id) === id);
    return {
      charge: this.chargeView(row as any, mine.reduce((sum, p) => sum + Number(p.amount ?? 0), 0)),
      payments: mine.map((p) => ({
        id: String(p.id),
        amount: Number(p.amount ?? 0),
        method: String(p.payment_method ?? "cash"),
        receiptNumber: String(p.receipt_number ?? ""),
        reference: p.reference ?? null,
        paidAt: p.paid_at ?? null,
      })),
    };
  }

  async listConcepts(ctx: AppContext) {
    this.requireAdminWith(ctx, "payments.view");
    const rows = await this.repository.listConcepts(ctx.institutionId);
    return {
      concepts: (rows as any[]).map((c) => ({
        id: String(c.id),
        name: String(c.name ?? ""),
        description: c.description ?? null,
        baseAmount: Number(c.base_amount ?? 0),
        recurring: c.recurring === true,
        currencyCode: String(c.catalog_currencies?.iso_code ?? "USD"),
      })),
    };
  }

  /** Crea el mismo cargo para varios alumnos (`studentIds`) o para todo un salón (`groupId`). */
  async createCharges(ctx: AppContext, payload: Record<string, unknown>) {
    this.requireAdminWith(ctx, "payments.create");
    const conceptId = requiredId(payload.conceptId ?? payload.concept_id, "Concepto");
    const concept = await this.repository.findConcept(ctx.institutionId, conceptId);
    if (concept.active === false) {
      throw new HttpError(400, "El concepto de cobro está inactivo.", "validation_error");
    }
    const amount = payload.amount == null || payload.amount === ""
      ? Number(concept.base_amount ?? 0)
      : requiredNumber(payload.amount, "Monto");
    const discount = payload.discount == null || payload.discount === "" ? 0 : requiredNumber(payload.discount, "Descuento");
    if (!(amount > 0)) throw new HttpError(400, "El monto debe ser mayor que cero.", "validation_error");
    if (discount < 0 || discount > amount) {
      throw new HttpError(400, "El descuento debe estar entre 0 y el monto.", "validation_error");
    }
    const dueAt = requiredString(payload.dueAt ?? payload.due_at, "Fecha de vencimiento", 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dueAt) || Number.isNaN(new Date(`${dueAt}T00:00:00`).getTime())) {
      throw new HttpError(400, "La fecha de vencimiento no es válida (AAAA-MM-DD).", "validation_error");
    }

    const requested = asList(payload.studentIds ?? payload.student_ids).map((v) => requiredId(v, "Estudiante"));
    const groupId = optionalId(payload.groupId ?? payload.group_id);
    const target = new Set<number>(requested);
    if (groupId != null) {
      for (const id of await this.repository.activeStudentIdsOfGroup(ctx.institutionId, groupId)) target.add(id);
    }
    if (target.size === 0) {
      throw new HttpError(400, "Elige al menos un alumno o un salón.", "validation_error");
    }
    const valid = await this.repository.activeStudentIds(ctx.institutionId, [...target]);
    if (valid.length !== target.size) {
      throw new HttpError(400, "Algún alumno no existe o está inactivo.", "validation_error");
    }

    const yearId = await this.repository.currentAcademicYearId(ctx.institutionId);
    const description = optionalString(payload.description, 150) ?? String(concept.name);
    const ids = await this.repository.insertCharges(
      valid.map((studentId) => ({
        institution_id: ctx.institutionId,
        student_id: studentId,
        concept_id: conceptId,
        academic_year_id: yearId,
        description,
        amount,
        discount,
        late_fee: 0,
        total_amount: this.money(amount - discount),
        due_at: dueAt,
        status: "pending",
      })),
    );
    return { created: ids.length, chargeIds: ids.map(String) };
  }

  // ---------- Cálculo ----------

  private sumByCharge(payments: Record<string, unknown>[]) {
    const map = new Map<number, number>();
    for (const p of payments) {
      const id = Number(p.charge_id);
      map.set(id, (map.get(id) ?? 0) + Number(p.amount ?? 0));
    }
    return map;
  }

  private totalOf(c: any) {
    return c.total_amount == null
      ? Number(c.amount ?? 0) - Number(c.discount ?? 0) + Number(c.late_fee ?? 0)
      : Number(c.total_amount);
  }

  /** `overdue` si vence antes de hoy y no está cerrado (pagado o anulado), aunque el estado guardado sea otro. */
  private effectiveStatus(c: any) {
    const stored = String(c.status ?? "pending");
    if (stored === "paid" || stored === "cancelled") return stored;
    const due = c.due_at ? new Date(`${c.due_at}T23:59:59`) : null;
    return due != null && due.getTime() < Date.now() ? "overdue" : stored;
  }

  private money(n: number) {
    return Math.round(n * 100) / 100;
  }

  private chargeView(c: any, paid: number) {
    const person = c.students?.persons;
    const total = this.totalOf(c);
    return {
      id: String(c.id),
      studentId: String(c.student_id),
      studentName: `${person?.first_name ?? ""} ${person?.last_name ?? ""}`.trim() || "Estudiante",
      conceptId: c.concept_id == null ? null : String(c.concept_id),
      conceptName: String(c.payment_concepts?.name ?? c.description ?? "Cargo"),
      description: String(c.description ?? c.payment_concepts?.name ?? ""),
      amount: Number(c.amount ?? 0),
      discount: Number(c.discount ?? 0),
      lateFee: Number(c.late_fee ?? 0),
      total: this.money(total),
      paid: this.money(paid),
      balance: this.money(Math.max(total - paid, 0)),
      dueAt: c.due_at ?? null,
      status: this.effectiveStatus(c),
      storedStatus: String(c.status ?? "pending"),
      currencyCode: String(c.payment_concepts?.catalog_currencies?.iso_code ?? "USD"),
    };
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

  private async paidByCharge(chargeId: number, institutionId: number) {
    const { data, error } = await this.repository.paidPaymentsByCharge(
      chargeId,
      institutionId,
    );
    if (error) throw new HttpError(400, error.message, "db_error");
    return (data ?? []).reduce(
      (sum: number, row: Record<string, unknown>) =>
        sum + Number(row.amount ?? 0),
      0,
    );
  }

  private async hydratePayment(
    institutionId: number,
    id: number,
    extras: Record<string, unknown> = {},
  ) {
    const row = await this.repository.findPaymentForHydration(id, institutionId);
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

