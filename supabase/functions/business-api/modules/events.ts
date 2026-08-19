import { AppContext, requireRole } from "../shared/auth.ts";
import { expectSingle } from "../shared/db.ts";
import { db } from "../shared/supabase.ts";
import { requiredDate, requiredString } from "../shared/validators.ts";

export async function createEvent(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  requireRole(ctx, ["teacher"]);
  const title = requiredString(payload.title, "Título", 150);
  const description = requiredString(payload.description, "Descripción", 2000);
  const date = requiredDate(payload.date, "Fecha");
  const audience = requiredString(payload.audience, "Audiencia", 50);
  const row = await expectSingle<Record<string, unknown>>(
    db
      .from("calendar_events")
      .insert({
        institution_id: ctx.institutionId,
        title,
        description,
        start_at: date.toISOString(),
        audience,
        type: "event",
        created_by: ctx.userId,
      })
      .select("id, title, description, start_at, audience")
      .single(),
    "No se pudo crear el evento.",
  );
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
