-- =============================================================================
-- 0010_demo_announcements.sql — Anuncios de demo (idempotente).
-- Antes la tabla `announcements` estaba vacía → los dashboards admin/parent no
-- tenían "avisos" reales. Se siembran 3 si aún no hay ninguno en la institución.
-- =============================================================================
do $$
declare
  v_inst bigint := 1;
  v_author bigint;
begin
  if exists (select 1 from announcements where institution_id = v_inst) then
    return;
  end if;
  select id into v_author from users where email = 'admin@educa360.com';

  insert into announcements
    (institution_id, title, content, kind, audience, published, published_at, created_by)
  values
    (v_inst, 'Reunión de Padres Trimestral',
     'Discusión sobre nuevos lineamientos y plan de becas 2026.',
     'general', 'all', true, now() - interval '1 day', v_author),
    (v_inst, 'Feria de Ciencias 2026',
     'Convocatoria abierta a estudiantes para presentar proyectos.',
     'event', 'all', true, now() - interval '3 day', v_author),
    (v_inst, 'Mantenimiento de plataforma',
     'El portal estará en mantenimiento el sábado por la noche.',
     'system', 'all', true, now() - interval '5 day', v_author);
end $$;
