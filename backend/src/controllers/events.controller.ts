import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { eventsService } from "../services/events.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function createEvent(req: AppRequest, res: Response) {
  const data = await eventsService.createEvent(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}
