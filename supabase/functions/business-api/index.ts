import { dispatch } from "./modules/mod.ts";
import { loadContext } from "./shared/auth.ts";
import { corsHeaders, HttpError, json } from "./shared/http.ts";
import { asRecord, requiredString } from "./shared/validators.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: { message: "Method not allowed" } }, 405);
  }

  try {
    const body = asRecord(await req.json());
    const action = requiredString(body.action, "Acción", 100);
    const payload = asRecord(body.payload);
    const ctx = await loadContext(req);
    const data = await dispatch(ctx, action, payload);
    return json({ ok: true, data });
  } catch (error) {
    if (error instanceof HttpError) {
      return json({
        ok: false,
        error: { code: error.code, message: error.message },
      }, error.status);
    }
    console.error(error);
    return json({
      ok: false,
      error: { code: "internal_error", message: "Error interno del backend." },
    }, 500);
  }
});
