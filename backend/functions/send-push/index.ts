// =============================================================================
// Educa360 — Edge Function `send-push`
//
// Envía una notificación por Web Push estándar (VAPID) a las suscripciones
// web de un usuario, guardadas en `devices.push_token` (JSON con
// {endpoint, keys:{p256dh, auth}} — ver `WebPushService` en el cliente
// Flutter). Educa360 NO usa Firebase/FCM.
//
// Invocación esperada (POST, JSON):
//   { "notificationId": 123 }
//
// Requiere estos secrets (ver README de esta carpeta — AÚN NO desplegado):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (opcional)
// `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase
// automáticamente en toda Edge Function — no hace falta configurarlos.
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:soporte@educa360.app";

if (VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY) {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
}

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    return new Response(
      JSON.stringify({ error: "VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY no configurados" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  let body: { notificationId?: number | string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "JSON inválido" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const notificationId = body.notificationId;
  if (!notificationId) {
    return new Response(JSON.stringify({ error: "Falta notificationId" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: notification, error: notifError } = await supabase
    .from("notifications")
    .select("id, user_id, title, message, data")
    .eq("id", notificationId)
    .single();

  if (notifError || !notification) {
    return new Response(JSON.stringify({ error: "Notificación no encontrada" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: devices, error: devicesError } = await supabase
    .from("devices")
    .select("id, push_token")
    .eq("user_id", notification.user_id)
    .eq("platform", "web")
    .eq("active", true);

  if (devicesError) {
    return new Response(JSON.stringify({ error: devicesError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const payload = JSON.stringify({
    title: notification.title ?? "Educa360",
    body: notification.message ?? "",
    deepLink: (notification.data as Record<string, unknown> | null)?.deepLink ?? "/",
  });

  const targets = devices ?? [];
  const results = await Promise.allSettled(
    targets.map(async (device: { id: number; push_token: string }) => {
      const subscription = JSON.parse(device.push_token);
      await webpush.sendNotification(subscription, payload);
    }),
  );

  if (targets.length > 0) {
    await supabase.from("notification_deliveries").insert(
      results.map((r, i) => ({
        notification_id: notification.id,
        destination: targets[i].id.toString(),
        status: r.status === "fulfilled" ? "sent" : "failed",
        provider: "web-push",
        error: r.status === "rejected" ? String((r as PromiseRejectedResult).reason) : null,
        sent_at: new Date().toISOString(),
      })),
    );
  }

  const sent = results.filter((r) => r.status === "fulfilled").length;
  return new Response(JSON.stringify({ sent, total: results.length }), {
    headers: { "Content-Type": "application/json" },
  });
});
