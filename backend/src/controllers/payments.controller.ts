import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { paymentsService } from "../services/payments.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

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
