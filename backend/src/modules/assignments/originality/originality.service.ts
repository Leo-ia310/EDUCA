import { OriginalityRepository } from './originality.repository';
import { assignmentsRepository } from '../assignments.repository';
import { permissionsService } from '../../../services/permissions.service';
import type { AppContext } from '../../../types/app-context';
export class OriginalityService {
  constructor(private readonly repository = new OriginalityRepository()) {}
  async report(ctx: AppContext, id: number, evidence = false, retry = false) {
    permissionsService.requireRole(ctx, ['teacher']);
    const submission = await assignmentsRepository.findSubmissionWithAssignment(id, ctx.institutionId);
    await permissionsService.assertTeacherCanUseAssignment(ctx, Number(submission.assignment_id), 'assignments.review');
    await permissionsService.assertTeacherCanUseAssignment(ctx, Number(submission.assignment_id), 'students.view');
    return this.repository.report(id, evidence, retry);
  }
}
export const originalityService = new OriginalityService();
