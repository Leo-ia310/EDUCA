import type { Response } from "express";

import { requireAppContext } from "../../middleware/auth.middleware";
import {
  parseListFilesQuery,
  parsePrepareUploadBody,
  parseRegisterFileMetadataBody,
} from "./files.schemas";
import { filesService } from "./files.service";
import type { AppRequest } from "../../types/app-context";

export async function listFiles(req: AppRequest, res: Response) {
  const data = await filesService.list(
    requireAppContext(req),
    parseListFilesQuery(req.query),
  );
  return res.json({ ok: true, data });
}

export async function prepareUpload(req: AppRequest, res: Response) {
  const data = await filesService.prepareUpload(
    requireAppContext(req),
    parsePrepareUploadBody(req.body),
  );
  return res.json({ ok: true, data });
}

export async function registerMetadata(req: AppRequest, res: Response) {
  const data = await filesService.registerMetadata(
    requireAppContext(req),
    parseRegisterFileMetadataBody(req.body),
  );
  return res.status(201).json({ ok: true, data });
}
