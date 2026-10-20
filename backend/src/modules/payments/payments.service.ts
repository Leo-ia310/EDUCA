import { randomUUID } from "node:crypto";
import { effectiveChargeStatus } from "./payment-status";

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

    if (!Number.isFinite(amount) || Math.abs(amount * 100 - Math.round(amount * 100)) > 1e-7) {
      throw new HttpError(400, "El monto debe tener como máximo dos decimales.", "validation_error");
    }
    const payment = await this.repository.registerChargePayment(
      chargeId,
      amount,
      this.methodFromPayload(payload.method),
      optionalString(payload.reference, 150),
      this.idempotencyKey(payload.idempotencyKey) ?? randomUUID(),
    );

    return {
      payment: {
        ...payment,
        payerName: optionalString(payload.payerName, 150),
        gatewayName: optionalString(payload.gatewayName, 100),
      },
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
    const { error } = await this.repository.cancelCharge(chargeId);
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
    return this.repository.collectionSummary();
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
    const rows = await this.repository.listCharges(ctx.institutionId, studentIds);
    const paidBy = await this.repository.paidTotals(rows.map(c => Number(c.id)));
    const charges = (rows as any[])
      .map((c) => this.chargeView(c, paidBy.get(Number(c.id)) ?? 0))
      .filter((c) => status == null || c.status === status);
    return { charges };
  }

  /** Cargos de un hijo (padre) o propios (alumno), con lo pagado y el saldo. Solo lectura. */
  async chargesOfStudent(ctx: AppContext, query: Record<string, unknown>) {
    const studentId = await this.permissions.normalizeStudentId(ctx, query.studentId ?? query.student_id, "estudiante");
    const rows = await this.repository.listCharges(ctx.institutionId, [studentId]);
    const paidBy = await this.repository.paidTotals(rows.map(c => Number(c.id)));
    return { charges: (rows as any[]).map((c) => this.chargeView(c, paidBy.get(Number(c.id)) ?? 0)) };
  }

  async getCharge(ctx: AppContext, idValue: unknown) {
    this.requireAdminWith(ctx, "payments.view");
    const id = requiredId(idValue, "Cargo");
    const [row, paid, totals] = await Promise.all([
      this.repository.findCharge(ctx.institutionId, id),
      this.repository.paidPayments(ctx.institutionId, id),
      this.repository.paidTotals([id]),
    ]);
    return {
      charge: this.chargeView(row as any, totals.get(id) ?? 0),
      payments: paid.map((p) => ({
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
    const requestKey=payload.requestId??randomUUID();
    if(typeof requestKey!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(requestKey))throw new HttpError(400,"Clave de operación inválida.","validation_error");
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
      })),requestKey,
    );
    return { created: ids.length, chargeIds: ids.map(String) };
  }

  // ---------- Cálculo ----------

  private totalOf(c: any) {
    return c.total_amount == null
      ? Number(c.amount ?? 0) - Number(c.discount ?? 0) + Number(c.late_fee ?? 0)
      : Number(c.total_amount);
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
      status: effectiveChargeStatus(c),
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
}

export const paymentsService = new PaymentsService();

