import type { Response } from "express";

import { authFlowService } from "../services/auth-flow.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function login(req: AppRequest, res: Response) {
  const data = await authFlowService.login(asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function refresh(req: AppRequest, res: Response) {
  const data = await authFlowService.refresh(asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function recoverPassword(req: AppRequest, res: Response) {
  const data = await authFlowService.recoverPassword(asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function logout(req: AppRequest, res: Response) {
  const token = (req.header("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  const data = await authFlowService.logout(token);
  return res.json({ ok: true, data });
}
