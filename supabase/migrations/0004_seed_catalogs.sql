-- =============================================================================
-- Educa360 — 0004 SEED CATÁLOGOS + INSTITUCIÓN DEMO
-- =============================================================================

insert into catalog_countries (iso_code, name, phone_code) values
  ('NIC', 'Nicaragua', '505'),
  ('CRI', 'Costa Rica', '506'),
  ('HND', 'Honduras', '504'),
  ('GTM', 'Guatemala', '502'),
  ('SLV', 'El Salvador', '503'),
  ('PAN', 'Panamá', '507'),
  ('MEX', 'México', '52'),
  ('USA', 'Estados Unidos', '1')
on conflict do nothing;

insert into catalog_currencies (iso_code, name, symbol) values
  ('NIO', 'Córdoba',  'C$'),
  ('USD', 'Dólar',    '$'),
  ('EUR', 'Euro',     '€'),
  ('CRC', 'Colón',    '₡')
on conflict do nothing;

insert into catalog_document_types (name, code) values
  ('Cédula', 'CED'),
  ('Pasaporte', 'PAS'),
  ('Partida de nacimiento', 'PN')
on conflict do nothing;

insert into catalog_genders (name, code) values
  ('Masculino', 'M'),
  ('Femenino', 'F'),
  ('No especificado', 'NE')
on conflict do nothing;

insert into catalog_relationships (name) values
  ('Padre'), ('Madre'), ('Tutor'), ('Abuelo/a'), ('Tío/a')
on conflict do nothing;

insert into catalog_education_levels (name, display_order) values
  ('Preescolar', 1), ('Primaria', 2), ('Secundaria', 3), ('Bachillerato', 4),
  ('Universidad', 5)
on conflict do nothing;

insert into catalog_weekdays (name, abbreviation, display_order) values
  ('Lunes', 'Lun', 1), ('Martes', 'Mar', 2), ('Miércoles', 'Mié', 3),
  ('Jueves', 'Jue', 4), ('Viernes', 'Vie', 5), ('Sábado', 'Sáb', 6),
  ('Domingo', 'Dom', 7)
on conflict do nothing;

insert into catalog_attendance_statuses (name, code, counts_as_absent, color) values
  ('Presente', 'PRE', false, '#22C55E'),
  ('Ausente', 'AUS', true, '#EF4444'),
  ('Tarde', 'TAR', false, '#F59E0B'),
  ('Justificado', 'JUS', false, '#3B82F6'),
  ('Permiso', 'PER', false, '#8B5CF6')
on conflict do nothing;

insert into catalog_evaluation_types (name, code) values
  ('Examen', 'EXM'), ('Tarea', 'TAR'), ('Proyecto', 'PRO'),
  ('Quiz', 'QZ'), ('Exposición', 'EXP'), ('Participación', 'PART')
on conflict do nothing;

insert into catalog_task_statuses (name, code) values
  ('Pendiente', 'PEND'), ('Entregada', 'ENTR'),
  ('Calificada', 'CALI'), ('Vencida', 'VENC'), ('Revisada', 'REV')
on conflict do nothing;

insert into catalog_enrollment_statuses (name, code) values
  ('Activa', 'ACT'), ('Retirada', 'RET'),
  ('Trasladada', 'TRA'), ('Egresada', 'EGR')
on conflict do nothing;

insert into catalog_notification_channels (name, code) values
  ('Email', 'EMAIL'), ('Push', 'PUSH'), ('SMS', 'SMS'), ('In-App', 'INAPP')
on conflict do nothing;

insert into catalog_notification_types (name, code) values
  ('Asistencia', 'ATT'),
  ('Calificación', 'GRADE'),
  ('Tarea', 'TASK'),
  ('Comunicado', 'ANN'),
  ('Pago', 'PAY'),
  ('Mensaje', 'MSG')
on conflict do nothing;

insert into catalog_file_types (name, extension, mime_type) values
  ('PDF', 'pdf', 'application/pdf'),
  ('Imagen', 'jpg', 'image/jpeg'),
  ('Documento', 'docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  ('Video', 'mp4', 'video/mp4')
on conflict do nothing;

-- Permisos base
insert into permissions (module, name, code) values
  ('attendance', 'Crear asistencia', 'attendance.create'),
  ('attendance', 'Ver asistencia',   'attendance.read'),
  ('assignments', 'Crear tarea',     'assignments.create'),
  ('assignments', 'Calificar tarea', 'assignments.grade'),
  ('grades', 'Ver calificaciones',   'grades.read'),
  ('grades', 'Registrar nota',       'grades.write'),
  ('reports', 'Ver reportes',        'reports.read'),
  ('users', 'Gestionar usuarios',    'users.manage'),
  ('announcements', 'Publicar anuncio', 'announcements.publish'),
  ('messages', 'Enviar mensajes', 'messages.send')
on conflict do nothing;

-- Roles globales del sistema
insert into roles (institution_id, name, code, is_system) values
  (null, 'Super Administrador', 'super_admin', true),
  (null, 'Estudiante',         'student',     true),
  (null, 'Maestro',            'teacher',     true),
  (null, 'Padre/Tutor',        'parent',      true),
  (null, 'Administrador',      'admin',       true),
  (null, 'Coordinador',        'coordinator', true),
  (null, 'Director',           'director',    true)
on conflict do nothing;

-- Institución demo
insert into institutions (code, name, primary_color, secondary_color, timezone, active)
values ('EDU360', 'Colegio Demo Educa360', '#9BE000', '#1E2218', 'America/Managua', true)
on conflict (code) do nothing;
