# Accesos de alumnos y padres (Tasks 33 y 36)

En **Roles y perfiles → Accesos de padres, alumnos y notas**, una cuenta de
administración o dirección con `roles.edit` puede guardar, cambiar o quitar
reglas. Los destinatarios se buscan escribiendo nombre o identificador, sin
sensibilidad a mayúsculas o tildes; se muestran hasta 50 coincidencias con una
lista que construye solo las filas visibles. El alcance global afecta a alumnos y padres; docentes y administración
conservan sus permisos académicos existentes.

## Permisos de módulos

Se admiten reglas de institución, rol (`parent` / `student`) y usuario.
La prioridad es **usuario > rol > institución**; sin regla, se permite el acceso.
Si coinciden dos roles con la misma prioridad, prevalece la restricción.
Quitar una regla restaura la configuración heredada.

Se controlan notas, pagos, asistencia, horario, lectura y entrega de tareas,
reportes, descarga de boletines, comunicados, envío de mensajes y materiales.
Desactivar entrega de tareas conserva su lectura. Desactivar envío de mensajes
conserva conversaciones y confirmaciones de lectura; oculta el nuevo mensaje y
el compositor. No se aplica automáticamente una restricción por mora: el admin
decide cuándo activarla o retirarla.

## Visibilidad de notas

Las reglas pueden dirigirse a institución, rol, grupo, estudiante o usuario,
para todos los periodos o uno específico. La prioridad es:

**usuario > estudiante > grupo > rol > institución**.

Dentro del mismo alcance, el periodo específico precede a todos los periodos.
En un empate prevalece ocultar. Además, el permiso de módulo `grades.view`
debe estar habilitado; una regla de visibilidad no reactiva un módulo bloqueado.

Una regla de estudiante o grupo afecta al estudiante y a los padres vinculados.
Una regla de usuario padre afecta solo a esa cuenta. El filtro de grupo respeta
el año académico del periodo. Si algún periodo está oculto, el resumen anual
se bloquea para evitar divulgar indirectamente sus notas. La pantalla Notas
permite elegir otro estudiante o periodo habilitado.

## Protección y actualización

La migración `0026_portal_access_and_grade_visibility.sql` guarda las reglas
con aislamiento por institución, validación de destinos y auditoría del actor.
Los RPC administrativos exigen `roles.edit`; las tablas no permiten escrituras
directas del usuario. API y RLS validan las restricciones, incluidas consultas
directas de Supabase, notas, promedios, reportes, metadatos de archivos y nuevas
descargas de Storage. Las relaciones familiares y matrículas no se pueden
reescribir desde una cuenta de alumno o padre para eludir el alcance.

La API revisa los permisos en cada petición. Flutter consulta al iniciar sesión,
cuando cambia la revisión de permisos en Realtime y al volver a la app o
reconectar. La migración 0027 publica una revisión por institución, sin reglas
ni datos personales. No hay sondeo periódico de permisos. Los avisos se agrupan
y la actualización ocurre en segundo plano: solo un cambio efectivo invalida
los datos dependientes; una respuesta idéntica no cambia el estado de pantalla.
Un error al consultar permisos bloquea los módulos protegidos y
ofrece reintento. Una copia ya descargada o un enlace firmado previamente
emitido conserva su vigencia; una regla no puede retirar una copia del equipo.

## API y verificación

- `GET /api/portal-access/me`: permisos efectivos y periodos visibles por hijo.
- `GET /api/portal-access/config`: reglas y destinos de la institución.
- `POST /api/portal-access/config`: guardar/quitar reglas.
- `GET /api/portal-access/grades?studentId=…&periodId=…`: notas autorizadas;
  omitir periodo solicita el anual. Una restricción devuelve HTTP 403.

Desde `backend`: `npm run typecheck`, `npm run docs:apis` y
`npx tsx scripts/portal_access_check.ts`.
Desde `backend/scripts`: `node portal_access_db_check.mjs` y
`node collaborations_db_check.mjs`. Los datos, reglas y auditorías de prueba
se revierten con rollback; no se envían mensajes, correos ni push reales.
Desde `frontend`: `flutter test --no-pub` y `flutter analyze --no-pub`.

Las pruebas cubren prioridad de reglas, cuenta del padre frente a la del hijo,
grupos y trimestres, protección de promedios/PDF, acceso directo a tablas,
restricción de entregas y mensajes, permisos administrativos, instituciones
distintas, edición desde la interfaz y navegación directa a módulos bloqueados.
