import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { developerService } from "../services/developer.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function summary(req: AppRequest, res: Response) {
  const data = await developerService.summary(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function institutions(req: AppRequest, res: Response) {
  const data = await developerService.institutions(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function users(req: AppRequest, res: Response) {
  const data = await developerService.users(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function auditEvents(req: AppRequest, res: Response) {
  const data = await developerService.auditEvents(requireAppContext(req));
  return res.json({ ok: true, data });
}

export function list(resource: Parameters<typeof developerService.list>[1]) {
  return async (req: AppRequest, res: Response) => {
    const data = await developerService.list(
      requireAppContext(req),
      resource,
      asRecord(req.query),
    );
    return res.json({ ok: true, data });
  };
}

export function create(resource: Parameters<typeof developerService.create>[1]) {
  return async (req: AppRequest, res: Response) => {
    const data = await developerService.create(
      requireAppContext(req),
      resource,
      asRecord(req.body),
    );
    return res.status(201).json({ ok: true, data });
  };
}

export function update(resource: Parameters<typeof developerService.update>[1]) {
  return async (req: AppRequest, res: Response) => {
    const data = await developerService.update(
      requireAppContext(req),
      resource,
      req.params.id,
      asRecord(req.body),
    );
    return res.json({ ok: true, data });
  };
}

export function archive(resource: Parameters<typeof developerService.archive>[1]) {
  return async (req: AppRequest, res: Response) => {
    const data = await developerService.archive(
      requireAppContext(req),
      resource,
      req.params.id,
    );
    return res.json({ ok: true, data });
  };
}
