# Prueba de estrés de Nivra en Render — 17 de octubre de 2026

Destino: https://nivra-backend-mcc4.onrender.com. Generador: k6 1.7.1, Windows, desde el equipo local. Zona horaria de los registros: America/Managua (UTC−06:00).

Se probaron cuentas demo EDU360 y las cuatro cuentas facilitadas de BIGSCHOOL. Las claves y los tokens no se incluyen en los artefactos. Las peticiones de negocio atraviesan Render y sus dependencias reales; la carga no se ejecutó dentro de Render.

El límite útil observado depende de la operación: en BIGSCHOOL el escalón de 5 solicitudes/s terminó sin errores, con p95 de 1,85 s; en el de 10 solicitudes/s el p95 subió a 12,53 s. No hay evidencia para afirmar que este despliegue soporte 10 solicitudes/s de esta mezcla con buena respuesta. Esto no se traduce directamente a una cantidad de personas conectadas.

La comprobación sostenida posterior completó 601 peticiones durante 120 s a 5 solicitudes/s, sin errores ni 429. El p95 global fue 1,93 s y el p99, 2,62 s. La ruta de tareas de familia tuvo p95 de 3,29 s: cumplir el umbral global no significa que cada ruta cumpla individualmente.

La prueba HTTP de `/health` completó 41.852 peticiones sin errores, pero alcanzó el tope configurado de 500 VUs y dejó 16.430 iteraciones sin iniciar. No se validaron 1000 solicitudes/s reales. Las escrituras completaron 90 actualizaciones de tareas a 2 solicitudes/s, sin errores, con p95 de 1,91 s; las ocho tareas temporales se archivaron y su ausencia del listado se verificó.

| Cuenta BIGSCHOOL | Rol comprobado |
|---|---|
| Pablo | student |
| Osmar | teacher |
| Ernesto | director |
| Maikel | parent |

## Resultados

| Perfil | Peticiones de carga completadas | Fallos | p50 ms | p95 ms | p99 ms | Iteraciones no iniciadas |
|---|---:|---:|---:|---:|---:|---:|
| EDU360: subida de lecturas | 622 | 9.97% | 2608.69 | 15000.35 | 15001.02 | 144 |
| BIGSCHOOL: subida de lecturas | 519 | 8.09% | 1443.55 | 11364.74 | 15000.65 | 41 |
| BIGSCHOOL: 5 solicitudes/s durante 120 s | 601 | 0.00% | 795.64 | 1926.49 | 2623.66 | 0 |
| EDU360: tareas, 2 escrituras/s | 90 | 0.00% | 1641.17 | 1910.14 | 2093.51 | 0 |
| BIGSCHOOL: 1 login/s durante 30 s | 30 | 0.00% | 953.79 | 1090.43 | 1095.01 | 0 |
| HTTP /health: subida hasta objetivo 1000/s | 41852 | 0.00% | 996.32 | 1361.99 | 1593.42 | 16430 |

Los resúmenes de carga usan métricas personalizadas que excluyen el inventario y la autenticación inicial. `http_reqs` incluye esas solicitudes adicionales. Un timeout se cuenta como fallo HTTP 0. Las mesetas son cortas y no equivalen a una prueba prolongada de estabilidad.

## Escalones: reads.json

| Escalón | Respuestas completadas | Fallos | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| ramp_5 | 54 | 0.00% | 1841.35 | 1966.09 |
| hold_5 | 151 | 0.00% | 1983.27 | 2364.35 |
| ramp_10 | 53 | 0.00% | 3331.95 | 4083.00 |
| hold_10 | 214 | 2.34% | 12891.56 | 14981.18 |
| ramp_20 | 66 | 27.27% | 15000.91 | 15001.06 |
| hold_20 | 84 | 46.43% | 15001.05 | 15003.11 |

Los escalones de negocio tienen objetivos de 5, 10, 20 y 40 solicitudes/s; cada meseta dura 30 s si no se activa el aborto. Los grupos se asignan al completar cada petición, por lo que una respuesta pendiente puede pasar al siguiente escalón. El objetivo configurado no es el rendimiento alcanzado.

| Rutas con mayor p95 | p95 ms |
|---|---:|
| /api/family/assignments | 15001.16 |
| /api/family/children | 15000.92 |
| /api/chats/conversations/:conversationId/messages | 15000.92 |
| /api/assignments/teacher | 15000.88 |
| /api/schedules/mine | 15000.54 |
| /api/family/attendance | 15000.45 |
| /api/chats/conversations | 15000.31 |
| /api/attendance/class/:classId | 15000.19 |
| /api/payments/mine | 14915.45 |
| /api/reports/report-cards/preview | 14227.06 |

## Escalones: bigschool-reads.json

| Escalón | Respuestas completadas | Fallos | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| ramp_5 | 54 | 0.00% | 1942.64 | 2062.53 |
| hold_5 | 152 | 0.00% | 1845.99 | 2509.05 |
| ramp_10 | 58 | 0.00% | 1928.91 | 2949.41 |
| hold_10 | 214 | 8.41% | 12532.27 | 15000.78 |
| ramp_20 | 41 | 58.54% | 15000.47 | 15000.91 |

Los escalones de negocio tienen objetivos de 5, 10, 20 y 40 solicitudes/s; cada meseta dura 30 s si no se activa el aborto. Los grupos se asignan al completar cada petición, por lo que una respuesta pendiente puede pasar al siguiente escalón. El objetivo configurado no es el rendimiento alcanzado.

| Rutas con mayor p95 | p95 ms |
|---|---:|
| /api/family/assignments | 15000.84 |
| /api/schedules/mine | 12846.28 |
| /api/chats/conversations | 12482.16 |
| /api/chats/conversations/:conversationId/messages | 12065.36 |
| /api/attendance/class/:classId | 12032.54 |
| /api/family/children | 11725.54 |
| /api/assignments/teacher | 11228.86 |
| /api/family/attendance | 10966.27 |
| /api/grades/periods | 9392.59 |
| /api/payments/concepts | 9328.94 |

## Escalones: health.json

| Escalón | Respuestas completadas | Fallos | p95 ms | p99 ms |
|---|---:|---:|---:|---:|
| warmup | 526 | 0.00% | 131.43 | 179.21 |
| 50 | 1001 | 0.00% | 131.29 | 184.79 |
| 100 | 2744 | 0.00% | 129.66 | 150.44 |
| 200 | 5488 | 0.00% | 206.20 | 234.35 |
| 500 | 12137 | 0.00% | 1296.46 | 1539.68 |
| 1000 | 14076 | 0.00% | 1454.07 | 1682.97 |
| recovery | 5880 | 0.00% | 1354.57 | 1378.51 |

Los objetivos HTTP suben por 50, 100, 200, 500 y 1000 peticiones/s, con 20 s de meseta y transiciones intermedias. Salvo el grupo 50, cada etiqueta incluye la subida de 10 s anterior a su meseta. Revisar iteraciones no iniciadas: alcanzar el objetivo configurado no garantiza generar esa carga.

## Cobertura previa a la carga: reads.log

| Método | Ruta | Resultado |
|---|---|---|
| POST | /api/assignments/teacher-classes | 200 |
| GET | /api/portal-access/me | 200 |
| GET | /api/portal-access/config | 200 |
| GET | /api/portal-access/grades | 200 |
| GET | /api/auth/2fa/status | 200 |
| GET | /api/admin/institutions | 200 |
| GET | /api/admin/users | 200 |
| GET | /api/admin/directory | 200 |
| GET | /api/admin/permissions/catalog | 200 |
| GET | /api/admin/profiles | 200 |
| GET | /api/admin/roles | 400 — db_error |
| GET | /api/admin/students | 200 |
| GET | /api/admin/teachers | 200 |
| GET | /api/admin/parents | 200 |
| GET | /api/collaborations | 200 |
| GET | /api/family/children | 200 |
| GET | /api/family/attendance | 200 |
| GET | /api/family/assignments | 200 |
| GET | /api/payments/mine | 200 |
| GET | /api/assignments/teacher | 200 |
| GET | /api/attendance/summary | 200 |
| GET | /api/chats/conversations | 200 |
| GET | /api/chats/contacts | 200 |
| GET | /api/events/announcements | 200 |
| GET | /api/grades/scales/default | 200 |
| GET | /api/grades/periods | 200 |
| GET | /api/grades/gradebook | 200 |
| GET | /api/files | 400 — db_error |
| GET | /api/reports/report-cards | 200 |
| GET | /api/reports/report-cards/preview | 200 |
| GET | /api/notifications/preferences | 200 |
| GET | /api/notifications | 200 |
| GET | /api/schedules | 200 |
| GET | /api/schedules/mine | 200 |
| GET | /api/sync/queue | 200 |
| GET | /api/sync/changes | 400 — db_error |
| GET | /api/payments/summary | 200 |
| GET | /api/payments/concepts | 200 |
| GET | /api/payments/charges | 200 |
| GET | /api/developer/summary | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/institutions | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/users | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/audit-events | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/modules | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/apis | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/tasks | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/feature-flags | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/system-checks | Requires developer account; institutional admin is insufficient |
| GET | /api/attendance/class/:classId | 200 |
| GET | /api/attendance/groups/:groupId | 200 |
| GET | /api/assignments/:id/submissions | 200 |
| GET | /api/chats/conversations/:conversationId/messages | 200 |
| GET | /api/files/:id/download-url | No matching fixture |
| GET | /api/payments/charges/:chargeId | 200 |
| GET | /api/reports/report-cards/:id | No matching fixture |

### Fixtures y recuperación: reads.log

```text
RECOVERY {"status":200,"ms":212.5478}
```

## Cobertura previa a la carga: bigschool-reads.log

| Método | Ruta | Resultado |
|---|---|---|
| POST | /api/assignments/teacher-classes | 200 |
| GET | /api/portal-access/me | 200 |
| GET | /api/portal-access/config | 200 |
| GET | /api/portal-access/grades | 200 |
| GET | /api/auth/2fa/status | 200 |
| GET | /api/admin/institutions | 200 |
| GET | /api/admin/users | 200 |
| GET | /api/admin/directory | 200 |
| GET | /api/admin/permissions/catalog | 200 |
| GET | /api/admin/profiles | 200 |
| GET | /api/admin/roles | 400 — db_error — column roles.updated_at does not exist |
| GET | /api/admin/students | 200 |
| GET | /api/admin/teachers | 200 |
| GET | /api/admin/parents | 200 |
| GET | /api/collaborations | 200 |
| GET | /api/family/children | 200 |
| GET | /api/family/attendance | 200 |
| GET | /api/family/assignments | 200 |
| GET | /api/payments/mine | 200 |
| GET | /api/assignments/teacher | 200 |
| GET | /api/attendance/summary | 200 |
| GET | /api/chats/conversations | 200 |
| GET | /api/chats/contacts | 200 |
| GET | /api/events/announcements | 200 |
| GET | /api/grades/scales/default | 200 |
| GET | /api/grades/periods | 200 |
| GET | /api/grades/gradebook | 200 |
| GET | /api/files | 400 — db_error — column files.updated_at does not exist |
| GET | /api/reports/report-cards | 200 |
| GET | /api/reports/report-cards/preview | 200 |
| GET | /api/notifications/preferences | 200 |
| GET | /api/notifications | 200 |
| GET | /api/schedules | 200 |
| GET | /api/schedules/mine | 200 |
| GET | /api/sync/queue | 200 |
| GET | /api/sync/changes | 400 — db_error — column change_log.changed_at does not exist |
| GET | /api/payments/summary | 200 |
| GET | /api/payments/concepts | 200 |
| GET | /api/payments/charges | 200 |
| GET | /api/developer/summary | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/institutions | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/users | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/audit-events | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/modules | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/apis | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/tasks | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/feature-flags | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/system-checks | Requires developer account; institutional admin is insufficient |
| GET | /api/attendance/class/:classId | 200 |
| GET | /api/attendance/groups/:groupId | 200 |
| GET | /api/assignments/:id/submissions | 200 |
| GET | /api/chats/conversations/:conversationId/messages | 200 |
| GET | /api/files/:id/download-url | No matching fixture |
| GET | /api/payments/charges/:chargeId | 200 |
| GET | /api/reports/report-cards/:id | 200 |

### Fixtures y recuperación: bigschool-reads.log

```text
RECOVERY {"status":200,"ms":115.0856}
```

## Cobertura previa a la carga: bigschool-soak.log

| Método | Ruta | Resultado |
|---|---|---|
| POST | /api/assignments/teacher-classes | 200 |
| GET | /api/portal-access/me | 200 |
| GET | /api/portal-access/config | 200 |
| GET | /api/portal-access/grades | 200 |
| GET | /api/auth/2fa/status | 200 |
| GET | /api/admin/institutions | 200 |
| GET | /api/admin/users | 200 |
| GET | /api/admin/directory | 200 |
| GET | /api/admin/permissions/catalog | 200 |
| GET | /api/admin/profiles | 200 |
| GET | /api/admin/roles | 400 — db_error — column roles.updated_at does not exist |
| GET | /api/admin/students | 200 |
| GET | /api/admin/teachers | 200 |
| GET | /api/admin/parents | 200 |
| GET | /api/collaborations | 200 |
| GET | /api/family/children | 200 |
| GET | /api/family/attendance | 200 |
| GET | /api/family/assignments | 200 |
| GET | /api/payments/mine | 200 |
| GET | /api/assignments/teacher | 200 |
| GET | /api/attendance/summary | 200 |
| GET | /api/chats/conversations | 200 |
| GET | /api/chats/contacts | 200 |
| GET | /api/events/announcements | 200 |
| GET | /api/grades/scales/default | 200 |
| GET | /api/grades/periods | 200 |
| GET | /api/grades/gradebook | 200 |
| GET | /api/files | 400 — db_error — column files.updated_at does not exist |
| GET | /api/reports/report-cards | 200 |
| GET | /api/reports/report-cards/preview | 200 |
| GET | /api/notifications/preferences | 200 |
| GET | /api/notifications | 200 |
| GET | /api/schedules | 200 |
| GET | /api/schedules/mine | 200 |
| GET | /api/sync/queue | 200 |
| GET | /api/sync/changes | 400 — db_error — column change_log.changed_at does not exist |
| GET | /api/payments/summary | 200 |
| GET | /api/payments/concepts | 200 |
| GET | /api/payments/charges | 200 |
| GET | /api/developer/summary | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/institutions | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/users | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/audit-events | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/modules | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/apis | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/tasks | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/feature-flags | Requires developer account; institutional admin is insufficient |
| GET | /api/developer/system-checks | Requires developer account; institutional admin is insufficient |
| GET | /api/attendance/class/:classId | 200 |
| GET | /api/attendance/groups/:groupId | 200 |
| GET | /api/assignments/:id/submissions | 200 |
| GET | /api/chats/conversations/:conversationId/messages | 200 |
| GET | /api/files/:id/download-url | No matching fixture |
| GET | /api/payments/charges/:chargeId | 200 |
| GET | /api/reports/report-cards/:id | 200 |

### Fixtures y recuperación: bigschool-soak.log

```text
RECOVERY {"status":200,"ms":113.1505}
```

## Cobertura previa a la carga: writes.log

| Método | Ruta | Resultado |
|---|---|---|
| POST | /api/assignments/teacher-classes | 200 |

### Fixtures y recuperación: writes.log

```text
FIXTURES [{"id":"77","title":"K6-STRESS-1792255877327-0"},{"id":"78","title":"K6-STRESS-1792255878947-1"},{"id":"79","title":"K6-STRESS-1792255880526-2"},{"id":"80","title":"K6-STRESS-1792255882083-3"},{"id":"81","title":"K6-STRESS-1792255883514-4"},{"id":"82","title":"K6-STRESS-1792255885208-5"},{"id":"83","title":"K6-STRESS-1792255886744-6"},{"id":"84","title":"K6-STRESS-1792255888209-7"}]
CLEANUP {"id":"77","status":200,"softDelete":true}
CLEANUP {"id":"78","status":200,"softDelete":true}
CLEANUP {"id":"79","status":200,"softDelete":true}
CLEANUP {"id":"80","status":200,"softDelete":true}
CLEANUP {"id":"81","status":200,"softDelete":true}
CLEANUP {"id":"82","status":200,"softDelete":true}
CLEANUP {"id":"83","status":200,"softDelete":true}
CLEANUP {"id":"84","status":200,"softDelete":true}
CLEANUP_VERIFIED {"status":200,"remaining":[],"verified":true}
RECOVERY {"status":200,"ms":113.4135}
```

### Fixtures y recuperación: login.log

```text
RECOVERY {"status":200,"ms":126.5619}
```

## Interpretación y límites

- El resultado de `/health` mide HTTP sin acceso a Supabase. No debe extrapolarse a usuarios, notas, tareas ni pagos.
- Las pruebas de negocio usan cuatro cuentas y una mezcla equilibrada por rol, sin pausas entre iteraciones. VUs son trabajadores de carga, no personas reales conectadas.
- Se conserva el rate limiting real. Un 429 señala cuotas, no demuestra saturación. Los timeouts de negocio con `/health` disponible sugieren revisar la ruta de datos y sus dependencias; sin telemetría de Render/Supabase no se puede atribuir el cuello de botella a CPU, RAM o base de datos.
- Se aborta con más del 10% de fallos de servidor acumulados o más del 5% de respuestas 429 en negocio; `/health` aborta con más del 20% de fallos. Los umbrales de servicio usados son menos del 1% de errores y p95 menor de 2 s.
- Las rutas que ya fallaron durante el inventario se excluyeron del tráfico repetido; los errores de validación iniciales no son fallos de capacidad. Las primeras ejecuciones del generador con cuerpo JSON null en GET se descartaron.
- Escrituras de carga: actualización de ocho tareas borrador temporales en EDU360, con borrado lógico y comprobación posterior. No se ejecutaron escrituras masivas de notas, asistencia, pagos, chats, anuncios, 2FA ni archivos; tampoco se probó la generación masiva de boletines. Las rutas developer requieren una cuenta de ese rol. Por ello, esta ejecución no certifica todas las operaciones de la API.
- Los logins iniciales de Pablo y Osmar sufrieron timeout durante la recuperación de la carga demo; ambos funcionaron al repetirlos tras recuperar el servicio. No fueron fallos de contraseña. La comprobación sostenida también encontró temporalmente un 429 por IP al preparar las sesiones; se respetó Retry-After antes de repetirla.

## Trabajo recomendado según los hallazgos

1. Corregir la correspondencia entre consultas y migraciones para `roles.updated_at`, `files.updated_at` y `change_log.changed_at`; los tres errores ocurrieron antes de aplicar carga.
2. Repetir la zona de 5–10 solicitudes/s observando CPU, RAM y latencia de dependencias en Render/Supabase. Los datos de esta ejecución ubican la degradación, pero no identifican por sí solos el recurso agotado.
3. Perfilar las rutas de tareas, familia, horarios y chat, junto con el coste de validar autenticación y permisos por petición. Priorizar las consultas repetidas y la cantidad de viajes a Supabase antes de aumentar indiscriminadamente los VUs.

## Repetición

Ver `backend/scripts/k6/README.md`. Los scripts admiten credenciales por entorno. No guardar claves en código ni habilitar HTTP debug. Ejecutar cada perfil por separado y dejar recuperar el servicio entre cargas.

Referencia de metodología: [Grafana k6 — executors de llegada constante](https://grafana.com/docs/k6/latest/using-k6/scenarios/executors/constant-arrival-rate/) y [umbrales](https://grafana.com/docs/k6/latest/using-k6/thresholds/).
