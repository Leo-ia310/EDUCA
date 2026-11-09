-- El maestro decide, al crear o editar una tarea, si los estudiantes pueden dejar
-- un comentario junto con su entrega. Por defecto se mantienen habilitados para
-- no cambiar el comportamiento de las tareas ya existentes.
alter table public.assignments
  add column if not exists allow_student_comments boolean not null default true;

-- Conteo ligero de tareas por clase para las tarjetas del panel docente: evita
-- cargar páginas de tareas solo para contar. SECURITY INVOKER: la RLS limita el
-- resultado a las clases visibles para quien consulta (propias y colaborativas).
create or replace function public.teacher_assignment_class_counts() returns jsonb
language sql stable set search_path=public as $$
  select coalesce(jsonb_object_agg(t.class_id::text, jsonb_build_object(
      'total', t.total, 'open', t.open, 'drafts', t.drafts)), '{}'::jsonb)
  from (
    select a.class_id, count(*) total,
      count(*) filter (where a.published and (a.due_at is null or a.due_at >= now())) open,
      count(*) filter (where not a.published) drafts
    from public.assignments a
    where a.institution_id = public.current_institution_id() and a.deleted_at is null
    group by a.class_id
  ) t
$$;
revoke all on function public.teacher_assignment_class_counts() from public, anon;
grant execute on function public.teacher_assignment_class_counts() to authenticated;
