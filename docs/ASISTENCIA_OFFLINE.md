# Asistencia offline con confirmación y versiones

La migración 0047 se aplica después de 0046. Está probada localmente y pendiente de despliegue. Backend, Flutter y cualquier cliente web que escriba asistencia deben actualizarse juntos: ya no se permite escribir `attendances` directamente ni reemplazar cambios sin versión.

## Escritura

`POST /api/sync/attendance/batch` recibe hasta 100 sesiones y 100 marcas. Cada marca contiene `operationId` UUID, UUID local estable, clase, fecha civil `AAAA-MM-DD`, estudiante, estado, versión esperada, `recordedAt` y notas. La versión inicial es 0. La clave y el contenido deben ser idénticos al reintentar; una nueva edición necesita otra clave. Las sesiones, marcas, registro de cambios y recibos se escriben en una transacción. Un elemento no autorizado o inválido revierte todo el lote.

Los cambios simultáneos se resuelven comparando la versión guardada, sin confiar en el reloj del teléfono. Si difiere, esa marca devuelve `conflict`, versión y estado/notas del servidor; no sobrescribe. El cliente conserva su elección y requiere revisión explícita antes de crear otra operación. Los demás elementos válidos del lote pueden confirmarse. Repetir una operación confirmada devuelve el recibo original, incluso si se perdió la respuesta HTTP. Los recibos pertenecen al actor y están fuera de la API de datos del navegador.

Las rutas individuales y el guardado por clase usan el mismo protocolo. El guardado por clase también exige claves, versión y `recordedAt` estable; devuelve conteos y resultados por marca. El docente se deriva del JWT y se vuelven a comprobar cuenta, institución, matrícula y permiso de clase, incluidos colaboradores revocados. No se aceptan los IDs de docente enviados por el cliente como prueba de identidad.

## Almacenamiento local

Hive separa registros, sesiones, cola y caché por institución/cuenta. Los registros antiguos sin propietario verificable se conservan bajo sus claves anteriores, pero no se muestran ni suben automáticamente. Su recuperación requiere identificar al autor y contrastar la asistencia del servidor; no se deben asignar al siguiente usuario que abra el teléfono.

La operación se persiste antes del HTTP y se elimina de la cola únicamente después de validar la confirmación del lote. Si falla la red, se cierra la pantalla, cambia la cuenta o se reinicia el servicio, queda pendiente. Una edición realizada durante un envío conserva su operación nueva y utiliza la versión confirmada como base del lote siguiente. Las sesiones y marcas se envían en lotes; no se hace una solicitud de telemetría por fila. Se recupera también el caso de cierre después de guardar el estado sincronizado y antes de limpiar su entrada de cola.

El roster y las clases consultados con éxito se conservan en una caché separada por cuenta. Ante errores transitorios se pueden consultar sin conexión; un 401/403 no se transforma en una lectura de caché. La primera consulta de una clase necesita conexión. El servidor vuelve a autorizar cualquier subida; una caché previa no concede permisos de escritura. No se fabrican clases/rosters demo cuando falla una sesión real. Se conserva la fecha civil de la clase aparte del reloj del dispositivo.

La pantalla presenta las marcas sin seleccionar como `Sin marcar`. No las cuenta como presentes ni las completa silenciosamente al finalizar. `Todos presentes` es una acción explícita. Los conflictos muestran el valor del servidor y piden confirmar la elección individual; el atajo masivo no los resuelve.

## Cambios incrementales

`GET /api/sync/changes?limit=100` devuelve `changes.items`, `hasMore` y `nextCursor`. Continuar con `cursor=nextCursor`, conservando el texto completo. El cursor contiene `(updated_at,id)` con microsegundos y bigint sin redondear. No avanzar desde `serverTime` ni paginar mediante offset. `since` se admite solo como inicio.

Las escrituras asignan timestamps después de tomar un bloqueo por institución; pull toma el mismo bloqueo para no saltar una transacción que termine más tarde. El timestamp del log es monótono por institución. Solo se devuelven cambios de asistencia de clases autorizadas, incluidas bajas como tombstones mientras siga autorizada la clase. El log comienza con esta migración; una instalación nueva usa primero la instantánea del roster. Este endpoint no sincroniza pagos, notas, tareas ni chats. No se elimina historial de cambios o recibos automáticamente: purgarlo exige definir una ventana de soporte y un protocolo de nueva instantánea, sin borrar claves aún reintentables.

Los endpoints heredados `/sync/queue` guardan exclusivamente metadatos; no ejecutan ni confirman asistencia. El cliente actual utiliza el lote transaccional.

## Pruebas

La suite usa PostgreSQL temporal y cajas Hive temporales, sin credenciales de producción. Cubre reintentos tras respuesta perdida, persistencia en disco, límites de lote, edición durante subida, conflicto, aislamiento entre cuentas, caché offline y denegaciones, rollback, revocación de colaboradores, más de 1000 cambios y espera de commits en curso. Las mediciones locales no equivalen a capacidad de Render.
