-- 0015_sync_developer_api_registry.sql
-- Sincroniza el inventario tecnico con el backend Node actual.
-- El frontend ya consume /api/developer/* y las escrituras de negocio via
-- POST /api/business-api, por eso se corrigen los estados sembrados en 0014.

update developer_api_registry
set frontend_status = 'connected',
    backend_status = 'implemented',
    updated_at = now(),
    notes = coalesce(notes, 'Sincronizado por migracion 0015.')
where deleted_at is null
  and path like '/api/developer/%';

insert into developer_api_registry (
  module_key,
  method,
  path,
  action,
  summary,
  description,
  backend_status,
  frontend_status,
  request_schema,
  response_schema,
  source_file,
  priority,
  notes
) values
  ('business_api', 'POST', '/api/business-api', null, 'Dispatcher de negocio', 'Endpoint compatible usado por Flutter para escrituras sensibles.', 'implemented', 'connected', '{"body":{"action":"string","payload":"object"}}', '{"ok":true,"data":{}}', 'backend/src/routes/business-api.routes.ts', 'critical', 'Tambien disponible como /functions/v1/business-api en el host Node.'),
  ('assignments', 'POST', 'action: assignments.teacherClasses', 'assignments.teacherClasses', 'Clases del docente', 'Lista clases reales para formularios y asistencia conectada.', 'implemented', 'connected', '{}', '{"ok":true,"data":[]}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('assignments', 'POST', 'action: assignments.upsert', 'assignments.upsert', 'Crear o actualizar tarea', 'Valida docente, clase, periodo academico y adjuntos.', 'implemented', 'connected', '{"payload":{"classId":"number","title":"string","dueAt":"date","maxScore":"number"}}', '{"ok":true,"data":{"assignment":{}}}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('assignments', 'POST', 'action: assignments.submit', 'assignments.submit', 'Entregar tarea', 'Valida estudiante, matricula, publicacion y entregas tardias.', 'implemented', 'connected', '{"payload":{"assignmentId":"number","studentId":"number?"}}', '{"ok":true,"data":{"submission":{}}}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('assignments', 'POST', 'action: assignments.gradeSubmission', 'assignments.gradeSubmission', 'Calificar entrega', 'Registra nota por entrega mediante reglas de negocio.', 'implemented', 'connected', '{"payload":{"submissionId":"number","score":"number"}}', '{"ok":true,"data":{"submission":{}}}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('attendance', 'POST', 'action: attendance.upsertClassSession', 'attendance.upsertClassSession', 'Sincronizar sesion de clase', 'Usado por AttendanceSyncService para el flujo offline-first.', 'implemented', 'connected', '{"payload":{"classId":"number","dateMs":"number|string"}}', '{"ok":true,"data":{"id":"number"}}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('attendance', 'POST', 'action: attendance.upsertAttendance', 'attendance.upsertAttendance', 'Sincronizar asistencia', 'Sube marcaciones offline-first con pertenencia docente y matricula.', 'implemented', 'connected', '{"payload":{"uuid":"string","classId":"number","classSessionId":"number","studentId":"number","statusId":"number","recordedAtMs":"number|string"}}', '{"ok":true,"data":{"id":"number"}}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('chat', 'POST', 'action: chat.sendMessage', 'chat.sendMessage', 'Enviar mensaje', 'Valida que el usuario participe en la conversacion.', 'implemented', 'connected', '{"payload":{"conversationId":"number","content":"string?"}}', '{"ok":true,"data":{"message":{}}}', 'backend/src/services/business-api.service.ts', 'medium', null),
  ('chat', 'POST', 'action: chat.markAsRead', 'chat.markAsRead', 'Marcar conversacion leida', 'Inserta lecturas de mensajes no leidos.', 'implemented', 'connected', '{"payload":{"conversationId":"number"}}', '{"ok":true,"data":{"ok":true}}', 'backend/src/services/business-api.service.ts', 'medium', null),
  ('chat', 'POST', 'action: chat.ensureIndividual', 'chat.ensureIndividual', 'Asegurar chat individual', 'Crea o reutiliza conversacion individual.', 'implemented', 'connected', '{"payload":{"otherUserId":"number"}}', '{"ok":true,"data":{"conversationId":"string"}}', 'backend/src/services/business-api.service.ts', 'medium', null),
  ('events', 'POST', 'action: events.create', 'events.create', 'Crear evento', 'Persistencia de eventos/anuncios desde docentes y admin.', 'implemented', 'connected', '{"payload":{"title":"string","description":"string","date":"date","audience":"string"}}', '{"ok":true,"data":{"event":{}}}', 'backend/src/services/business-api.service.ts', 'medium', null),
  ('grades', 'POST', 'action: grades.upsertScale', 'grades.upsertScale', 'Crear o actualizar escala', 'Configura escala institucional y rangos.', 'implemented', 'connected', '{"payload":{"name":"string","type":"string","ranges":"array"}}', '{"ok":true,"data":{"scale":{}}}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('grades', 'POST', 'action: grades.setDefaultScale', 'grades.setDefaultScale', 'Definir escala por defecto', 'Guarda escala predeterminada de la institucion.', 'implemented', 'connected', '{"payload":{"id":"number"}}', '{"ok":true,"data":{"ok":true}}', 'backend/src/services/business-api.service.ts', 'medium', null),
  ('grades', 'POST', 'action: grades.setGrade', 'grades.setGrade', 'Registrar nota', 'Valida docente, clase y matricula antes de escribir.', 'implemented', 'connected', '{"payload":{"evaluationId":"number","studentId":"number","rawScore":"number"}}', '{"ok":true,"data":{"ok":true}}', 'backend/src/services/business-api.service.ts', 'high', null),
  ('notifications', 'POST', 'action: notifications.saveWebPushDevice', 'notifications.saveWebPushDevice', 'Guardar dispositivo Web Push', 'Persiste la suscripcion Push API del navegador.', 'implemented', 'connected', '{"payload":{"endpoint":"string","pushToken":"string"}}', '{"ok":true,"data":{"ok":true}}', 'backend/src/services/business-api.service.ts', 'medium', null),
  ('payments', 'POST', 'action: payments.register', 'payments.register', 'Registrar pago', 'Registra pago contra cargo con idempotencia opcional.', 'implemented', 'connected', '{"payload":{"chargeId":"number","amount":"number","method":"string","idempotencyKey":"uuid?"}}', '{"ok":true,"data":{"payment":{}}}', 'backend/src/services/business-api.service.ts', 'high', 'Pasarela externa real pendiente de proveedor/credenciales.'),
  ('payments', 'POST', 'action: payments.cancelCharge', 'payments.cancelCharge', 'Anular cargo', 'Marca cargo como cancelado desde administracion.', 'implemented', 'connected', '{"payload":{"chargeId":"number"}}', '{"ok":true,"data":{"ok":true}}', 'backend/src/services/business-api.service.ts', 'medium', null),
  ('assignments', 'POST', '/api/assignments/*', null, 'Rutas REST de tareas', 'Equivalentes a las actions assignments.*.', 'implemented', 'not_needed', '{}', '{"ok":true,"data":{}}', 'backend/src/routes/assignments.routes.ts', 'low', 'Flutter usa /api/business-api.'),
  ('attendance', 'POST', '/api/attendance/*', null, 'Rutas REST de asistencia', 'Equivalentes a las actions attendance.*.', 'implemented', 'not_needed', '{}', '{"ok":true,"data":{}}', 'backend/src/routes/attendance.routes.ts', 'low', 'Flutter usa /api/business-api.'),
  ('chat', 'POST', '/api/chats/*', null, 'Rutas REST de chat', 'Equivalentes a las actions chat.*.', 'implemented', 'not_needed', '{}', '{"ok":true,"data":{}}', 'backend/src/routes/chats.routes.ts', 'low', 'Flutter usa /api/business-api.'),
  ('events', 'POST', '/api/events', null, 'Ruta REST de eventos', 'Equivalente a events.create.', 'implemented', 'not_needed', '{}', '{"ok":true,"data":{}}', 'backend/src/routes/events.routes.ts', 'low', 'Flutter usa /api/business-api.'),
  ('grades', 'POST', '/api/grades/*', null, 'Rutas REST de notas', 'Equivalentes a las actions grades.*.', 'implemented', 'not_needed', '{}', '{"ok":true,"data":{}}', 'backend/src/routes/grades.routes.ts', 'low', 'Flutter usa /api/business-api.'),
  ('notifications', 'POST', '/api/notifications/web-push-device', null, 'Ruta REST Web Push device', 'Equivalente a notifications.saveWebPushDevice.', 'implemented', 'not_needed', '{}', '{"ok":true,"data":{}}', 'backend/src/routes/notifications.routes.ts', 'low', 'Flutter usa /api/business-api.'),
  ('payments', 'POST', '/api/payments/*', null, 'Rutas REST de pagos', 'Equivalentes a las actions payments.*.', 'implemented', 'not_needed', '{}', '{"ok":true,"data":{}}', 'backend/src/routes/payments.routes.ts', 'low', 'Flutter usa /api/business-api.')
on conflict do nothing;
