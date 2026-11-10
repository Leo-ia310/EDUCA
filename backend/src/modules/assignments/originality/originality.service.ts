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
  private async assignmentAccess(ctx: AppContext, assignmentId: number, permission: string) {
    permissionsService.requireRole(ctx, ['teacher']);
    await permissionsService.assertTeacherCanUseAssignment(ctx, assignmentId, permission);
    await permissionsService.assertTeacherCanUseAssignment(ctx, assignmentId, 'students.view');
  }
  async summary(ctx: AppContext, assignmentId: number) {
    await this.assignmentAccess(ctx, assignmentId, 'assignments.review');
    return this.repository.summary(assignmentId);
  }
  async template(ctx: AppContext, assignmentId: number) {
    await this.assignmentAccess(ctx, assignmentId, 'assignments.review');
    return this.repository.templateGet(assignmentId);
  }
  async saveTemplate(ctx: AppContext, assignmentId: number, template: string) {
    await this.assignmentAccess(ctx, assignmentId, 'assignments.create');
    return this.repository.templateSet(assignmentId, template);
  }
}
export const originalityService = new OriginalityService();
