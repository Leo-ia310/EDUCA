# Despliegue de las correcciones de escalabilidad

**Estado actualizado:** las migraciones 0029–0053 y los 9 cambios de horarios autorizados ya se aplicaron a Supabase. Backend local `/ready`: 200, contrato 53. Publicación de backend en Render/Edge/clientes pendiente. Ver [registro de aplicación](MIGRACION_SUPABASE_APLICADA_2026_10_19.md). Las referencias siguientes a pendientes describen el estado previo o el procedimiento para otros destinos.

Este chat prepara y verifica código y migraciones localmente. No aplica cambios a Render/Supabase ni publica nuevas aplicaciones. Comprobar el historial real de migraciones antes de aplicar únicamente las pendientes; no asumir el estado remoto a partir de los archivos locales.

## Orden de actualización

1. Registrar plan/CPU/RAM/región de Render, versión de Node, configuración y límites de Supabase/PostgREST y proveedores. Guardar un backup recuperable fuera del repositorio. Preparar una ventana de actualización y la versión mínima de clientes: cambian contratos de escritura y privilegios de Data API.
2. Detener nuevas escrituras y drenar backend/workers antiguos. La migración 0045 cambia leases y claves de entrega; no ejecutar workers antiguos y nuevos a la vez. Conservar solicitudes, recibos y estados de revisión.
3. Ejecutar la revisión de solo lectura de `backend/scripts/schedules-preflight.sql`. Resolver los cruces con el responsable de los horarios antes de activar las exclusiones. No borrar bloques, renombrar aulas ni modificar horas automáticamente para hacer pasar la migración. Ver `HORARIOS_TRANSACCIONALES.md`.
4. Aplicar las migraciones pendientes 0029–0053 en orden. Verificar especialmente reglas de pagos, índices/exclusiones de horarios, RLS, funciones de Auth, recibos de asistencia y escrituras, cola de anuncios y `notification_push_outbox`. 0053 instala el marcador de contrato usado por readiness; ese marcador no sustituye la comprobación del historial completo.
5. Publicar el backend compatible. Desarrollo, Docker y CI usan Node 22.23.4; también se admiten 24.x desde 24.22.1 y 26.x desde 26.12.1. Estos mínimos corrigen CVE-2026-111497: reconstruir las imágenes y reiniciar las instancias tras actualizar. Configurar `SUPABASE_SERVICE_ROLE_KEY`, Resend y VAPID en Node; la clave privada VAPID nunca se distribuye a clientes. Mantener el intervalo global de correo acorde con la cuota real compartida del proveedor. Consultar `OPERACION_BACKEND.md` para plazos, admisión y cierre.
6. Actualizar ambas funciones legacy: `business-api` solo reenvía al Node, con `BACKEND_API_BASE_URL=https://<host>/api` y `CORS_ORIGIN` explícitos; sin configuración falla de forma cerrada. `send-push` solo encola y requiere el secreto interno. La entrega real de todos esos push se hace en Node, no en Edge. Una función antigua que continúe desplegada conservaría su comportamiento previo.
7. Publicar Flutter y actualizar consumidores web con el OpenAPI generado. Son obligatorias claves de creación de personas/perfiles y UUID v4 para mensajes; asistencia usa versiones y operaciones persistidas. Los INSERT/UPDATE directos de dispositivos y los INSERT de mensajes ya no sustituyen las RPC/HTTP autorizadas. También cambian las escrituras directas de boletines/anuncios. Coordinar la actualización de clientes existentes antes de volver a habilitar escrituras.
8. Verificar `/health`, `/ready` (contrato 53), inicio de sesión/2FA y roles reales. Probar lectura y aislamiento por institución; luego crear y limpiar fixtures exclusivamente EDU360 para escrituras. Comprobar pagos concurrentes/idempotencia, asistencia offline/conflictos, alta interrumpida de Auth, publicación de anuncios y un push real por cada navegador utilizado. No convertir datos de BigSchool en fixtures.
9. Reiniciar bajo SIGTERM en una instalación de pruebas y comprobar el drenado/checkpoints. Repetir k6 con recursos y cuentas de pruebas documentados, empezando bajo y aumentando por etapas. Revisar errores y cuotas además de latencia/RPS. Usar `session-flow.js` para recorridos con una identidad distinta por persona virtual; `/health` no mide operaciones académicas.

## Verificación y observación

`npm test` y la suite Flutter verifican contratos, permisos, rollback, concurrencia, filas fuera del primer millar y recuperación local. No ejercitan el servicio Auth/Resend/Web Push real: esos proveedores están simulados o representados por la base temporal. Las comprobaciones de servicio anteriores pertenecen al despliegue, con autorización y fixtures apropiados.

Vigilar códigos 429/503/504, ocupación, latencias, CPU/RAM, conexiones/planes de PostgreSQL y antigüedad/tamaño de colas. Las métricas internas son por proceso; agregar todas las instancias. Supervisar reservas de Auth `pending`/`needs_review`, entregas de correo en revisión y dispositivos fallidos. No copiar tokens, suscripciones, contraseñas ni cuerpos de proveedor a logs.

## Recuperación

Ante una respuesta ambigua, reintentar la misma intención con su clave original. No eliminar identidades Auth, borrar recibos ni generar otra clave para sortear una operación sin confirmar. Los casos fuera de la ventana del proveedor requieren conciliación; ver `ESCRITURAS_TRANSACCIONALES.md` y `ANUNCIOS_Y_ENTREGAS.md`.

Si hay que retirar una versión, detener escrituras y workers antes de cambiarla. Revertir únicamente el binario a un backend antiguo puede ser incompatible con los nuevos privilegios y contratos. Conservar la evidencia de operaciones confirmadas al planificar la recuperación; restaurar un backup o retirar restricciones no es un rollback automático seguro de datos producidos después de ese backup.

## Archivo completo para SQL Editor

El paquete `supabase/deploy/scalability-0029-0053.sql` contiene las 25 migraciones en una sola transacción, comprobación previa de horarios y verificación final del contrato 53. Se regenera sin conexión con `node backend/scripts/build-scalability-sql.mjs`. La prueba `backend/test/scalability-bundle.integration.test.mjs` comprueba ejecución completa, rollback preventivo ante horarios incompatibles, rechazo de segunda aplicación y acceso con 2FA ausente/desactivado.

La revisión del 19 de octubre encontró 13 cruces existentes en Big School. Ejecutar primero `supabase/deploy/revisar-horarios.sql` y revisar [ACTUALIZACION_SUPABASE_2026_10_19.md](ACTUALIZACION_SUPABASE_2026_10_19.md). El paquete se detiene antes de aplicar cambios si continúan esos cruces. No incluye decisiones automáticas sobre horarios reales.
