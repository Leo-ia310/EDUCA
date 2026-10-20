# Escrituras compuestas y recuperación

Las migraciones 0048–0052 y sus clientes son una actualización coordinada. No se han aplicado a producción. Hacer backup y probar restauración antes de desplegar. Detener escritores/worker antiguos, aplicar las migraciones en orden y actualizar backend, Flutter y cualquier consumidor web del contrato generado.

## Personas, cuentas y documentos

Persona, estudiante/docente/acudiente, vínculos y datos del acceso se confirman en una transacción. Se conservan clases históricas; solo se reemplazan asignaciones del año actual cuando el actor tiene `classes.edit`. Archivar una persona desactiva sus accesos vinculados sin borrar historia. No permite archivar la propia cuenta ni administrar un rol protegido fuera del alcance real del actor. Los roles globales son de lectura y el código de un rol asignado es inmutable.

Las escalas reemplazan cabecera y rangos juntos; se rechazan superposiciones. Los boletines obtienen una sola instantánea de notas autorizadas y persisten año/matrícula reales. Los cargos masivos validan y guardan todo o nada y devuelven todos los IDs como texto, sin el límite de 1000 filas de PostgREST. Usar un `requestId` UUID estable para reintentar estas operaciones. Misma clave con contenido diferente devuelve 409. No hay purga automática de recibos sin definir antes su ventana de reintento.

## Altas con Supabase Auth

`POST /api/admin/{profiles,students,teachers,parents}` requiere `requestId` UUID. Antes de contactar Auth, SQL guarda una reserva privada de correo, UUID de identidad y huella del contenido. La contraseña viaja solamente a Auth; no se guarda en tablas, preferencias ni logs. La comprobación de reintento combina una derivación scrypt con el contenido y la clave.

Auth y PostgreSQL son servicios separados. No existe una transacción distribuida entre ambos. Si se pierde una respuesta, conservar el mismo `requestId`, contenido y contraseña: el backend consulta el UUID reservado y recupera el alta. Persona, entidad, usuario, rol y vínculos se confirman después en una sola transacción. La cuenta debe acreditar el `provisioning_id` y la institución de su reserva. Una identidad de procedencia distinta no se adopta.

Flutter guarda únicamente la clave de reintento, por institución/cuenta/tipo/correo, y genera los códigos de alumno/docente a partir de esa clave al crear. Editar una persona conserva su código anterior. Un 503 conserva la reserva; no se debe cambiar de clave para intentar sortearlo. Solo un rechazo explícito 400/422 de Auth, con ausencia de identidad comprobada, permite cancelar esa reserva y comenzar otra.

La conciliación es una operación privada de mantenimiento. Para reservas detenidas: detener y drenar los procesos de alta; revisar `admin_provisionings` por ID, estado, UUID reservado/observado y fechas; contrastar Auth, sus metadatos y `public.users`; recuperar con la solicitud original o completar mediante un operador autorizado tras verificar su contenido. `needs_review` exige esa revisión. No eliminar una cuenta Auth por un timeout: la transacción pública puede haberse confirmado. Una cancelación excepcional exige comprobar primero que no hay solicitud externa todavía ejecutándose y que la identidad no está vinculada. Conservar la reserva como evidencia; no borrar recibos para permitir duplicados.

## Mensajes y push

`chat.sendMessage` requiere `requestId` UUID v4. La RPC 0052 valida actor/MFA/permisos/membresía/adjunto y guarda mensaje, notificaciones internas y trabajos push por dispositivo en una transacción. La repetición idéntica devuelve el mismo mensaje; un UUID reutilizado para otro contenido produce 409. Se revoca el INSERT directo de mensajes para impedir saltarse este contrato.

Flutter conserva la clave por institución, cuenta, conversación y huella del texto/archivo; no persiste texto ni URLs en esas preferencias. Un envío no confirmado se reintenta explícitamente con el mismo contenido, incluso tras recrear el repositorio. No reenvía pendientes de otra cuenta. Dos mensajes idénticos confirmados sucesivamente tienen UUIDs distintos. El texto/adjunto visible se conserva al fallar y no permite doble clic durante el envío. La reconciliación de burbujas usa UUID, nunca una coincidencia de texto y tiempo. Las claves pendientes no se purgan automáticamente; un borrador visible no se restaura tras reiniciar y el usuario debe volver a introducir el contenido para recuperar esa operación.

Los push ya no bloquean la respuesta del chat. `notification_push_outbox` tiene cuatro leases globales, uno por institución, dos envíos locales concurrentes, turnos entre instituciones y un dispositivo por lease. Se comprueban usuario, institución, permiso, membresía y dispositivo antes de enviar. Cada dispositivo confirmado conserva su checkpoint; un fallo no repite otros dispositivos. Hasta tres intentos, backoff/Retry-After y caducidad a las 24 horas. Una suscripción sustituida no se desactiva por un fallo de la antigua.

Configurar `SUPABASE_SERVICE_ROLE_KEY` y VAPID en el backend para este worker; la Edge Function `send-push` ahora solo encola y todos los envíos de chat/anuncios los realiza Node. Si falta configuración, el arranque lo registra y conserva la cola hasta su caducidad. Los anuncios mantienen su estado pendiente mientras esperan confirmación push; priorizan correos aún no procesados para que esa espera no bloquee a los demás destinatarios. El reintento explícito de anuncios solo reinicia dispositivos fallidos dentro de su plazo, conservando los confirmados. La notificación interna permanece disponible. La entrega Web Push externa puede repetirse si se pierde su confirmación; el tag estable sustituye la tarjeta visible. No se promete entrega exactamente una vez. Supervisar trabajos `failed` y tamaño/edad de pendientes; purgar solo registros terminales según una política de retención aprobada, nunca recibos de mensajes o altas para forzar reintentos.

Las pruebas usan PostgreSQL temporal y proveedores simulados, sin correos/push ni escrituras en Render.


Los destinos push se validan al registrar y antes de cada envío: HTTPS/443, sin credenciales, claves de tamaño esperado y dominios de proveedores conocidos. Las suscripciones no pueden dirigir el worker a URLs internas o dominios arbitrarios. La lista sigue los destinos publicados por [Chrome](https://developer.chrome.com/blog/push-notifications-on-the-open-web), [Mozilla](https://blog.mozilla.org/services/page/2/), [WebKit](https://webkit.org/blog/12945/meet-web-push/) y [Microsoft](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/wns-overview); actualizarla deliberadamente si cambia un proveedor. Una suscripción antigua inválida se desactiva sin exponer su URL en logs.


El registro de navegador también usa una RPC autenticada y serializada por usuario/endpoint: dos llamadas simultáneas conservan un solo dispositivo activo; al refrescar una suscripción se retiran duplicados históricos del mismo usuario sin borrar evidencia. INSERT/UPDATE directos de `devices` quedan revocados para clientes; conservar el endpoint de registro del backend. La validez de la suscripción se verifica otra vez al entregar, de forma independiente de la vía por la que llegó al almacenamiento.
