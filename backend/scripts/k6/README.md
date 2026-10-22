# Pruebas k6 contra Render

Ejecutar desde la raíz del repositorio. Requiere `k6` en PATH.

```powershell
New-Item -ItemType Directory -Force backend/stress-results/mi-prueba | Out-Null
k6 run --env SMOKE=1 --env SUMMARY_PATH=backend/stress-results/mi-prueba/smoke.json backend/scripts/k6/health.js
k6 run --env PROFILE=inventory --env SUMMARY_PATH=backend/stress-results/mi-prueba/inventory.json backend/scripts/k6/backend.js
k6 run --env PROFILE=reads --env SUMMARY_PATH=backend/stress-results/mi-prueba/reads.json backend/scripts/k6/backend.js
k6 run --env PROFILE=writes --env ALLOW_WRITES=EDU360 --env SUMMARY_PATH=backend/stress-results/mi-prueba/writes.json backend/scripts/k6/backend.js
k6 run --env PROFILE=login --env SUMMARY_PATH=backend/stress-results/mi-prueba/login.json backend/scripts/k6/backend.js
k6 run --env SUMMARY_PATH=backend/stress-results/mi-prueba/health.json backend/scripts/k6/health.js
```

Ejecutar los perfiles por separado, conservando también su salida de consola con `Tee-Object`.
No ejecutar perfiles simultáneos si se desea atribuir los resultados a una carga concreta.

- `BASE_URL`: por defecto `https://nivra-backend-mcc4.onrender.com`.
- `INSTITUTION_CODE`: por defecto `EDU360`. Las escrituras exigen `ALLOW_WRITES=EDU360`.
- `ADMIN_USERNAME`, `TEACHER_USERNAME`, `STUDENT_USERNAME`, `PARENT_USERNAME`, `DEMO_PASSWORD`: credenciales de las cuentas demo, reemplazables mediante entorno. Cada rol admite también `ADMIN_PASSWORD`, `TEACHER_PASSWORD`, `STUDENT_PASSWORD` o `PARENT_PASSWORD`.
- `reads`: mezcla equilibrada de los cuatro roles; sube hasta 40 peticiones/s, con mesetas de 30 s.
- `soak`: lecturas sostenidas; `SOAK_RPS=5` y `SOAK_DURATION=120s` por defecto.
- `writes`: crea ocho tareas borrador con prefijo `K6-STRESS-`, actualiza esas tareas a `WRITE_RPS` (2/s por defecto) y las elimina lógicamente al terminar. Confirma que desaparecieron del listado. Los registros archivados permanecen en la base de datos según el contrato de borrado del backend.
- `login`: 1 login/s durante 30 s.
- `health`: sube hasta un objetivo de 1000 peticiones/s y 500 VUs. No consulta Supabase: no representa capacidad de operaciones académicas.

Las cuotas por usuario/IP siguen activas. Un HTTP 429 mide la cuota de las cuentas empleadas; no demuestra saturación de infraestructura. Los perfiles abortan ante errores de servidor sostenidos o demasiados 429. El objetivo de carga puede superar la carga generada; revisar `dropped_iterations` y los VUs antes de interpretar capacidad.

El inventario usa OpenAPI, prueba las lecturas con sus parámetros y excluye de carga las rutas que ya fallan. Los fallos y omisiones se registran en `COVERAGE`; nunca se deben presentar las omisiones como rutas aprobadas. No se generan anuncios masivos ni mensajes a personas ajenas a fixtures. Pagos, asistencia, 2FA, recuperación de contraseña y generación de boletines requieren fixtures y restauración específicos para probar escrituras completas.

Los resúmenes eliminan `setup_data`, que en k6 1.7 puede contener tokens. No activar HTTP debug ni guardar respuestas de login. Si se interrumpe externamente el proceso, revisar `FIXTURES` y completar la limpieza de las tareas registradas.

Referencia: [executors de llegada constante](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/constant-arrival-rate/) y [umbrales con aborto](https://grafana.com/docs/k6/latest/using-k6/thresholds/).


## Capacidad por personas con cuentas distintas

`session-flow.js` usa una identidad real de pruebas por VU, recorridos de tres lecturas según rol y pausas de 3–7 segundos. Exige que todas las cuentas pertenezcan a EDU360 y que todas las rutas del recorrido funcionen antes de iniciar carga. No escribe datos ni excluye silenciosamente rutas fallidas. El destino predeterminado es local; establecer `BASE_URL` deliberadamente para otra instalación.

Pasar `ACCOUNTS_JSON` mediante entorno, sin guardarlo en el repositorio ni activar HTTP debug: lista de objetos con `username`, `password`, `role` y opcional `institutionCode`. `PEOPLE` no puede superar el número de identidades distintas proporcionadas. Cuatro cuentas permiten esta prueba de cuatro personas; no se multiplican para afirmar cien usuarios. Ejecutar `k6 run --env PEOPLE=4 --env BASE_URL=https://<host> --env SUMMARY_PATH=<ruta-segura>.json backend/scripts/k6/session-flow.js` tras configurar el entorno.

La rampa llega a PEOPLE, mantiene tres minutos el máximo y reduce la carga. Umbrales: errores de negocio <1 %, p95 <2 s; aborta por >5 % de errores de servidor o >10 % de limitación sostenida. Revisar 429 por separado: una cuota no mide CPU máxima. Comparar solicitudes realmente completadas, RPS, VUs alcanzados, latencias y recursos de Render/Supabase. `http_reqs` incluye login/probes; `business_requests` cuenta solo recorridos. El resumen omite tokens y datos de setup. No afirmar capacidad superior a la realmente sostenida ni presentar `/health`/`/ready` como tráfico de negocio.

La ejecución del 20 de octubre usa el diagnóstico descrito a continuación. Los resultados del 17 de octubre permanecen históricos y no se suman a las cifras nuevas.

## Diagnóstico de 503 y carga con ocho cuentas

`run-diagnostic.mjs` inicia sesión una vez por cuenta, comprueba 25 rutas de lectura y ejecuta `diagnostic.js` con k6. Recibe exactamente ocho cuentas distintas en `K6_ACCOUNTS_JSON`, con `username`, `password`, `institutionCode` y `role` (`admin`, `teacher`, `student`, `parent`). Usar únicamente cuentas autorizadas. Las contraseñas y tokens pasan por memoria/entorno y no se guardan en resultados; no activar HTTP debug.

Desde la raíz, con el entorno de credenciales ya configurado:

```powershell
$env:RUN_LABEL='mi-diagnostico'
node backend/scripts/k6/run-diagnostic.mjs
```

El destino predeterminado de este diagnóstico es Render; `BASE_URL` permite probar un backend local autorizado con la misma carga. Busca k6 en `C:\Program Files\k6\k6.exe`; se puede sustituir con `K6_PATH`. Guarda los resultados en `backend/stress-results/<RUN_LABEL>/`. Las rutas que fallan en preflight aparecen en `evidence.json` y se excluyen de carga: deben revisarse, no contarse como aprobadas.

Primero ejecuta ocho VUs con identidades distintas y pausas de 3–7 s durante 90 s. Luego intenta mesetas de 5, 10, 20, 40 y 80 solicitudes/s, 45 s cada una, y recuperación a 2/s durante 60 s. Detiene la escalada al encontrar errores/429, iteraciones descartadas o p95 >10 s; un objetivo no alcanzado no mide capacidad. Cada escenario k6 también tiene aborto por >5 % de fallos de servidor o >10 % de 429. El objetivo p95 <2 s es un criterio de esta prueba, no un SLA acordado.

Para comprobar una carga menor durante tres minutos, ejecutar por separado con otro `RUN_LABEL`:

```powershell
$env:DIAGNOSTIC_MODE='soak'
$env:SOAK_RPS='1'
$env:SOAK_DURATION='180s'
$env:RUN_LABEL='mi-diagnostico/soak'
node backend/scripts/k6/run-diagnostic.mjs
```

La llegada por segundo reutiliza las ocho identidades; los VUs adicionales son trabajadores sintéticos y no personas distintas. `business_requests` separa negocio de `operational_requests`; `http_reqs` cuenta respuestas registradas. En abortos puede haber solicitudes interrumpidas sin respuesta/medición y `dropped_iterations` que nunca se enviaron. No sumarlas como operaciones completadas. Los logins/preflight del runner se cuentan aparte en `runnerRequests`. El runner cierra únicamente las sesiones que creó, con alcance `local`.

`inspect-feed.mjs` consulta la definición SQL viva y obtiene EXPLAIN ANALYZE de la lectura bajo `authenticated`, con RLS y una transacción READ ONLY que revierte al terminar. Usa el maestro de diagnóstico ID 12; `PROFILE_USER_ID` permite seleccionar otro actor autorizado y `PROFILE_FAMILY_SCOPE=1` resuelve su alumno o primer hijo para medir la misma consulta del portal familiar. `inspect-dependency.mjs` requiere `TEST_USERNAME`/`TEST_PASSWORD` de ese maestro de Big School y realiza una tanda acotada de lecturas RPC directas para obtener el código SQL oculto por el 503 público. Admite `DEPENDENCY_CONCURRENCY` de 1 a 8. Estos dos inspectores guardan evidencia bajo `2026-10-20` o `RUN_LABEL`; no cambian funciones, políticas, límites ni datos académicos. Evitar ejecutarlos a la vez que una prueba k6 para poder atribuir resultados.

`benchmark-rls-local.mjs --copy-authorized-production-data` compara las respuestas de ocho perfiles en PostgreSQL desechable con una copia autorizada y de solo lectura de las tablas de aplicación. No guarda filas personales en el reporte. Por defecto compara 0053 con 0054; `BENCHMARK_ROLE_QUERIES=1` compara 0055 con 0056 y conserva ambos reportes por separado. Las cifras locales no representan capacidad de Render.
