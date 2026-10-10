import type { AppContext } from "../../types/app-context";
import { assignmentsService } from "../assignments/assignments.service";
import { attendanceService } from "../attendance/attendance.service";
import { chatsService } from "../chats/chats.service";
import { eventsService } from "../events/events.service";
import { gradesService } from "../grades/grades.service";
import { notificationsService } from "../notifications/notifications.service";
import { paymentsService } from "../payments/payments.service";

export type BusinessApiHandler = (
  ctx: AppContext,
  payload: Record<string, unknown>,
) => Promise<unknown>;

export const businessApiHandlers: Record<string, BusinessApiHandler> = {
  "assignments.teacherClasses": (ctx) => assignmentsService.teacherClasses(ctx),
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


