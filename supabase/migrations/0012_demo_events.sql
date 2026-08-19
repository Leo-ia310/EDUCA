-- =============================================================================
-- 0012_demo_events.sql — Eventos institucionales de demo (idempotente).
-- La tabla `calendar_events` ya existía (0001) pero estaba vacía → los
-- dashboards usaban el conteo de anuncios como sustituto. Aquí se siembran 6
-- eventos (algunos este mes, otros próximos) si aún no hay ninguno.
-- =============================================================================
do $$
declare
  v_inst   bigint := 1;
  v_author bigint;
begin
  if exists (select 1 from calendar_events where institution_id = v_inst) then
    return;
  end if;
  select id into v_author from users where email = 'admin@educa360.com';

  insert into calendar_events
    (institution_id, title, description, type, start_at, end_at, audience, created_by)
  values
    (v_inst, 'Entrega de Boletines', 'Entrega de calificaciones del I Trimestre.',
     'academic', date_trunc('month', now()) + interval '4 day 15 hour',
     date_trunc('month', now()) + interval '4 day 17 hour', 'parents', v_author),
    (v_inst, 'Reunión de Padres', 'Reunión general con docentes.',
     'meeting', now() + interval '5 day', now() + interval '5 day 2 hour', 'parents', v_author),
    (v_inst, 'Simulacro de Evacuación', 'Ejercicio de seguridad escolar.',
     'drill', now() + interval '8 day', now() + interval '8 day 1 hour', 'all', v_author),
    (v_inst, 'Feria de Ciencias 2026', 'Exposición de proyectos de estudiantes.',
     'academic', now() + interval '12 day', now() + interval '12 day 6 hour', 'all', v_author),
    (v_inst, 'Día del Estudiante', 'Actividades recreativas y culturales.',
     'holiday', now() + interval '20 day', now() + interval '20 day 8 hour', 'students', v_author),
    (v_inst, 'Torneo Interescolar', 'Competencia deportiva.',
     'sport', date_trunc('month', now()) + interval '25 day 9 hour',
     date_trunc('month', now()) + interval '25 day 14 hour', 'all', v_author);
end $$;
