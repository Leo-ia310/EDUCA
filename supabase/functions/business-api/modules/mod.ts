import { AppContext } from "../shared/auth.ts";
import { HttpError } from "../shared/http.ts";
import {
  deleteAssignment,
  gradeSubmission,
  publishAssignment,
  submitAssignment,
  teacherClasses,
  upsertAssignment,
} from "./assignments.ts";
import { upsertAttendance, upsertClassSession } from "./attendance.ts";
import {
  ensureIndividualConversation,
  markConversationAsRead,
  sendMessage,
} from "./chat.ts";
import { createEvent } from "./events.ts";
import { setDefaultScale, setGrade, upsertScale } from "./grades.ts";
import { saveWebPushDevice } from "./notifications.ts";
import { cancelCharge, registerPayment } from "./payments.ts";

type Handler = (
  ctx: AppContext,
  payload: Record<string, unknown>,
) => Promise<unknown>;

const handlers: Record<string, Handler> = {
  "assignments.teacherClasses": (ctx) => teacherClasses(ctx),
  "assignments.upsert": upsertAssignment,
  "assignments.delete": deleteAssignment,
  "assignments.publish": publishAssignment,
  "assignments.submit": submitAssignment,
  "assignments.gradeSubmission": gradeSubmission,
  "payments.register": registerPayment,
  "payments.cancelCharge": cancelCharge,
  "events.create": createEvent,
  "attendance.upsertClassSession": upsertClassSession,
  "attendance.upsertAttendance": upsertAttendance,
  "grades.upsertScale": upsertScale,
  "grades.setDefaultScale": setDefaultScale,
  "grades.setGrade": setGrade,
  "chat.sendMessage": sendMessage,
  "chat.markAsRead": markConversationAsRead,
  "chat.ensureIndividual": ensureIndividualConversation,
  "notifications.saveWebPushDevice": saveWebPushDevice,
};

export async function dispatch(
  ctx: AppContext,
  action: string,
  payload: Record<string, unknown>,
) {
  const handler = handlers[action];
  if (handler == null) {
    throw new HttpError(404, `Acción no soportada: ${action}`, "not_found");
  }
  return await handler(ctx, payload);
}
