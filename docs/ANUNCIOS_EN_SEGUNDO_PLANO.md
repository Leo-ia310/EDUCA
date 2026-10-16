# Publicación de anuncios

La publicación guarda `calendar_events`, `announcements` y un trabajo en
`announcement_delivery_jobs` dentro de la misma transacción (migración 0024).
La petición responde al guardar; no espera el envío de correos o push.
El UUID `requestId` identifica un intento de publicación y permite repetir una
petición cuyo resultado se perdió sin crear otro anuncio.

El formulario se cierra al enviar. Un controlador de sesión conserva la tarjeta
optimista durante la navegación y muestra errores de guardado con un reintento.
El listado consulta el progreso cada dos segundos mientras haya trabajos activos.
Al entrar en la pantalla o recuperar actividad invalida la lista; sin trabajos
activos vuelve a consultar cada 20 segundos. Así detecta publicaciones hechas
desde otras sesiones aunque antes hubiera mostrado «Sin anuncios». Los cambios
de permisos también invalidan el repositorio. Los errores de API siguen mostrando
el estado de error y reintento, sin presentarlos como una lista vacía.
Los anuncios anteriores a esta migración se consideran publicados y no se reenvían.

## Procesamiento

`backend/src/server.ts` inicia el distribuidor; requiere un proceso backend activo
y `SUPABASE_SERVICE_ROLE_KEY`. Nunca se guarda un JWT de usuario en la cola.
Resend utiliza `EMAIL_PROVIDER`, `RESEND_API_KEY` y `RESEND_FROM_EMAIL`; Web Push
conserva la configuración VAPID existente. No incluir estas claves en Flutter.

El distribuidor crea las notificaciones internas en bloque, procesa destinatarios
por lotes de lectura de 50 y separa los comienzos de envíos de correo por 600 ms.
Los correos tienen un tiempo máximo de petición de 15 segundos. El progreso por
destinatario queda guardado y un bloqueo renovable permite recuperar trabajos
interrumpidos. Una segunda instancia no procesa simultáneamente el mismo envío.

Los correos utilizan una clave de idempotencia estable por anuncio/destinatario
(Resend conserva estas claves durante 24 horas). Los reintentos conservan las
entregas registradas como exitosas y vuelven a intentar las fallidas; no vuelven
a crear las notificaciones internas. Las preferencias de correo y la vigencia
del usuario se comprueban antes de enviar.

## Estados

| Estado | Interfaz |
| --- | --- |
| Borrador local pendiente de respuesta | Publicando… |
| `queued` | Preparando envío… |
| `processing`, fase `notifications` | Notificando… |
| `processing`, fase `email` | Enviando correos… y progreso |
| `completed` | Publicado |
| `completed_with_errors` | Publicado con incidencias y reintento de envío |
| `failed` | Publicado, envío incompleto y reintento |

Al terminar se inserta una notificación interna para el autor con enlace a
Anuncios, incluyendo un aviso si hubo incidencias. El feed existente recibe el
cambio mediante Realtime o su sondeo de respaldo. Publicado significa guardado y
solicitudes de envío procesadas; no confirma recepción o lectura del correo.

## Verificación

Desde `backend`: `npm run typecheck`, `npm run docs:apis`,
`npx tsx scripts/announcements_check.ts` y
`npx tsx scripts/announcement_worker_check.ts`.
Desde `backend/scripts`: `node announcements_db_check.mjs` y
`node announcement_queue_check.mjs` (ambos hacen rollback y no envían correos).
Desde `frontend`: `flutter test --no-pub` y `flutter analyze --no-pub`.

Prueba controlada: el flujo previo con ocho destinatarios y 50 ms simulados por
envío tardó aproximadamente 470 ms. El nuevo handler con persistencia simulada
de 5 ms respondió en aproximadamente 12 ms sin esperar al distribuidor. Estas
medidas verifican la separación del envío; no son latencias de producción.
