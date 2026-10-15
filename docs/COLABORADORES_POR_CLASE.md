# Colaboradores por clase

Desde **Mis clases → Colaboradores**, un titular puede invitar a otro profesor
activo de su institución, seleccionar una o varias clases propias y asignar
permisos. La invitación aparece en las notificaciones del destinatario y en
Colaboradores. Hasta que la acepta, no concede acceso. El titular o administración
puede editar los permisos o revocar el acceso. Un colaborador no puede delegarlo.

| Permiso | Alcance |
| --- | --- |
| `class.view` | Ver la clase y sus tareas; obligatorio |
| `students.view` | Consultar el grupo, estudiantes y calificaciones en lectura |
| `assignments.create` | Crear, editar, publicar y archivar tareas de esa clase |
| `assignments.review` | Consultar entregas y sus adjuntos; no permite calificar |
| `assignments.grade` | Calificar entregas mediante el RPC de calificación |
| `grades.write` | Registrar o ajustar notas del libro; no concede calificar tareas |
| `attendance.write` | Registrar o actualizar asistencia; no borrar sesiones históricas |

Revisar/calificar entregas, registrar notas y asistencia incluyen `students.view`.
Calificar tareas también incluye revisar sus entregas. No se agregan otros
permisos de escritura. El atajo **Solo lectura** marca clase, estudiantes y
revisión de entregas. La estructura de evaluaciones y la administración de
colaboradores siguen reservadas al titular/administración.

## Implementación

- Migración `0025_class_collaborators.sql`: relación, invitaciones, permisos,
  funciones con validación de actor/institución y políticas RLS restrictivas.
- `GET /api/collaborations`: clases accesibles con `isOwner`/`permissions`,
  invitaciones visibles y profesores disponibles de la institución.
- `POST /api/collaborations`: acciones `invite`, `accept`, `decline`, `update`,
  `revoke`. La invitación a varias clases es atómica: si alguna no está autorizada,
  no se invita en ninguna.
- La API y RLS verifican los permisos específicos. También se protege el RPC
  `grade_submission`, que ejecuta con privilegios elevados; su implementación
  interna no es ejecutable por clientes.
- Las identidades, los roles y la asignación del titular no pueden modificarse
  desde una cuenta docente para ampliar privilegios.
- Titular y colaboradores comparten una sesión de asistencia por clase/fecha.
  El RPC usa un bloqueo transaccional para impedir duplicados concurrentes.
- Las acciones sobre colaboraciones, tareas, entregas, evaluaciones, notas y
  asistencia generan auditoría con el usuario autenticado real. Los clientes no
  pueden insertar o modificar esos registros de auditoría.
- Al aceptar/editar/revocar se refrescan las clases y selectores locales. Una
  pantalla que ya estaba abierta en otro dispositivo puede conservar su vista
  hasta refrescarla, pero la API y RLS rechazan inmediatamente los accesos revocados.
- Se requiere conexión para gestionar invitaciones. En demo no se simulan
  invitaciones reales ni se envían correos.

## Verificación

`backend/scripts/collaborations_db_check.mjs` crea identidades temporales dentro
de una transacción y verifica invitaciones a varias clases, aceptación, aislamiento
entre instituciones, dependencias de permisos, llamadas directas a tablas/RPC,
calificación vs. libro de notas, asistencia compartida, auditoría y revocación.
Todo se revierte con rollback, incluidas las notificaciones; no se envían correos.

Las pruebas Flutter en `test/features/collaborations/` cubren la selección de
varias clases, permisos mínimos, aceptación y acciones ocultas para colaboradores
con acceso limitado. Ejecutar además `flutter test --no-pub`,
`flutter analyze --no-pub`, `npm run typecheck` y `npm run docs:apis`.
