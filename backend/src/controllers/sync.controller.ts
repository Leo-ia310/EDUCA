import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { syncService } from "../services/sync.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function listQueue(req: AppRequest, res: Response) {
  const data = await syncService.list(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function enqueue(req: AppRequest, res: Response) {
  const data = await syncService.enqueue(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function retry(req: AppRequest, res: Response) {
  const data = await syncService.retry(requireAppContext(req), req.params.id);
  return res.json({ ok: true, data });
}

export async function markFailed(req: AppRequest, res: Response) {
  const data = await syncService.markFailed(requireAppContext(req), req.params.id, asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function pullChanges(req: AppRequest, res: Response) {
  const data = await syncService.pull(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}
