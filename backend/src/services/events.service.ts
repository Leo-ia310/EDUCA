import type { AppContext } from "../types/app-context";
import { requiredDate, requiredString } from "../validators/common.validators";
import {
  eventsRepository,
  EventsRepository,
} from "../repositories/events.repository";
import {
  permissionsService,
  PermissionsService,
} from "./permissions.service";

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
    const audience = requiredString(payload.audience, "Audiencia", 50);
    const row = await this.repository.insertEvent({
      institution_id: ctx.institutionId,
      title,
      description,
      start_at: date.toISOString(),
      audience,
      type: "event",
      created_by: ctx.userId,
    });
    return {
      event: {
        id: String(row.id),
        title: String(row.title ?? ""),
        description: String(row.description ?? ""),
        date: String(row.start_at ?? date.toISOString()),
        audience: String(row.audience ?? ""),
      },
    };
  }
}

export const eventsService = new EventsService();
