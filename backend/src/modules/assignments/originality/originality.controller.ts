import type { Response } from 'express';
import type { AppRequest } from '../../../types/app-context';
import { requireAppContext } from '../../../middleware/auth.middleware';
import { originalityService } from './originality.service';
import { parseOriginalityQuery, parseOriginalityRetry } from './originality.schemas';
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
