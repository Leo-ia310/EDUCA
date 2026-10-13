import type { Response } from "express";

import { requireAppContext } from "../../middleware/auth.middleware";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";
import { schedulesService } from "./schedules.service";

export async function listSchedules(req: AppRequest, res: Response) {
  const data = await schedulesService.list(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function createSchedule(req: AppRequest, res: Response) {
  const data = await schedulesService.create(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function updateSchedule(req: AppRequest, res: Response) {
  const data = await schedulesService.update(
    requireAppContext(req),
    req.params.id,
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function deleteSchedule(req: AppRequest, res: Response) {
  const data = await schedulesService.remove(
    requireAppContext(req),
    req.params.id,
    asRecord(req.query),
  );
  return res.json({ ok: true, data });
}

export async function mySchedules(req: AppRequest, res: Response) {
  const data = await schedulesService.mine(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}
