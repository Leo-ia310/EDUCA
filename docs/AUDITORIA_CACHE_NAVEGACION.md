# Auditoría de consultas y navegación — 2026-10-20

## Evidencia previa a los cambios

- `schedule/providers.dart`: `weeklySlotsProvider` y `childWeeklySlotsProvider` son `autoDispose` sin retención. Al desaparecer su último listener se destruyen; volver a entrar ejecuta `_fetchWeekly` y `GET /schedules/mine`. Home y horario comparten el provider, pero solo mientras vive.
- `grades/presentation/controllers/grades_controller.dart` y `gradebook_controller.dart`: las familias de rendimiento, boletín, evaluaciones y libro se destruyen al salir. Cada ejecución de rendimiento/boletín pide además `repo.defaultScale()`, aunque existe un provider de escala.
- `dashboard/providers.dart`: los cuatro FutureProvider NO son autoDispose; navegar no los destruye. Sí se recalculan por invalidación, cambios de acceso o cualquier emisión de `authControllerProvider`, al observar todo AuthState. Los resolutores de identidad y varios repositorios repiten esta dependencia demasiado amplia.
- Reconstrucción de widgets y consultas son fenómenos distintos. Los skeletons iniciales son legítimos; no se debe ocultar una carga entre cuentas usando datos anteriores. Se medirán llamadas mediante contadores de transporte en tests, no tiempos inventados de producción.
- Chat: streams y repositorio compartidos, AdaptiveRefresh y realtime; mensajes autoDispose liberan suscripciones. Notificaciones: repositorio compartido y refresco adaptativo. Asistencia: Hive y cola por institución/usuario, con reintentos e idempotencia. No sustituir estos mecanismos por caché HTTP.
- Backend de notas: `gradebook` carga evaluaciones/matrícula por lotes y notas por conjunto; no hay consulta por celda. Asistencia agrupa marcas por sesiones. Dashboard docente usa RPC de contadores por lote. Los tests existentes de presupuesto cubren estos casos. No se dispone de EXPLAIN ANALYZE ni estadísticas de la base productiva; no justificar índices nuevos sin esos datos.
- No hay Redis instalado. Candidato limitado: escala institucional predeterminada (catálogo compartido sin notas/personas), dos consultas por lectura. Las respuestas de notas, chat, asistencia, permisos y autenticación quedan fuera de caché compartida.

## Plan y límites de seguridad

1. Reproducir navegación con ProviderContainer y contar llamadas antes/después.
2. Retención de lecturas por TTL; compartir Future en curso; revalidar vistas activas conservando el valor durante refresco; liberar inactivas al expirar. Los cambios de identidad/permisos destruyen el estado inmediatamente.
3. Unificar resolución de escala, invalidación selectiva tras guardar notas y pruebas de aislamiento/expiración/error.
4. Evaluar caché opcional Upstash solo para catálogo institucional, desactivada sin configuración; timeout y fallback a DB. No crear cuentas ni modificar infraestructura productiva.
5. Analyzer, tests Flutter y backend, documentación API si se modifica backend.

No se cambian contratos, routing, migraciones, RLS ni builds. Rollback: revertir los archivos de esta tarea; la caché compartida se desactiva retirando su configuración. Los cambios locales previos en APK y stress-results se conservan.
