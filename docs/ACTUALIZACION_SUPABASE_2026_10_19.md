# Preparación de actualización de Supabase — 19 de octubre de 2026

**Estado actualizado:** las migraciones 0029–0053 y los 9 cambios de horarios autorizados ya se aplicaron a Supabase. Backend local `/ready`: 200, contrato 53. Publicación de backend en Render/Edge/clientes pendiente. Ver [registro de aplicación](MIGRACION_SUPABASE_APLICADA_2026_10_19.md). Las referencias siguientes a pendientes describen el estado previo o el procedimiento para otros destinos.

## Causa del error local

El backend en localhost:3001 responde 200 a `/health` y 503 a `/ready`. La base configurada no tiene `backend_request_context`, `backend_readiness_v1`, `admin_people_page` ni `chat_send_message`. El frontend/backend nuevo no es compatible con ese esquema anterior. La revisión se hizo mediante consultas de solo lectura; no se aplicaron migraciones remotas.

El 2FA sigue siendo opcional. Una cuenta sin configuración de 2FA o con `enabled=false` debe poder usar la aplicación; únicamente una cuenta que lo activó necesita verificar su segundo factor. No hay ninguna instrucción en el paquete para activar 2FA masivamente.

## Archivos preparados

- `supabase/deploy/scalability-0029-0053.sql`: las 25 migraciones completas, transacción única, guardas iniciales, revisión de horarios, verificación final del contrato 53 y recarga del esquema PostgREST.
- `supabase/deploy/revisar-horarios.sql`: consulta de solo lectura con institución, horarios, grupos, materias, aulas y motivos de cada cruce.
- `backend/scripts/build-scalability-sql.mjs`: generador sin conexión ni credenciales, con SHA256 de cada migración incluida.

No ejecutar el paquete directamente en una base distinta o con migraciones parcialmente aplicadas. La comprobación de baseline y del marcador evita algunos usos incorrectos, pero no sustituye el historial real. La base revisada no tiene tabla de historial en `supabase_migrations`; el paquete no inventa que las migraciones anteriores estén registradas.

## Bloqueo concreto: horarios de Big School

Se encontraron 13 pares incompatibles, todos en institución 2 y año académico ID 2. `weekday_id` conserva el identificador del catálogo; cada par tiene el mismo día y la misma franja indicados.

| Día ID | Horario | Bloques | Grupos | Motivo |
| --- | --- | --- | --- | --- |
| 1 | 08:00–09:30 | 8 / 26 | 2do A / 2do A | Grupo y aula; Matemáticas / Estudios Sociales |
| 1 | 08:00–09:30 | 10 / 28 | 3er A / 3er A | Grupo, maestro y aula; Matemáticas / Estudios Sociales |
| 1 | 08:00–09:30 | 24 / 26 | 1er A / 2do A | Mismo maestro de Estudios Sociales |
| 2 | 08:00–09:30 | 14 / 16 | 2do A / 3er A | Mismo maestro de Lengua y Literatura |
| 3 | 10:00–11:30 | 7 / 9 | 1er A / 2do A | Mismo maestro de Matemáticas |
| 3 | 08:00–09:30 | 20 / 22 | 2do A / 3er A | Mismo maestro de Ciencias Naturales |
| 4 | 10:00–11:30 | 15 / 17 | 2do A / 3er A | Mismo maestro de Lengua y Literatura |
| 5 | 10:00–11:30 | 19 / 25 | 1er A / 1er A | Grupo y aula; Ciencias Naturales / Estudios Sociales |
| 5 | 10:00–11:30 | 21 / 23 | 2do A / 3er A | Mismo maestro de Ciencias Naturales |
| 5 | 10:00–11:30 | 21 / 27 | 2do A / 2do A | Grupo y aula; Ciencias Naturales / Estudios Sociales |
| 5 | 10:00–11:30 | 21 / 29 | 2do A / 3er A | Mismo maestro; Ciencias Naturales / Estudios Sociales |
| 5 | 10:00–11:30 | 23 / 29 | 3er A / 3er A | Grupo, maestro y aula; Ciencias Naturales / Estudios Sociales |
| 5 | 10:00–11:30 | 25 / 27 | 1er A / 2do A | Mismo maestro de Estudios Sociales |

Son conflictos de datos existentes, no problemas que deban arreglarse borrando horarios al migrar. Hace falta confirmar el horario correcto o la asignación docente con el responsable. Cambiar un maestro de clase puede afectar varios bloques. Repetir ambas comprobaciones de `backend/scripts/schedules-preflight.sql` después de corregir: las dos deben devolver cero filas.

## Ejecución cuando los horarios estén resueltos

1. Disponer de backup recuperable y detener escritores/workers antiguos. Seguir el orden completo de `DESPLIEGUE_ESCALABILIDAD.md`, incluida la actualización de clientes y funciones Edge.
2. Abrir SQL Editor de Supabase, pegar todo `scalability-0029-0053.sql` y ejecutarlo como postgres. No ejecutar fragmentos por separado. Si sigue habiendo conflictos, se detendrá antes de aplicar las migraciones y mostrará IDs/motivos.
3. Confirmar resultado `schema_version=53`. Si falla, ejecutar `ROLLBACK` si la conexión queda en transacción abortada; investigar el error antes de repetir.
4. Reiniciar el backend compatible, comprobar `/ready` 200 y recargar la app. Si la sesión guardada tiene un refresh token inválido, volver a iniciar sesión; no activar 2FA como solución al error de esquema.

La aplicación local seguirá devolviendo errores de dependencia hasta completar una actualización compatible o arrancar una versión anterior compatible. Esta preparación no se presenta como una reparación remota ya aplicada. Los proveedores gestionados y la base real requieren las comprobaciones posteriores al despliegue; la prueba automática usa PostgreSQL local con el esquema del repositorio y datos sintéticos.
