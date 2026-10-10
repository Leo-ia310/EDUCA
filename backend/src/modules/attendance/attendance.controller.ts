import type { Response } from "express";

import { requireAppContext } from "../../middleware/auth.middleware";
import { attendanceService } from "./attendance.service";
import type { AppRequest } from "../../types/app-context";
import { asRecord } from "../../validators/common.validators";

export async function upsertClassSession(req: AppRequest, res: Response) {
  const data = await attendanceService.upsertClassSession(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function upsertAttendance(req: AppRequest, res: Response) {
  const data = await attendanceService.upsertAttendance(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

