import type { AppContext } from "../types/app-context";
import { HttpError } from "../lib/errors";
import { assignmentsService } from "./assignments.service";
import { attendanceService } from "./attendance.service";
import { chatsService } from "./chats.service";
import { eventsService } from "./events.service";
import { gradesService } from "./grades.service";
import { notificationsService } from "./notifications.service";
import { paymentsService } from "./payments.service";

type Handler = (
  ctx: AppContext,
  payload: Record<string, unknown>,
) => Promise<unknown>;

export class BusinessApiService {
  private readonly handlers: Record<string, Handler> = {
    "assignments.teacherClasses": (ctx) =>
      assignmentsService.teacherClasses(ctx),
    "assignments.upsert": (ctx, payload) =>
      assignmentsService.upsertAssignment(ctx, payload),
    "assignments.delete": (ctx, payload) =>
      assignmentsService.deleteAssignment(ctx, payload),
    "assignments.publish": (ctx, payload) =>
      assignmentsService.publishAssignment(ctx, payload),
    "assignments.submit": (ctx, payload) =>
      assignmentsService.submitAssignment(ctx, payload),
    "assignments.gradeSubmission": (ctx, payload) =>
      assignmentsService.gradeSubmission(ctx, payload),
    "payments.register": (ctx, payload) =>
      paymentsService.registerPayment(ctx, payload),
    "payments.cancelCharge": (ctx, payload) =>
      paymentsService.cancelCharge(ctx, payload),
    "events.create": (ctx, payload) => eventsService.createEvent(ctx, payload),
    "attendance.upsertClassSession": (ctx, payload) =>
      attendanceService.upsertClassSession(ctx, payload),
    "attendance.upsertAttendance": (ctx, payload) =>
      attendanceService.upsertAttendance(ctx, payload),
    "grades.upsertScale": (ctx, payload) =>
      gradesService.upsertScale(ctx, payload),
    "grades.setDefaultScale": (ctx, payload) =>
      gradesService.setDefaultScale(ctx, payload),
    "grades.setGrade": (ctx, payload) => gradesService.setGrade(ctx, payload),
    "chat.sendMessage": (ctx, payload) => chatsService.sendMessage(ctx, payload),
    "chat.markAsRead": (ctx, payload) =>
      chatsService.markConversationAsRead(ctx, payload),
    "chat.ensureIndividual": (ctx, payload) =>
      chatsService.ensureIndividualConversation(ctx, payload),
    "notifications.saveWebPushDevice": (ctx, payload) =>
      notificationsService.saveWebPushDevice(ctx, payload),
  };

  async dispatch(
    ctx: AppContext,
    action: string,
    payload: Record<string, unknown>,
  ) {
    const handler = this.handlers[action];
    if (handler == null) {
      throw new HttpError(404, `Acción no soportada: ${action}`, "not_found");
    }
    return handler(ctx, payload);
  }
}

export const businessApiService = new BusinessApiService();
