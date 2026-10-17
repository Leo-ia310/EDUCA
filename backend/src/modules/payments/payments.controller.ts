import type { Response } from "express";

import { requireAppContext } from "../../middleware/auth.middleware";
import { paymentsService } from "./payments.service";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";

export async function registerPayment(req: AppRequest, res: Response) {
  const data = await paymentsService.registerPayment(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function cancelCharge(req: AppRequest, res: Response) {
  const body = {
    ...asRecord(req.body),
    chargeId: req.params.chargeId ?? req.body?.chargeId,
  };
  const data = await paymentsService.cancelCharge(requireAppContext(req), body);
  return res.json({ ok: true, data });
}

export async function paymentsSummary(req: AppRequest, res: Response) {
  const data = await paymentsService.summary(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function myCharges(req: AppRequest, res: Response) {
  const data = await paymentsService.chargesOfStudent(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function listCharges(req: AppRequest, res: Response) {
  const data = await paymentsService.listCharges(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function getCharge(req: AppRequest, res: Response) {
  const data = await paymentsService.getCharge(requireAppContext(req), req.params.chargeId);
  return res.json({ ok: true, data });
}

export async function listConcepts(req: AppRequest, res: Response) {
  const data = await paymentsService.listConcepts(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function createCharges(req: AppRequest, res: Response) {
  const data = await paymentsService.createCharges(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function registerPaymentAsAdmin(req: AppRequest, res: Response) {
  const data = await paymentsService.registerPaymentAsAdmin(
    requireAppContext(req),
    req.params.chargeId,
    asRecord(req.body),
  );
  return res.status(201).json({ ok: true, data });
}
