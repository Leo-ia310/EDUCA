import type { Response } from "express";

import { filesService } from "../services/files.service";
import { requireAppContext } from "../middleware/auth.middleware";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function listFiles(req: AppRequest, res: Response) {
  const data = await filesService.list(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function prepareUpload(req: AppRequest, res: Response) {
  const data = await filesService.prepareUpload(requireAppContext(req), asRecord(req.body));
  return res.json({ ok: true, data });
}

export async function registerMetadata(req: AppRequest, res: Response) {
  const data = await filesService.registerMetadata(requireAppContext(req), asRecord(req.body));
  return res.status(201).json({ ok: true, data });
}
