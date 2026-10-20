# Horarios de Big School — propuesta aprobada y aplicada

El usuario aprobó expresamente los 9 cambios y se aplicaron a Supabase junto con las migraciones 0029–0053. Ver [registro de aplicación](MIGRACION_SUPABASE_APLICADA_2026_10_19.md).

Descripción de la propuesta antes de aprobarla: propuesta calculada para eliminar los 13 cruces actuales; no confirma disponibilidad real, recesos ni la jornada autorizada por la escuela.

Se proponen 9 cambios de hora. Se conservan los días, cantidad/duración de las clases, maestros, materias, grupos y aulas. Algunas clases terminan a las 13:00, por lo que hace falta confirmar ese límite con la escuela. No se borra ninguna clase ni se desactiva ninguna protección.

| ID | Día | Grupo | Materia | Actual | Propuesto |
| --- | --- | --- | --- | --- | --- |
| 7 | Miércoles | 1er Grado A | Matemáticas | 10:00–11:30 | 11:30–13:00 |
| 10 | Lunes | 3er Grado A | Matemáticas | 08:00–09:30 | 09:30–11:00 |
| 14 | Martes | 2do Grado A | Lengua y Literatura | 08:00–09:30 | 09:30–11:00 |
| 15 | Jueves | 2do Grado A | Lengua y Literatura | 10:00–11:30 | 08:30–10:00 |
| 20 | Miércoles | 2do Grado A | Ciencias Naturales | 08:00–09:30 | 11:30–13:00 |
| 21 | Viernes | 2do Grado A | Ciencias Naturales | 10:00–11:30 | 08:30–10:00 |
| 23 | Viernes | 3er Grado A | Ciencias Naturales | 10:00–11:30 | 11:30–13:00 |
| 25 | Viernes | 1er Grado A | Estudios Sociales | 10:00–11:30 | 08:30–10:00 |
| 26 | Lunes | 2do Grado A | Estudios Sociales | 08:00–09:30 | 09:30–11:00 |

El archivo `supabase/deploy/scalability-con-propuesta-horarios.sql` contiene esta propuesta y las 25 migraciones en una transacción. Está bloqueado por defecto con `horario_aprobado := false`. Si se aprueban estos horarios, cambiar esa única variable a `true` antes de ejecutarlo completo. Valida los valores anteriores y asignaciones de los 9 bloques; si los datos cambiaron, aborta en vez de sobrescribirlos. Repite la revisión global de horarios antes de migrar. Cualquier error revierte tanto las franjas propuestas como las migraciones.

El SQL original sin correcciones (`scalability-0029-0053.sql`) seguirá rechazando los cruces mientras no se corrijan. El backup previo está en `C:/Users/Maykel/Backups/EDUCA/2026-10-19_21-06-26`.

Para regenerar el paquete bloqueado por defecto: `node backend/scripts/build-scalability-sql.mjs --with-schedule-proposal`. El paquete se conserva para auditoría; no volver a ejecutarlo sobre la base ya actualizada.
