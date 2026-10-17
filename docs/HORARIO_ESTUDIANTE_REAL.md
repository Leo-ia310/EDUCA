# Horario real del estudiante (Task 28)

El inicio (`HomeScheduleSection`) y la pantalla `ScheduleScreen` comparten
`weeklySlotsProvider`, conectado a `GET /api/schedules/mine` con el token de
sesión. El estudiante no envía un ID de usuario ni una institución elegidos
desde el cliente: el backend los resuelve desde la sesión y la matrícula.
Para padres se valida que `studentId` corresponda a uno de sus hijos.

Los ejemplos requieren `--dart-define=DEMO=true`. La ausencia de usuario,
institución, credenciales o cliente de API ya no activa horarios ficticios.
Una respuesta inválida o un fallo de API produce un error con reintento,
sin presentarse como un día libre. Mientras carga no se muestra el horario
anterior; si toda la semana está vacía se muestra «No tienes horario asignado».
Un día sin clases dentro de una semana asignada conserva su estado de día libre.

`SchedulesRepository.listForClasses` filtra en SQL por institución y clases
autorizadas, sin descargar todos los horarios del colegio. Añade únicamente
los recesos generales o de los grupos autorizados. Si no hay clases
programadas, devuelve una lista vacía aunque existan recesos generales.
Los bloques creados por admin se leen de la misma tabla `schedules`.

La carga depende de la identidad (usuario, institución y rol), no de cambios
transitorios de `loading` o errores de autenticación. No se agregó polling.

Comprobaciones:

- `cd backend; npm run typecheck; npm run docs:apis`.
- `npx tsx scripts/student_schedule_check.ts`: estudiante propio/ajeno,
  hijo autorizado/no autorizado, institución de sesión, vacío y consultas SQL
  de solo lectura. No crea cuentas ni modifica datos.
- `cd frontend; flutter test --no-pub --concurrency=1 test/student_schedule_test.dart test/schedules_test.dart`:
  API real frente a datos demo, sesión/API ausentes, respuesta inválida,
  estabilidad ante cambios de carga de auth y estados de inicio/pantalla.
- `flutter analyze --no-pub`.
