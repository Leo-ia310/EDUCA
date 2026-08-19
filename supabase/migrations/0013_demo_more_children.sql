-- =============================================================================
-- 0013_demo_more_children.sql — Más hijos para el padre demo (idempotente).
-- Marta (parents.id=1) tenía solo a Julián. Se añaden 2 hijos más para poder
-- probar el selector de hijos del dashboard de padre.
-- =============================================================================
do $$
declare v_parent bigint := 1;
begin
  if (select count(*) from parent_students where parent_id = v_parent) >= 2 then
    return;
  end if;
  insert into parent_students (student_id, parent_id, is_main_responsible, can_pickup, lives_with)
  values
    (2, v_parent, true,  true, true),   -- Ana Martínez
    (5, v_parent, false, true, true)    -- Diego Rivas
  on conflict do nothing;
end $$;
