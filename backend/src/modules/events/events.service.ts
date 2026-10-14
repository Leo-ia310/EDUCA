import type { AppContext } from "../../types/app-context";
import { requiredDate, requiredString } from "../../validators/common.validators";
import {
  eventsRepository,
  EventsRepository,
} from "./events.repository";
import {
  permissionsService,
  PermissionsService,
} from "../../services/permissions.service";
import { notificationsService } from "../notifications/notifications.service";

export class EventsService {
  constructor(
    private readonly repository: EventsRepository = eventsRepository,
    private readonly permissions: PermissionsService = permissionsService,
  ) {}

  async createEvent(ctx: AppContext, payload: Record<string, unknown>) {
    this.permissions.requireRole(ctx, ["teacher"]);
    const title = requiredString(payload.title, "Título", 150);
    const description = requiredString(
      payload.description,
      "Descripción",
      2000,
    );
    const date = requiredDate(payload.date, "Fecha");
    const audience = normalizeAudience(
      requiredString(payload.audience, "Audiencia", 50),
    );
    const row = await this.repository.insertEvent({
      institution_id: ctx.institutionId,
      title,
      description,
      start_at: date.toISOString(),
      audience,
      type: "announcement",
      created_by: ctx.userId,
    });
    const announcement = await this.repository.insertAnnouncement({
      institution_id: ctx.institutionId,
      title,
      content: description,
      kind: "general",
      audience,
      published: true,
      published_at: new Date().toISOString(),
      created_by: ctx.userId,
    });
    const notifications = await notificationsService.notifyAudience(
      ctx,
      audience,
      title,
      description,
      {
        module: "announcements",
        eventId: row.id,
        announcementId: announcement.id,
        date: date.toISOString(),
        deepLink: "/announcements",
      },
    );
    return {
      event: {
        id: String(row.id),
        title: String(row.title ?? ""),
        description: String(row.description ?? ""),
        date: String(row.start_at ?? date.toISOString()),
        audience: String(row.audience ?? ""),
      },
      announcement: {
        id: String(announcement.id),
        title: String(announcement.title ?? ""),
        content: String(announcement.content ?? ""),
        audience: String(announcement.audience ?? ""),
      },
      notifications,
    };
  }
}

export const eventsService = new EventsService();

function normalizeAudience(value: string) {
  const key = value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase();
  switch (key) {
    case "all":
    case "toda la institucion":
      return "all";
    case "parents":
    case "parent":
    case "padres":
    case "padres y tutores":
      return "parents";
    case "students":
    case "student":
    case "estudiantes":
      return "students";
    case "teachers":
    case "teacher":
    case "docentes":
      return "teachers";
    case "admins":
    case "staff":
    case "administracion":
      return "staff";
    default:
      return value;
  }
}

