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

No se ha ejecutado esta nueva prueba contra Render: primero deben desplegarse las migraciones/backend/clientes y prepararse las cuentas independientes necesarias. Los resultados del 17 de octubre permanecen históricos.
