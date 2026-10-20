# Operación del backend

Cambios locales, pendientes de despliegue coordinado con las migraciones 0029–0053 y clientes. Configurar Render para consultar `/ready` cuando se quiera comprobar disponibilidad; `/health` confirma únicamente que el proceso responde. `/ready` comprueba consulta SQL y contrato 53, con consulta compartida/caché de dos segundos. No valida Resend/VAPID ni mide capacidad de negocio.

## Presupuestos y errores

- `DEPENDENCY_TIMEOUT_MS=15000`: cada llamada Supabase, incluidos Auth, REST, Storage y logout. La señal también se conserva durante consumo del cuerpo. Los envíos Resend/Web Push tienen sus propios límites acotados.
- `REQUEST_TIMEOUT_MS=60000`: presupuesto HTTP total; al vencer responde 504 y cancela dependencias. Desconectar el cliente cancela el contexto. Cancelar HTTP no prueba que PostgreSQL o un proveedor no hayan confirmado: reintentar escrituras con su clave original.
- `MAX_CONCURRENT_REQUESTS=100`: admisión por proceso; exceso devuelve 503 y `Retry-After: 2`. No es una promesa de 100 usuarios soportados ni un límite global de la flota. El cupo de cada usuario sigue compartido en SQL.
- `SHUTDOWN_TIMEOUT_MS=25000`: al recibir SIGTERM/SIGINT deja de admitir trabajo, cierra conexiones ociosas y espera peticiones y checkpoints de ambos workers. Al agotar el plazo cancela conexiones y sale con error; la recuperación utiliza recibos/leases persistentes. Ajustar por debajo del plazo real del proveedor de hosting.

Los errores de permisos son 403, inexistencia 404, conflictos 409 y validación 400. Fallos de SQL, esquema pendiente o timeout de dependencia devuelven 503, sin nombres de tablas, consultas ni filas. JSON inválido devuelve 400 y cuerpo excesivo 413. Auth caído o limitado no incrementa contraseñas incorrectas. `x-request-id` y el error JSON permiten correlación; se aceptan únicamente identificadores cortos seguros.

Flutter conserva `statusCode`, `code`, `requestId`, `retryAfter` y `retryable`; conexión 15 s, envío 30 s y recepción 75 s por defecto. Cancelar/cambiar de cuenta invalida solicitudes de la sesión anterior. No hay reintento automático de escrituras. La caché offline solo se usa ante fallos transitorios, no ante 401/403/cancelación.

## Observabilidad

`GET /internal/metrics` exige `Authorization: Bearer INTERNAL_API_SECRET`. Devuelve contadores, errores, tiempos acumulados/máximos y buckets de latencia, solicitudes activas y tiempo de vida. Los nombres de rutas son plantillas y no incluyen IDs, cuerpos, query strings ni tokens. Medidas por proceso: recolectar y agregar todas las instancias; se reinician al reiniciar el proceso. La latencia de dependencia mide hasta recibir cabeceras; la HTTP mide hasta finalizar/cerrar la respuesta. No interpretar estos buckets como un percentil de toda la flota.

Alertar por 5xx/504, ocupación, latencia de rutas reales, 429, edades de colas, trabajos en revisión/fallidos y fallos al drenar. Correlacionar con CPU/memoria de Render, conexiones/tiempos/planes de PostgreSQL y cuotas del proveedor. No registrar correos, JWTs, suscripciones push ni payloads de proveedores en logs.

La capacidad final requiere desplegar los cambios y repetir carga representativa con los scripts k6 y los recursos reales de Render/Supabase. Las pruebas locales y `/health` no permiten calcular usuarios simultáneos.


Node mínimo 20.3.0, con CI en 22: la composición de señales usa [AbortSignal.any](https://nodejs.org/api/globals.html#static-method-abortsignalanysignals). Las métricas conservan códigos exactos (por ejemplo 429, 503 y 504), sin agrupar todas las limitaciones y fallos en un mismo estado genérico. Cada turno del worker admite como máximo su concurrencia, incluso si una entrega termina antes de la siguiente admisión; no acumula promesas de toda la cola. El worker activo vuelve a ceder al event loop entre turnos y conserva el sondeo de respaldo cuando no hay trabajo.
