import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { gradesService } from "../services/grades.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function upsertScale(req: AppRequest, res: Response) {
  const data = await gradesService.upsertScale(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function setDefaultScale(req: AppRequest, res: Response) {
  const body = { ...asRecord(req.body), id: req.params.id ?? req.body?.id };
  const data = await gradesService.setDefaultScale(requireAppContext(req), body);
  return res.json({ ok: true, data });
}

export async function setGrade(req: AppRequest, res: Response) {
  const data = await gradesService.setGrade(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}
