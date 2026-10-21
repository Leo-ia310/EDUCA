# Estrés de Render y diagnóstico de 503 — 20 de octubre de 2026

**Se reprodujeron errores 503. La consulta de tareas y sus verificaciones RLS presentan un cuello de botella medido en Supabase. No se demostró capacidad para carga alta.**

Destino: `https://nivra-backend-mcc4.onrender.com`. Herramienta de carga: k6 1.7.1. Ocho cuentas distintas: administrador/director, maestro, alumno y padre de Big School y EDU360. El backend respondió `/ready` con contrato SQL 53 antes y después de las pruebas. Este contrato no identifica el SHA del código desplegado.

## Resultados de k6

Las cifras de solicitudes y porcentajes corresponden a respuestas registradas. p95 significa que el 95 % de esas respuestas tardó ese tiempo o menos; no incorpora solicitudes interrumpidas por aborto.

| Escenario | Carga de negocio completada | 503 | p95 | p99 | Resultado |
|---|---:|---:|---:|---:|---|
| 8 cuentas simultáneas, pausas de 3–7 s, 90 s | 121 | 0 | 2,42 s | 3,66 s | Sin errores; incumple el objetivo p95 <2 s |
| Objetivo 5 solicitudes/s, meseta prevista de 45 s | 60 | 3 (5 %) | 9,10 s | 15,34 s | Abortó a los 26 s; 20 iteraciones descartadas |
| Recuperación, objetivo 2 solicitudes/s, 60 s | 120 | 2 (1,67 %) | 8,56 s | 10,13 s | Persistieron fallos puntuales de tareas |
| Escrituras EDU360, objetivo 2 actualizaciones/s | 3 | 3 | 10,27 s | 10,31 s | Abortó; muestra pequeña, 7 iteraciones descartadas |
| Lecturas sostenidas, objetivo 1 solicitud/s, 180 s | 181 | 0 | 3,70 s | 6,24 s | Sin errores ni iteraciones descartadas; sigue lento |

El escenario de 5/s completó aproximadamente 2,31 operaciones/s antes del aborto. El de recuperación completó 1,95/s y el sostenido 0,99/s, incluyendo su drenaje final. No se alcanzaron las etapas de 10, 20, 40 y 80/s: se detuvo la escalada al aparecer fallos. El escenario de escritura incluye setup/limpieza en su duración total; no interpretar su tasa global como rendimiento sostenido de escritura.

No hubo 429, 401 ni 403 en las respuestas de carga registradas. Los 503 capturados fueron `database_unavailable`, no `server_busy` ni `server_draining`. Por ejemplo, un fallo tenía cuota restante 1167: no fue agotamiento de esa cuenta. Los VUs sintéticos adicionales de los escenarios de llegada reutilizan las ocho identidades; no representan personas adicionales.

Las dos pasadas de preflight completaron 192 solicitudes: 16 logins y 176 lecturas, todas en 200. Se comprobaron 25 rutas distintas, con parámetros/roles adecuados: directorio de alumnos/padres/clases, perfiles, roles, horarios, pagos, períodos/escalas, boletines, tareas, sincronización, notificaciones, chats, anuncios, acceso y consultas de familia.

## Causa investigada

1. Los GET de tareas de maestro y alumno fallaron en ambos colegios durante la carga. En la etapa 5/s tardaron unos 15,3 s y devolvieron `database_unavailable`; durante recuperación hubo fallos de unos 8,6 s.
2. Se aisló la dependencia con lecturas directas de `assignment_feed`, usando una sesión autorizada de maestro y conservando RLS. Cuatro consultas simultáneas respondieron en 200, pero tardaron 7,72–8,62 s. Una segunda tanda acotada de ocho consultas simultáneas falló **8/8** con SQL **57014**, `canceling statement due to statement timeout`, tras 8,86–9,16 s. Son tandas independientes del tráfico k6, no solicitudes adicionales a Render durante esa prueba.
3. El backend traduce estos errores operativos SQL a `503 database_unavailable`. Esto confirma una causa reproducible de esos 503; no demuestra que todos los 503 históricos tengan el mismo origen. Para correlacionar cada fallo público con su error interno faltan logs de Render/Supabase.
4. `EXPLAIN ANALYZE` de la función viva, en una transacción READ ONLY con rol `authenticated` y RLS activo, midió **2708 ms de ejecución SQL**, sin tráfico k6 simultáneo. El resultado contenía solo cuatro tareas. Hubo **55 699 accesos a bloques en caché y cero lecturas de disco** en esa ejecución.
5. El plan de la consulta interna, sin modificar la función desplegada, midió 2279 ms. Entre sus puntos costosos estaban `classes` con `teacher_class_read` (~575 ms), `enrollments` con `teacher_group_read` (~601 ms acumulados), `students` con `teacher_student_read` (~281 ms acumulados), y comprobaciones de `submissions` (~687 ms acumulados). Estos tiempos de nodos pueden incluir trabajo anidado: no sumarlos como costes independientes. Hay índices utilizados; no es evidencia de que falte simplemente un índice.
6. JIT ya estaba desactivado. Repetir el plan con `SET LOCAL jit=off` no mejoró sustancialmente la ejecución. No se cambió la configuración persistente de Supabase.

La evidencia apunta a trabajo repetido de autorización por fila y consultas anidadas en el feed. No se midieron CPU/RAM de Render ni de Supabase; no se dispone localmente del secreto de métricas internas o de credenciales del proveedor para esos paneles. No se atribuye el fallo a falta de RAM, caída del proceso o un plan concreto de Render.

IDs de solicitudes útiles para buscar logs:

- Maestro Big School: `d0d97721-ce3c-4649-b963-be039240f516`.
- Alumno Big School: `1ae98c75-2f78-4c7d-a9a3-2050a327900a`.
- Maestro EDU360: `c94f41a4-b542-45ee-b68a-b3c8cbb55628`.
- Escritura EDU360: `531bc295-16ea-47a8-9338-117eeb881fc1`.

## Escrituras y limpieza

Solo se crearon ocho tareas **borrador, no publicadas, en EDU360**, IDs 107–114. No se crearon alumnos, padres, cobros, mensajes ni anuncios. Big School no recibió escrituras de datos académicos; los logins y las cuotas de solicitudes sí cambian metadatos de sesión como parte del uso normal.

Los ocho borradores desaparecieron del listado tras la limpieza. La comprobación SQL posterior confirmó institución 1, `published=false` y `deleted_at` establecido en los ocho. Se conservan archivados según el contrato de borrado lógico.

Los ocho recibieron al menos una actualización de la carga, aunque no se registró ninguna respuesta exitosa de actualización: tres respuestas fueron 503 y hubo otras solicitudes interrumpidas. **Un 503 o una desconexión no garantiza que la escritura se haya revertido.** El servicio realiza la actualización antes de hidratar la respuesta, con varias consultas posteriores. No se puede asignar cada cambio a una respuesta concreta con este registro; debe investigarse la confirmación de escritura y el comportamiento de reintentos/idempotencia.

Los dos recorridos del runner cerraron sus 16 sesiones nuevas con alcance `local`. También se cerraron las dos sesiones de aislamiento de Supabase. El perfil histórico `backend.js` de escrituras no implementa cierre de sus cuatro sesiones de login; no se ejecutó logout global sobre usuarios reales.

## Conteo de solicitudes

- **605 solicitudes HTTP registradas por k6**, de las cuales **485 son operaciones de carga de negocio** y 120 son sondas/setup/limpieza.
- 192 solicitudes adicionales de login/preflight del runner y 2 logins de aislamiento: **799 respuestas registradas al backend dentro del diagnóstico automatizado**.
- Más 2 sondas iniciales y 2 sondas finales `/health`/`/ready`: **803 solicitudes completadas registradas a Render en este diagnóstico**.
- Separadamente, 12 lecturas RPC directas y 18 cierres locales de sesión: **30 solicitudes HTTP a Supabase**, fuera de la cifra de Render. No incluyen las llamadas internas que el backend hace a Supabase ni las consultas por conexión PostgreSQL.
- **8 respuestas 503 registradas por k6**. Los 8 errores directos de Supabase de la tanda de aislamiento se cuentan aparte.

Las peticiones interrumpidas al abortar pueden haber llegado al servidor sin producir una muestra HTTP completa. Por tanto, 803 no es un conteo exacto de todos los intentos recibidos por Render. Las 27 iteraciones descartadas por los generadores nunca se enviaron y tampoco se suman. Los porcentajes anteriores usan únicamente respuestas completadas de cada escenario.

## Capacidad que sí se puede afirmar y siguientes pasos

Se observaron ocho cuentas en recorridos ligeros sin errores y una mezcla de lecturas a ~1/s durante tres minutos sin errores. Aun así, p95 superó 2 s. La mezcla a objetivo 5/s falló, la recuperación a 2/s tuvo errores y ocho consultas de tareas simultáneas agotaron el tiempo de SQL. **No hay base para prometer 50, 100 o 1000 usuarios ni para fijar un máximo universal de personas.** Estos resultados dependen del recorrido, las pausas, el volumen de datos y las ráfagas.

Prioridad de trabajo:

1. Reducir las evaluaciones repetidas de permisos/ámbito dentro de `assignment_feed` y sus políticas, conservando aislamiento institucional, roles, colaboración, visibilidad y 2FA opcional. Validar con pruebas de permisos y el mismo plan SQL.
2. Revisar el camino de escritura e hidratación para reducir consultas y resolver la confirmación ambigua de cambios ante un timeout; comprobar reintentos y atomicidad con fixtures.
3. Correlacionar `requestId`, código SQL y duración de dependencia en observabilidad interna, sin exponer SQL ni credenciales al cliente.
4. Repetir exactamente estos escenarios tras corregir, y solo entonces escalar a las etapas superiores y realizar una prueba de mayor duración con recursos del proveedor observados.

No se modificaron APIs, funciones SQL, políticas RLS, límites ni variables de entorno desplegadas. Se añadieron herramientas/evidencia de diagnóstico y se corrigieron dos rutas obsoletas en el script de sesiones existente. No se hizo commit ni push. El APK que ya tenía cambios locales se conservó.

Evidencia: `totals.json`, los cinco `*-summary.json`, sus logs, los dos `evidence.json`, `dependency-isolation*.json`, `feed-explain.json`, `write-cleanup-db.json` y `final-health.json`. Los resultados no guardan contraseñas, tokens ni respuestas de datos personales. Al terminar, `/health` y `/ready` volvieron a responder 200 y `/ready` confirmó versión 53.
