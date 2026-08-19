import type { Response } from "express";

import { requireAppContext } from "../middleware/auth.middleware";
import { assignmentsService } from "../services/assignments.service";
import type { AppRequest } from "../types/app-context";
import { asRecord } from "../validators/common.validators";

export async function teacherClasses(req: AppRequest, res: Response) {
  const data = await assignmentsService.teacherClasses(requireAppContext(req));
  return res.json({ ok: true, data });
}

export async function upsertAssignment(req: AppRequest, res: Response) {
  const data = await assignmentsService.upsertAssignment(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function deleteAssignment(req: AppRequest, res: Response) {
  const body = { ...asRecord(req.body), id: req.params.id ?? req.body?.id };
  const data = await assignmentsService.deleteAssignment(
    requireAppContext(req),
    body,
  );
  return res.json({ ok: true, data });
}

export async function publishAssignment(req: AppRequest, res: Response) {
  const body = { ...asRecord(req.body), id: req.params.id ?? req.body?.id };
  const data = await assignmentsService.publishAssignment(
    requireAppContext(req),
    body,
  );
  return res.json({ ok: true, data });
}

export async function submitAssignment(req: AppRequest, res: Response) {
  const data = await assignmentsService.submitAssignment(
    requireAppContext(req),
    asRecord(req.body),
  );
  return res.json({ ok: true, data });
}

export async function gradeSubmission(req: AppRequest, res: Response) {
  const body = {
    ...asRecord(req.body),
    submissionId: req.params.submissionId ?? req.body?.submissionId,
  };
  const data = await assignmentsService.gradeSubmission(
    requireAppContext(req),
    body,
  );
  return res.json({ ok: true, data });
}
