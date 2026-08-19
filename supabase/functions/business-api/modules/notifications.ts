import { AppContext } from "../shared/auth.ts";
import { expectSingle } from "../shared/db.ts";
import { HttpError } from "../shared/http.ts";
import { db } from "../shared/supabase.ts";
import { requiredString } from "../shared/validators.ts";

export async function saveWebPushDevice(
  ctx: AppContext,
  payload: Record<string, unknown>,
) {
  const endpoint = requiredString(payload.endpoint, "Endpoint push", 2000);
  const pushToken = requiredString(payload.pushToken, "Token push", 5000);
  const { data: existing } = await db
    .from("devices")
    .select("id")
    .eq("user_id", ctx.userId)
    .eq("device_uuid", endpoint)
    .maybeSingle();
  if (existing == null) {
    await expectSingle(
      db
        .from("devices")
        .insert({
          user_id: ctx.userId,
          device_uuid: endpoint,
          platform: "web",
          push_token: pushToken,
          active: true,
          last_synced_at: new Date().toISOString(),
        })
        .select("id")
        .single(),
      "No se pudo guardar el dispositivo.",
    );
  } else {
    const { error } = await db
      .from("devices")
      .update({
        push_token: pushToken,
        active: true,
        last_synced_at: new Date().toISOString(),
      })
      .eq("id", existing.id);
    if (error) throw new HttpError(400, error.message, "db_error");
  }
  return { ok: true };
}
