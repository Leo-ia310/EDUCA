# Repetición de k6 y corrección de los 503 — 20 de octubre de 2026

Render se verificó después del despliegue de 3623fc5. Las migraciones 0054, 0055 y 0056 están aplicadas. La nueva admisión de dependencias y la sanitización del portal/adjuntos requieren desplegar el commit f6bd0a7 de main; el resultado de ese despliegue aún no está medido.

## Render: resultados registrados

Ocho identidades autorizadas: administrador/director, maestro, alumno y padre en Big School y EDU360. Las lecturas iniciales cubren 25 rutas distintas; cada preparación hace 8 logins y 88 lecturas. Las escrituras se limitaron a ocho borradores EDU360. Los VUs adicionales reutilizan esas identidades y no representan personas adicionales.

| Escenario | Negocio completado | Fallos | p95 | Descartadas |
|---|---:|---:|---:|---:|
| reads-10rps-summary.json | 82 | 16 | 15.18 s | 64 |
| reads-5rps-summary.json | 226 | 0 | 1.68 s | 0 |
| recovery-2rps-summary.json | 120 | 0 | 2.54 s | 0 |
| roles/soak-5/soak-5rps-summary.json | 480 | 25 | 15.11 s | 36 |
| sessions-8-summary.json | 131 | 0 | 1.58 s | 0 |
| soak/soak-5rps-summary.json | 172 | 13 | 15.51 s | 29 |
| soak-2/soak-2rps-summary.json | 361 | 0 | 1.50 s | 0 |
| writes-summary.json | 91 | 0 | 1.14 s | 0 |

La fase corta de 5/s pasó, pero las dos pruebas sostenidas de 5/s abortaron. La fase de 10/s también abortó. Por ello 5/s no se declara capacidad estable. La prueba de 2/s durante 180 s completó 361 lecturas sin errores ni descartes, p95 1,50 s. Las 91 actualizaciones a objetivo 2/s completaron sin errores, p95 1,14 s. No se validaron 100–200 personas simultáneas.

## Solicitudes

- Respuestas registradas a Render en esta ronda: **2248**.
- Solicitudes de negocio incluidas: **1663**; fallos registrados de negocio: **54**, todos HTTP 503.
- k6 registró 1863 HTTP; 4 corresponden a cierre local de sesiones en Supabase. Los runners añadieron 384 logins/lecturas; hubo cinco verificaciones públicas con respuesta registrada.
- Una verificación manual agotó 20 s sin respuesta registrada. Las ejecuciones abortadas pueden tener solicitudes en vuelo sin medición: el total anterior no es el número exacto de todos los intentos. Las iteraciones descartadas no se enviaron.
- Se cerraron 32 sesiones de lectura creadas por los runners y cuatro sesiones de escritura, con alcance local.

## Hallazgo y correcciones

Los logs de Render aportados por el usuario confirmaron 57014 en dos lecturas del portal del alumno. Los fallos de transporte restantes no contienen un código SQL confirmado. No hubo 429 por cuota en las fases de negocio. La repetición de roles anidados en RLS se optimizó en 0056, manteniendo permisos, revocación, institución y MFA opcional. Se compararon hashes completos de ocho respuestas y 112 combinaciones de autorización antes/después, sin diferencias.

Las consultas del alumno Big School pasaron de 733 a 266 ms en la RPC aislada. Esto no evitó por sí solo la saturación sostenida de Render. Se añadió admisión FIFO por proceso: ocho llamadas compartidas Auth/REST y hasta cuatro consultas SQL, con cola acotada y el plazo existente de 15 s incluyendo espera. SQL adquiere primero su límite propio para dejar capacidad a Auth. Storage conserva su transporte. La cola no cachea autorizaciones. Métricas privadas muestran límites, espera, cancelaciones y rechazos.

También se corrigieron las RPC del portal y la lectura de adjuntos: timeout/dependencia devuelve 503, permiso 403 y validación 400, sin exponer el mensaje SQL interno.

## Backend local con Supabase real: configuración final

| Objetivo | Completadas | Fallos | p95 | Descartadas |
|---|---:|---:|---:|---:|
| 5/s durante 180 s | 855 | 0 | 20.10 s | 46 |
| 2/s durante 180 s | 360 | 0 | 2.13 s | 0 |

A 5/s se evitaron errores de dependencia, pero la espera y los descartes impiden aprobar ese nivel como capacidad. A 2/s no hubo errores ni descartes, aunque p95 2,13 s supera ligeramente el criterio de prueba de 2 s. Estos resultados locales no se presentan como resultados de Render. Se conservaron por separado los ensayos anteriores de configuración.

## Datos, respaldo y validación

- Los ocho borradores creados en Render (123–130) quedaron archivados, verificados por API y SQL; ninguno permanece activo.
- 0056 se aplicó con respaldo privado verificado y SQL de reversión. La comparación transaccional conservó los hashes de alumnos, padres, personas, matrículas, vínculos, horarios, tareas y notas. Tablas públicas sin RLS: 0.
- Respaldo: C:/Users/Maykel/Backups/EDUCA/role-query-fix-2026-10-20T19-03-37-982Z/database-full.dump. SHA256: 58572e542da99f68c829855fa812a3bd2f669d944b17717d862d8d418c06b6d6. Verificación por descompresión completa de pg_restore.
- Build, typecheck, 62 pruebas unitarias y 54 pruebas de integración seleccionadas aprobadas. El cliente Flutter conserva sus 179 pruebas aprobadas y el analizador limpio de la validación anterior.
- Documentación de APIs regenerada. El archivo .env no necesita cambios para utilizar los valores predeterminados.

## Disponibilidad final y trabajo pendiente

Tras inactividad, una verificación de salud agotó 20 s y el siguiente intento tardó 54,57 s en devolver 200. Después curl verificó /health y /ready en aproximadamente 0,5 s, ambos 200 con schemaVersion 53 y assignmentWriteVersion 1. El panel del usuario muestra una instancia gratuita y advierte sobre suspensión por inactividad; es compatible con ese comportamiento, pero no demuestra la causa de cada demora o 503. No se dispone de CPU/RAM ni de todas las métricas internas del proveedor.

Queda desplegar f6bd0a7 del backend en Render y repetir allí la medición. La migración 0056 ya está aplicada. Hasta esa verificación no se aumenta la cifra de capacidad publicada.
