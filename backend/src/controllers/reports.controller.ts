import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { reportsService } from "../services/reports.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function previewReportCard(req: AppRequest, res: Response) {
  const data = await reportsService.previewReportCard(requireAppContext(req), asRecord(req.query));
  return res.json({ ok: true, data });
}

export async function generateReportCard(req: AppRequest, res: Response) {
  const data = await reportsService.generateReportCard(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}

export async function getReportCard(req: AppRequest, res: Response) {
  const data = await reportsService.getReportCard(requireAppContext(req), req.params.id);
  return res.json({ ok: true, data });
}
