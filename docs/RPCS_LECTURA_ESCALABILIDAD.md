# Contratos de lectura en Supabase

Las siguientes funciones se invocan mediante Supabase RPC con el JWT del usuario. No son rutas nuevas de Express. Aplicar las migraciones antes de publicar el frontend que las consume.

| Migración | RPC | Entrada | Salida |
| --- | --- | --- | --- |
| 0030 | `payment_charge_totals` | `p_charge_ids: bigint[]` (máximo 200) | Filas `{ charge_id, paid }`; solo cargos autorizados. La suma incluye todos los abonos, independientemente del límite de filas de PostgREST. |
| 0030 | `payment_collection_summary` | Ninguna | Resumen de recaudación, mora y estados; `byCurrency` conserva resúmenes separados por moneda. Administración con `payments.view`. |
| 0031 | `dashboard_attendance_pct` | `p_student_id?: bigint` | Porcentaje de presentes (`PRE`) del año actual. Sin alumno requiere administración con `dashboard.view`; con alumno exige alcance y permiso de asistencia. |
| 0031 | `dashboard_institutional_average` | Ninguna | Promedio institucional del año actual en escala 0–10, respetando RLS de notas. |
| 0031 | `dashboard_student_average` | `p_student_id: bigint` | Promedio del alumno del año actual en escala 0–100; exige visibilidad anual de notas. |
| 0031 | `dashboard_assignment_counts` | `p_assignment_ids: bigint[]` | `{ assignment_id, total, delivered, graded }`; matrícula activa del grupo/año de cada tarea y entregas reales, excluyendo borradores. |
| 0031 | `dashboard_pending_grading` | `p_class_ids: bigint[]` | Número de entregas pendientes de calificar del año actual, sin descargar IDs ni entregas. |
| 0032 | `assignment_feed` | Alumno opcional, clase, búsqueda, tipos, materia, abiertas, cursor de fecha/ID y límite 1–100 | Una página con tareas, adjuntos y avance del alumno. Año actual, matrícula ACT. Las API de tareas codifican el cursor sin perder microsegundos ni precisión de bigint. |
| 0032 | `assignment_counters` | `p_student_id?: bigint` | `{ pending, submitted, graded, toGrade }` completos en SQL, sin descargar e hidratar tareas. |
| 0032 | `class_enrollment_counts` | `p_class_ids: bigint[]` | `{ class_id, total }`; matrícula activa del año de cada clase. El backend consulta lotes de 200. |
| 0033 | `student_report_context` | `p_student_id: bigint`, `p_period_id?: bigint` | Identidad del boletín y asistencia del periodo/año solicitado. Exige alcance, permiso de reportes y visibilidad de notas; conserva RLS. Asistencia sin registros, puesto y total de compañeros quedan en `null` si no están calculados. |
| 0034 | `chat_conversations` | Límite 1–100, cursor fecha/ID, conversación y búsqueda opcionales | Página con participantes, último mensaje, no leídos y total global independiente del filtro. Actor, MFA, institución y membresía comprobados antes de agregar. |
| 0034 | `chat_messages` | Conversación, límite 1–300, `beforeId`/`afterId` excluyentes e ID puntual opcional | Historial o deltas ordenados por secuencia, adjuntos y recibos. `hasMore`, `nextBeforeId`, `nextAfterId`; no descarga historiales para hidratar participantes. |
| 0034 | `chat_mark_read` | Conversación | Inserta únicamente recibos faltantes y confirma notificaciones en una transacción. Sin corte de 1000 filas. |
| 0034 | `chat_ensure_individual` | Otro usuario | Busca o crea ambos participantes en una transacción, serializada por institución/par de usuarios. Conserva historiales existentes sin borrarlos ni unirlos. |
| 0037 | `chat_contacts` | Búsqueda y límite 1–100 | Busca nombre/correo/rol antes de limitar; solo usuarios activos de la institución. |
| 0037 | `teacher_dashboard_classes` | Ninguna | Clases actuales asignadas o compartidas con el actor; permisos y metadatos mínimos para el dashboard. No modifica el workspace histórico de administración. |
| 0037 | `latest_report_cards` | Periodo/alumno/salón opcionales, página y tamaño 1–100 | El más reciente por alumno/periodo, deduplicado en SQL y paginado. Restringe alcance familiar y notas ocultas. |

Las funciones de pagos autorizan explícitamente al actor, MFA, institución y alcance del alumno antes de agregar. Son `SECURITY DEFINER` con `search_path` fijo para evitar repetir las mismas comprobaciones por abono. Las funciones del dashboard son `SECURITY INVOKER`: mantienen las políticas de las tablas/vistas consultadas. Ninguna admite una institución o actor proporcionados por el cliente.

Para grids y reportes que necesitan todas las filas se usan lecturas ordenadas de 500 filas (`readAllPages` en backend y Flutter). Se avanza por las filas realmente recibidas y se termina con una página vacía; una página corta no significa fin porque el servidor puede aplicar un límite inferior. Estas lecturas no son snapshots transaccionales. Los listados interactivos deben usar la paginación de su endpoint; no se usa esta utilidad para reemplazar esa paginación.

Las RPC de `0036` (`admin_people_page`, `admin_directory_options`, `admin_directory_counts`, `admin_profiles_page`, `admin_catalog_page`) son **privadas para service_role**. Los clientes llaman los endpoints administrativos, que verifican el módulo y derivan la institución autorizada. Contratos y cambio del directorio en `DIRECTORIO_PAGINADO.md`. La RPC privada de contexto/cupo `0035` se documenta en `AUTENTICACION_Y_CUPOS.md`.

Los horarios usan `schedule_list`/`schedule_write` de 0038 con JWT del actor y permisos exactos, no service_role. El listado administrativo incluye `pageInfo`; la semana personal mantiene su contrato. Preparación de datos e integridad en `HORARIOS_TRANSACCIONALES.md`.
