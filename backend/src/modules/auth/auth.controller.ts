import type { Response } from "express";

import { authFlowService } from "./auth-flow.service";
import type { AppRequest } from "../../types/app-context";
import { requireAppContext } from "../../middleware/auth.middleware";
import { asRecord } from "../../validators/common.validators";

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

export async function resetPassword(req: AppRequest, res: Response) {
  return res.json({ ok: true, data: await authFlowService.resetPassword(asRecord(req.body)) });
}

export async function verifyTwoFactorLogin(req: AppRequest, res: Response) {
  const data = await authFlowService.verifyTwoFactorLogin(asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function twoFactorStatus(req: AppRequest, res: Response) {
  const ctx = requireAppContext(req);
  const data = await authFlowService.twoFactorStatus(ctx.userId);
  return res.json({ ok: true, data });
}

export async function setupTwoFactor(req: AppRequest, res: Response) {
  const ctx = requireAppContext(req);
  const data = await authFlowService.setupTwoFactor(ctx.userId, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function enableTwoFactor(req: AppRequest, res: Response) {
  const ctx = requireAppContext(req);
  const data = await authFlowService.enableTwoFactor(ctx.userId, asRecord(req.body), ctx.sessionId);
  return res.json({ ok: true, data });
}

export async function disableTwoFactor(req: AppRequest, res: Response) {
  const ctx = requireAppContext(req);
  const data = await authFlowService.disableTwoFactor(ctx.userId, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function logout(req: AppRequest, res: Response) {
  const token = (req.header("Authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  const data = await authFlowService.logout(token);
  return res.json({ ok: true, data });
}

export async function changePassword(req: AppRequest, res: Response) {
  const ctx = requireAppContext(req);
  const data = await authFlowService.changePassword(ctx.userId, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function sendTwoFactorEmailCode(req: AppRequest,res: Response) {
 const data=await authFlowService.sendTwoFactorEmailCode(requireAppContext(req).userId,asRecord(req.body));
 return res.json({ok:true,data});
}
export async function resendTwoFactorLogin(req: AppRequest,res: Response) {
 const data=await authFlowService.resendTwoFactorLogin(asRecord(req.body));
 return res.json({ok:true,data});
}
