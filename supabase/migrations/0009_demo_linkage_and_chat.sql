-- =============================================================================
-- 0009_demo_linkage_and_chat.sql
--
-- (1) Funciones RESOLVER en el backend: mapean el usuario autenticado
--     (auth.uid()) a su entidad operativa (student/teacher/parent) vía
--     users.person_id. Así el frontend NO hardcodea IDs: pregunta al backend
--     "¿quién soy?" y recibe su student_id/teacher_id/parent_id.
-- (2) Siembra idempotente de conversaciones de chat de demo (antes vacío → el
--     chat conectado no tenía datos y caía en el mock 'c-elena').
-- =============================================================================

-- -----------------------------------------------------------------------------
-- (1) Resolvers — SECURITY DEFINER + STABLE, usan auth.uid() del JWT.
-- -----------------------------------------------------------------------------
create or replace function public.current_person_id()
returns bigint language sql stable security definer set search_path = public as $$
  select u.person_id from users u where u.auth_user_id = auth.uid() limit 1;
$$;

create or replace function public.current_student_id()
returns bigint language sql stable security definer set search_path = public as $$
  select s.id
    from students s
    join users u on u.person_id = s.person_id
   where u.auth_user_id = auth.uid()
   limit 1;
$$;

create or replace function public.current_teacher_id()
returns bigint language sql stable security definer set search_path = public as $$
  select t.id
    from teachers t
    join users u on u.person_id = t.person_id
   where u.auth_user_id = auth.uid()
   limit 1;
$$;

create or replace function public.current_parent_id()
returns bigint language sql stable security definer set search_path = public as $$
  select pa.id
    from parents pa
    join users u on u.person_id = pa.person_id
   where u.auth_user_id = auth.uid()
   limit 1;
$$;

-- Hijos de un padre (para el rol parent): devuelve student_ids.
create or replace function public.my_children_student_ids()
returns setof bigint language sql stable security definer set search_path = public as $$
  select ps.student_id
    from parent_students ps
    join parents pa on pa.id = ps.parent_id
    join users u on u.person_id = pa.person_id
   where u.auth_user_id = auth.uid();
$$;

grant execute on function public.current_person_id()      to authenticated;
grant execute on function public.current_student_id()     to authenticated;
grant execute on function public.current_teacher_id()     to authenticated;
grant execute on function public.current_parent_id()      to authenticated;
grant execute on function public.my_children_student_ids() to authenticated;

-- -----------------------------------------------------------------------------
-- (2) Conversaciones de demo (solo si aún no hay ninguna en la institución 1).
--     users: 2=student@, 3=teacher@, 4=parent@, 5=admin@.
-- -----------------------------------------------------------------------------
do $$
declare
  v_inst bigint := 1;
  v_student bigint; v_teacher bigint; v_parent bigint;
  v_conv1 bigint; v_conv2 bigint;
begin
  if exists (select 1 from conversations where institution_id = v_inst) then
    return;
  end if;

  select id into v_student from users where email = 'student@educa360.com';
  select id into v_teacher from users where email = 'teacher@educa360.com';
  select id into v_parent  from users where email = 'parent@educa360.com';
  if v_teacher is null then return; end if;

  -- Conversación docente ↔ padre
  insert into conversations (institution_id, kind, title, created_by)
  values (v_inst, 'direct', 'Elena Ramírez', v_teacher)
  returning id into v_conv1;
  insert into conversation_participants (conversation_id, user_id, role) values
    (v_conv1, v_teacher, 'member'),
    (v_conv1, v_parent,  'member');
  insert into messages (conversation_id, sender_id, content, created_at) values
    (v_conv1, v_teacher, 'Buenas tardes, Julián va muy bien en Matemáticas.', now() - interval '2 hour'),
    (v_conv1, v_parent,  '¡Gracias, profe! ¿Alguna tarea pendiente?',        now() - interval '1 hour'),
    (v_conv1, v_teacher, 'Solo la entrega del viernes. Saludos.',            now() - interval '50 minute');

  -- Conversación docente ↔ estudiante
  insert into conversations (institution_id, kind, title, created_by)
  values (v_inst, 'direct', 'Elena Ramírez', v_teacher)
  returning id into v_conv2;
  insert into conversation_participants (conversation_id, user_id, role) values
    (v_conv2, v_teacher, 'member'),
    (v_conv2, v_student, 'member');
  insert into messages (conversation_id, sender_id, content, created_at) values
    (v_conv2, v_teacher, 'Recuerda subir tu tarea de álgebra.', now() - interval '3 hour'),
    (v_conv2, v_student, 'Listo, profe. La subo hoy.',           now() - interval '2 hour');
end $$;
