# Anuncios, audiencia y entregas

Las migraciones 0045 y 0046 se aplican después de 0044. No se han aplicado a Render. Antes de migrar, detener y drenar los workers anteriores; publicar backend y frontend compatibles después de migrar. No ejecutar workers antiguos junto con los nuevos: su protocolo de checkpoints es diferente. Respaldar la base y verificar los trabajos pendientes antes del cambio.

## Lecturas

`GET /api/events/announcements?limit=50&beforeId=123` devuelve `{announcements, hasMore, nextBeforeId}`. El cursor es un bigint decimal en texto y ordena por ID descendente, sin redondearlo en JavaScript. La audiencia se resuelve con RLS antes del límite; el calendario respeta la misma visibilidad. Las escrituras directas de anuncios se retiran: publicar usa la transacción de publicación y outbox existente.

Flutter conserva las páginas anteriores, ofrece actualizar cuando llegan publicaciones nuevas durante la lectura y descarta respuestas anteriores a un refresco explícito. Realtime agrupa invalidaciones; respaldo de 30 segundos con jitter/backoff, conciliación de 5 minutos con canal sano y suspensión de temporizadores en segundo plano. Los trabajos activos consultan exclusivamente `GET /api/events/announcements/status?ids=1,2`, en lotes de hasta 100. Respaldo de 2 segundos y eventos de progreso agrupados durante 2 segundos; `updatedAt` impide retroceder por respuestas tardías. Sin trabajos activos no hay sondeo de progreso.

## Trabajo y contadores

PostgreSQL admite hasta cuatro trabajos simultáneos globales y uno por institución. Cada proceso utiliza `ANNOUNCEMENT_WORKERS` (2 por defecto, máximo 4). Una porción procesa hasta 20 destinatarios o 10 segundos y vuelve a ceder el turno. Las reclamaciones necesitan token y lease vigentes. Preparar destinatarios/notificaciones ocurre una vez; cada checkpoint cambia los contadores por diferencia, sin contar toda la tabla por cada correo. Repetir un checkpoint no duplica contadores ni registros de entrega. El borrado de una cuenta ajusta los contadores de sus destinatarios.

El presupuesto de Resend se comparte entre procesos mediante PostgreSQL y cubre también recuperación de contraseña, invitaciones y 2FA. `EMAIL_MIN_INTERVAL_MS` vale 600 por defecto; validar el límite contratado antes de cambiarlo. La documentación actual de Resend indica 10 solicitudes/segundo por equipo y entre todas sus API keys, pero el límite real de la cuenta puede variar. Se respeta `Retry-After`, se comparte el enfriamiento y se limita la espera reservada. Los errores de configuración o cuota diaria/mensual detienen el trabajo; no generan un error repetido por cada destinatario.

## Reintentos y conciliación

La clave del proveedor y su payload se conservan para cada destinatario. Se comprueban consentimiento, correo y elegibilidad actuales antes del envío. Una respuesta perdida permite repetir la clave mientras sigue siendo válida; no se vuelve a enviar push ya confirmado. Resend conserva las claves durante 24 horas: después de 23 horas, o si cambia el correo tras un intento, el destinatario pasa a `needs_review`. No se promete entrega exactamente una vez fuera de la ventana del proveedor.

El botón de reintento conserva enviados y casos en revisión. Si solo queda revisión, no reencola. Para resolver un caso, un operador debe consultar la evidencia del proveedor y usar la RPC privada `resolve_announcement_email_review`: confirmar enviado requiere ID del proveedor; confirmar no enviado requiere evidencia y genera una nueva clave. No hay endpoint de navegador para esta acción. Drenar cualquier worker antiguo antes de confirmar que no se envió; una instancia pausada fuera del protocolo o una operación externa al proveedor no se puede cercar solo con PostgreSQL. No confirmar ausencia por un simple timeout.

El worker expone parada asíncrona y espera solicitudes/checkpoints en curso; su integración con el cierre HTTP se completa en el bloque 14.

## Validación local

Pruebas PostgreSQL en una base temporal sin credenciales de producción: actualización de trabajos antiguos, concurrencia global, equidad entre instituciones, checkpoints repetidos, borrado de cuenta, permisos, leases, cuotas compartidas, conciliación y más de 1000 destinatarios/publicaciones. Los correos de las pruebas unitarias usan transportes simulados; no envían mensajes reales. La velocidad local de estas pruebas no representa capacidad de Render.

Referencias: [límites de Resend](https://resend.com/docs/api-reference/rate-limit), [idempotencia de Resend](https://resend.com/docs/dashboard/emails/idempotency-keys).


## Push por dispositivo (0052)

Chat y anuncios comparten `notification_push_outbox`: instantánea de dispositivos una vez por notificación, leases distribuidos y checkpoint individual. El worker de anuncios ya no realiza una cadena HTTP por cada dispositivo. Un push pendiente conserva al destinatario pendiente y cede el turno sin contar el sondeo como fallo; la página prioriza correos nuevos para que no se atasquen detrás de esa espera. Los contadores finales distinguen fallidos/omitidos y no anuncian la finalización antes de obtener resultado del push.

El reintento explícito del anuncio reinicia solamente dispositivos fallidos dentro de 24 horas, en la misma transacción que el trabajo/destinatarios; no repite dispositivos confirmados. Caducado el plazo, una nueva publicación es una intención distinta. La función Edge `send-push` ahora solo encola por `notificationId`; configurar VAPID en Node y actualizar las dos funciones legacy al desplegar. Si falta VAPID, el worker lo registra y los trabajos permanecen pendientes hasta configuración/caducidad. Ver `ESCRITURAS_TRANSACCIONALES.md`.
