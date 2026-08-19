# Edge Function `send-push`

Envía Web Push (VAPID) a las suscripciones guardadas en `devices.push_token`
por `WebPushService` (cliente Flutter Web). Educa360 no usa Firebase/FCM.

## Estado

**Desplegada** (2026-08-18) en el proyecto `qwfkmijewogksfizdski`, con los
secrets `VAPID_PUBLIC_KEY`/`VAPID_PRIVATE_KEY`/`VAPID_SUBJECT` configurados
(par VAPID regenerado en esa fecha; `frontend/.env` actualizado con la nueva
`VAPID_PUBLIC_KEY` para que coincida).

## Para redesplegar tras cambios de código

El código fuente ya vive en la ruta estándar `supabase/functions/send-push`.
Para redesplegar:

```bash
supabase link --project-ref qwfkmijewogksfizdski   # si no está linkeado
supabase functions deploy send-push --use-api       # --use-api evita requerir Docker
```

Si cambian las claves VAPID (regenerar con `npx web-push generate-vapid-keys`),
actualiza también `VAPID_PUBLIC_KEY` en `frontend/.env`:

```bash
supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=mailto:tu-correo@dominio.com
```

`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase
automáticamente en toda Edge Function — no hace falta configurarlos.

## Invocación

```
POST /functions/v1/send-push
{ "notificationId": 123 }
```

Busca la fila en `notifications`, envía Web Push a los `devices` web activos
del usuario destino, y registra el resultado en `notification_deliveries`.

## Wiring pendiente: quién la llama

Hoy nada invoca esta función automáticamente. La forma recomendada:

**Database Webhook** (Supabase Studio → Database → Webhooks): trigger en
`INSERT` sobre `public.notifications` que haga `POST` a esta función con
`{ "notificationId": "{{ record.id }}" }`. Así, cualquier código que inserte
una notificación (hoy nada lo hace desde Supabase — `HiveNotificationsRepository`
es local; haría falta un repo de notificaciones real contra la tabla
`notifications`, que no forma parte de esta pasada) dispara el push
automáticamente sin que el cliente Flutter tenga que saber de la función.
