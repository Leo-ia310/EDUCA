# Caché y consultas de Nivra — 2026-10-20

## Diagnóstico

La [auditoría inicial](AUDITORIA_CACHE_NAVEGACION.md) se escribió antes de modificar código. Horarios y las familias de notas perdían su estado por `autoDispose`; volver a una ruta volvía a ejecutar la lectura. Dashboard ya conservaba datos, pero observaba emisiones completas de autenticación. Varios repositorios también se reconstruían por estados transitorios de carga/error. Una reconstrucción de widget no equivale a una petición HTTP.

## Cambios

- `core/network/provider_cache.dart`: caché exclusivamente en memoria usando Riverpod, retención del Future en curso, TTL desde la respuesta exitosa, liberación de familias inactivas sin consultas de fondo y revalidación de consumidores activos conservando el valor anterior. Los errores no se retienen entre visitas. Las dependencias de identidad/acceso destruyen el estado anterior y sus timers.
- `query_auth_provider.dart`: datos y repositorios dependen de usuario, institución, rol y permisos; flags transitorios de autenticación no los recrean. Se aplica a identidad, dashboard, notas, tareas, eventos, pagos, chat y asistencia. No se cambia el contrato de autenticación.
- Lectura única de escala para libro, rendimiento y boletín. Familias diferenciadas por alumno/clase/periodo. Guardar una nota invalida ese libro, el rendimiento y los boletines de ese alumno, sus evaluaciones de esa clase y el dashboard docente. No invalida el repositorio completo ni otros alumnos/clases.
- Crear/editar tareas, calificar y entregar refrescan el dashboard correspondiente. Guardar/eliminar horarios invalida únicamente datos de horarios. Las acciones existentes siguen actualizando sus feeds.
- GET simultáneos equivalentes comparten un transporte por cliente, token y parámetros normalizados. No hay caché HTTP de respuestas completadas. Las escrituras separan solicitudes anteriores de lecturas nuevas. Logout/cambio de cuenta cancela solicitudes autenticadas y limpia la deduplicación.
- Las vistas que consumían `valueOrNull` de dashboards descartan valores anteriores durante cambios de dependencia o errores. Conservan valores solo durante refrescos del mismo ámbito. Se quitaron fallbacks visuales a dashboards mock en esas vistas secundarias; demo sigue en sus providers originales.

| Lectura | TTL local | Actualización |
|---|---:|---|
| Dashboard por rol | 1 min | Revalidación activa, refresco manual e invalidaciones de escrituras |
| Rendimiento, boletín, evaluaciones, libro | 1 min | Revalidación activa y escritura selectiva |
| Horario propio / hijo | 5 min | Revalidación activa, refresco manual, cambio de permisos y escritura de horario |
| Escalas y periodos | 5 min | Revalidación activa; nueva sesión/institución/permisos invalida dependencias |
| Chat y notificaciones | Sin caché nueva de respuestas | Se conservan realtime, refresco adaptativo y feeds compartidos |
| Asistencia offline | Sin modificación del protocolo | Se conserva Hive por ámbito, cola, versiones, conflictos e idempotencia |

Una vista inactiva expirada vuelve a cargar al entrar. SWR se aplica a la revalidación de una vista activa; no se retienen indefinidamente datos vencidos. Los cambios de otros dispositivos en notas/dashboard se observan en la siguiente revalidación, hasta aproximadamente un TTL más el tiempo de red. No se afirma sincronización instantánea de estos datos.

## Upstash opcional y limitado

Se comparten el catálogo de `GET /api/grades/scales/default` y los tipos de estado de asistencia, sin estudiantes, notas, pagos, mensajes ni permisos. Sus lecturas actuales tienen alcance institucional uniforme; las políticas de configuración restringen escrituras, no crean variaciones del catálogo por usuario (`0003_rls_policies.sql`, `0006_hardening.sql`, `0020_admin_permissions_rls.sql`). La autenticación y autorización del request se ejecutan antes de cada hit. Nunca se cachea el contexto de sesión.

Configuración **solo en backend**:

```dotenv
UPSTASH_REDIS_REST_URL=https://<instancia>.upstash.io
UPSTASH_REDIS_REST_TOKEN=<secreto-del-backend>
CACHE_NAMESPACE=nivra:production
```

El namespace incorpora además el host del proyecto Supabase y el ID institucional. Use namespaces distintos entre despliegues independientes. Sin ambas credenciales la integración queda desactivada. No se añadieron dependencias npm, cuentas ni recursos externos; no se modificó Render ni Supabase remoto.

TTL compartido: 30 segundos. Configurar/editar escalas cambia una revisión de la institución, tanto por REST como por las acciones legacy existentes, que llaman al mismo service. Una carga iniciada antes de escribir no puede repoblar la revisión actual. Revisiones expiran a los 300 segundos, después de todas las respuestas antiguas. Solo se guardan lecturas exitosas; errores, timeouts y cuotas agotadas usan DB. Timeout Redis: 2000 ms por comando, configurable con `REDIS_TIMEOUT_MS` (100–5000 ms); circuito local abierto 30 s tras fallo. No se implementa lock distribuido: cada proceso deduplica sus misses; dos réplicas pueden cargar el mismo catálogo una vez cada una.

Si falla la invalidación tras una escritura confirmada, otras réplicas pueden conservar el catálogo hasta sus 30 segundos de TTL. El proceso que detecta el fallo consulta DB durante el circuito. No se aplica esta consistencia eventual a permisos ni datos personales.

Cada hit de escala consume dos GET en Redis (revisión y valor); cada miss exitoso añade un SET. Los estados de asistencia usan un GET y, al cargar, un SET; su L1 evita comandos durante 10 segundos. Conviene habilitarlo cuando hay suficientes lecturas compartidas dentro de esos 30 segundos. No ahorra la autenticación del backend ni el HTTP del cliente, y una consulta aislada puede tardar más por el viaje a Redis. La caché local es la optimización principal para navegación.

El plan gratuito publicado incluye 256 MB y 500 000 comandos/mes: verificar cuota antes de activar. No equivale a capacidad garantizada para miles de usuarios. Fuente: [precios oficiales Upstash](https://upstash.com/pricing/redis). Ciclo de vida utilizado: [documentación Riverpod 2](https://docs-v2.riverpod.dev/docs/concepts/modifiers/auto_dispose).

## Mediciones reproducibles

Mediciones de tests con transporte/repositorios instrumentados y fixtures aislados; **no son mediciones de latencia ni tráfico en producción**. Ningún dato real se reemplazó por fixtures en ejecución conectada.

| Escenario | Antes | Después | Alcance |
|---|---:|---:|---|
| Tres visitas a Horarios dentro del TTL | 3 GET | 1 GET | Regresión ejecutada antes de implementar retención: falló mostrando las tres llamadas; después pasó |
| Tres visitas a notas de dos alumnos | 6 lecturas de rendimiento | 2 | Una por alumno; una escala compartida |
| Dos GET concurrentes equivalentes | 2 transportes | 1 | Después de completarse, un GET nuevo vuelve al transporte |
| 20 lecturas del mismo catálogo institucional en TTL | 40 consultas de catálogo a DB | 2 | Prueba del adaptador y service con Redis simulado; 19 hits; no incluye auth |

La segunda y cuarta referencias anteriores corresponden al presupuesto del código anterior o sin caché, no a una ejecución contra el servicio remoto. Los contadores del adaptador compartido (`hits`, `misses`, `joins`, `failures`) permiten instrumentar el piloto sin registrar payloads ni tokens.

## PostgreSQL y N+1

Libro de notas y asistencia ya leen conjuntos completos por lotes; dashboard docente usa RPC de contadores, y horarios se resuelve en una RPC con filtros previos a paginación. No se encontró una consulta por celda de nota ni por cada marca en estos caminos. Se mantienen los tests de presupuesto que cubren más de 1000 filas, 1440 evaluaciones, grillas y conteos completos. No se agregaron índices ni migraciones especulativas.

Las integraciones locales comprueban planes de RLS con helpers de una ejecución, permisos de clases por lote y búsqueda administrativa por índice. No sustituyen `pg_stat_statements`/`EXPLAIN (ANALYZE, BUFFERS)` con volúmenes y distribución reales de cada institución.

## Activación, límites y rollback

Pendiente operativo: configurar Upstash en Render si el piloto demuestra beneficio; observar hit rate, latencias p50/p95 y cuota de comandos. Comparar solicitudes por sesión para Dashboard → Horarios → Calificaciones → Dashboard, separando cargas iniciales, mutaciones, cambio de permisos y expiraciones. Revisar consultas lentas reales antes de proponer índices.

No se certifica capacidad para miles de usuarios con estos tests. Quedan fuera de esta entrega el aprovisionamiento remoto, un ensayo de carga contra producción y sincronización instantánea de notas entre dispositivos. Algunos repositorios legacy mantienen sus políticas previas de demo; no se rediseñó la autenticación ni todos los flujos de errores de la app.

Rollback: retirar las dos variables Upstash para desactivar caché compartida. Revertir los archivos de esta tarea para quitar retención local; no hay migraciones que deshacer. Se conservaron el APK modificado y los resultados de estrés que ya estaban en el workspace.

## Validación final

- `cd frontend && flutter analyze --no-pub`: **No issues found!** ([salida](performance/cache-navigation/flutter-cache-analyze.log)).
- `cd frontend && flutter test --no-pub --reporter expanded`: **190 pruebas aprobadas** ([salida](performance/cache-navigation/flutter-cache-tests.log)).
- Verificación adicional de caché, navegación, notas y pantallas de horarios/libro: **19 pruebas aprobadas**, incluidas en las 190 anteriores ([salida](performance/cache-navigation/flutter-cache-focused.log)).
- `cd backend && npm test`: typecheck, **67 unitarias y 88 integraciones PostgreSQL aprobadas**. Después de añadir una prueba de conexión del service con la caché se repitieron `npm run typecheck` y `npm run test:unit`: **68 unitarias aprobadas** ([salida final](performance/cache-navigation/backend-cache-unit.log)). No hubo cambios posteriores en SQL.
- `npm run docs:apis`: ejecutado nuevamente; manifiesto y OpenAPI actualizados. `APIS_PENDIENTES_POR_CONECTAR.md` se regeneró y conserva el mismo contenido porque no se añadieron rutas pendientes.
- `git diff --check`: sin errores de whitespace. Sin cambios de esta tarea en migraciones, RLS, contratos públicos, routing ni plataformas móviles.

Las regresiones nuevas cubren: expiración activa/inactiva, reuso de Future en curso, error y reintento, invalidación selectiva, cambio de rol/logout, respuesta tardía de otro ámbito, bloqueo de cadenas desechadas antes de iniciar otra consulta, lecturas concurrentes, aislamiento de catálogos por institución, invalidación concurrente, fallo de Redis y circuito de respaldo. Los fixtures solo existen en tests.


## Ampliación Redis después de configurar credenciales

Conexión real verificada, sin mostrar URL ni tokens: PING, escritura, lectura y borrado correctos. El probe `cd backend && npx tsx scripts/verify-redis.ts` también comprobó dos hits entre clientes independientes e invalidación de escala, con cero fallos. Usó un namespace de verificación único y eliminó exclusivamente sus claves; no consultó datos escolares ni alteró claves de aplicación.

La primera comprobación detectó que el timeout de 500 ms era insuficiente desde este equipo: una conexión fría tardó 1268 ms y una lectura 587 ms. Se corrigió a 2000 ms por defecto y se volvió a verificar con éxito. Son tiempos puntuales de transporte desde el equipo local, no percentiles ni latencias de Render. Conviene mantener Redis y Render en regiones cercanas.

Además de escalas, `AttendanceService.classRoster`, `summary` y `groupDetail` reutilizan exclusivamente `catalog_attendance_statuses`. Es un catálogo de referencia de lectura pública según `0003_rls_policies.sql`. Las autorizaciones, alumnos, sesiones y marcas se siguen validando/consultando en cada petición. Una prueba modifica las marcas entre dos resúmenes y confirma que el segundo cambia aunque el catálogo provenga de caché; al revocar permiso, devuelve 403 antes de leer marcas.

- Redis para tipos de estado: 60 segundos. No hay una API que edite ese catálogo; cambios externos por SQL se observan al expirar. La capa local puede añadir hasta 10 segundos, por lo que el máximo de antigüedad es aproximadamente 70 segundos más red.
- L1 del proceso: 10 segundos, máximo 128 instituciones. Retorna copias para evitar que un consumidor modifique el valor de otros. Deduplica lectores concurrentes desde antes de consultar Redis.
- Claves separadas por catálogo, namespace, proyecto Supabase e institución. Se conserva la revisión de escalas y su invalidación en las escrituras existentes.
- `/internal/metrics` mantiene su autorización con `INTERNAL_API_SECRET` y añade `catalogCache`: enabled, circuitOpen, localEntries, hits, localHits, misses, joins, failures. Los contadores son por proceso y no contienen tokens, URLs, IDs ni claves. `misses` cuenta cargas tras un miss Redis, no todas las consultas de respaldo durante un fallo.
- Presupuesto de prueba: 20 lectores concurrentes del catálogo de asistencia pasan de 20 consultas de referencia a 1 y usan 2 comandos Redis; otra réplica obtiene el catálogo con 1 GET adicional. No se reduce el número de lecturas de marcas ni controles de permisos.
- Validación de esta ampliación: typecheck y 72 pruebas unitarias backend aprobadas; incluye las 10 pruebas de caché/servicios y la autorización de métricas. Se regeneraron docs de APIs. No se cambiaron SQL, RLS ni Flutter en esta ampliación; las 88 integraciones SQL y 190 pruebas Flutter corresponden a la fase anterior.

La configuración local ya responde. Un proceso que ya estaba iniciado debe reiniciarse para leer las variables; Render necesita estas variables en su propio entorno y desplegar este código. Esta verificación no es un despliegue remoto.
