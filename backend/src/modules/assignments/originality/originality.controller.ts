import type { Response } from 'express';
import type { AppRequest } from '../../../types/app-context';
import { requireAppContext } from '../../../middleware/auth.middleware';
import { originalityService } from './originality.service';
import { parseOriginalityAssignment, parseOriginalityQuery, parseOriginalityRetry, parseOriginalityTemplate } from './originality.schemas';
export async function originalityReport(req: AppRequest, res: Response) {
  const input = parseOriginalityQuery(req.params.submissionId, req.query);
  const data = await originalityService.report(requireAppContext(req), input.submissionId, input.evidence);
  res.setHeader('Cache-Control', 'private, no-store');
  return res.json({ ok: true, data });
}
export async function originalityRetry(req: AppRequest, res: Response) {
  const id = parseOriginalityRetry(req.params.submissionId, req.body);
  const data = await originalityService.report(requireAppContext(req), id, false, true);
  res.setHeader('Cache-Control', 'private, no-store');
  return res.json({ ok: true, data });
}
export async function originalitySummary(req: AppRequest, res: Response) {
  const data = await originalityService.summary(requireAppContext(req), parseOriginalityAssignment(req.params.id, req.query));
  res.setHeader('Cache-Control', 'private, no-store');
  return res.json({ ok: true, data });
}
export async function originalityTemplate(req: AppRequest, res: Response) {
  const data = await originalityService.template(requireAppContext(req), parseOriginalityAssignment(req.params.id, req.query));
  res.setHeader('Cache-Control', 'private, no-store');
  return res.json({ ok: true, data });
}
export async function originalitySaveTemplate(req: AppRequest, res: Response) {
  const input = parseOriginalityTemplate(req.params.id, req.body);
  const data = await originalityService.saveTemplate(requireAppContext(req), input.assignmentId, input.template);
  res.setHeader('Cache-Control', 'private, no-store');
  return res.json({ ok: true, data });
}
