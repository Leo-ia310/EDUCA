import type { Response } from "express";

import { businessApiService } from "../services/business-api.service";
import { requireAppContext } from "../middleware/auth.middleware";
import type { AppRequest } from "../types/app-context";
import { asRecord, requiredString } from "../validators/common.validators";

export async function dispatchAction(req: AppRequest, res: Response) {
  const body = asRecord(req.body);
  const action = requiredString(body.action, "Acción", 100);
  const payload = asRecord(body.payload);
  const data = await businessApiService.dispatch(
    requireAppContext(req),
    action,
    payload,
  );
  return res.json({ ok: true, data });
}
