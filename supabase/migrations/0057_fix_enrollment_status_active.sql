-- 0057_fix_enrollment_status_active.sql
-- admin_people_relations (0048) filtraba catalog_enrollment_statuses por una columna "active" que esa tabla
-- (0001_init_core: id, name, code) no tiene: cada alta de un alumno con salón fallaba con
-- 42703 «column "active" does not exist» (el backend lo mostraba como 503). Se quita ese filtro: los estados
-- son un catálogo fijo (ACT, RET, TRA, EGR) y se busca por código.
-- Solo redefine la función; no toca datos ni permisos (create or replace conserva los grants).
CREATE OR REPLACE FUNCTION public.admin_people_relations(p_inst bigint, p_kind text, p_id bigint, p_relations jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare year_id bigint; group_id bigint; ids bigint[]; existing bigint[]; actor bigint:=public.current_user_id();
begin
  if jsonb_typeof(p_relations) is distinct from 'object' then raise exception 'Relaciones inválidas.' using errcode='22023'; end if;
  if exists(select 1 from jsonb_object_keys(p_relations) k where k not in('groupId','classIds','childIds')) then raise exception 'Relación no permitida.' using errcode='22023'; end if;
  if p_kind='teachers' and p_relations?'classIds' then
    if jsonb_typeof(p_relations->'classIds')<>'array' or jsonb_array_length(p_relations->'classIds')>1000 then raise exception 'Clases inválidas.' using errcode='22023'; end if;
    select coalesce(array_agg(distinct value::bigint order by value::bigint),'{}') into ids from jsonb_array_elements_text(p_relations->'classIds');
    select id into year_id from public.academic_years where institution_id=p_inst and is_current and active order by id desc limit 1;
    if year_id is null and cardinality(ids)=0 then return; end if;
    if year_id is null then raise exception 'Configura un año académico actual.' using errcode='22023'; end if;
    if exists(select 1 from unnest(ids) selected(id) where not exists(select 1 from public.classes c where c.id=selected.id and c.institution_id=p_inst and c.academic_year_id=year_id and c.active)) then
      raise exception 'Las clases deben pertenecer al año actual de la institución.' using errcode='22023'; end if;
    select coalesce(array_agg(id order by id),'{}') into existing from public.classes where institution_id=p_inst and teacher_id=p_id and academic_year_id=year_id and active;
    if existing is distinct from ids then
      if not public.administrative_permission(p_inst,'classes.edit') then raise exception 'Necesitas permiso para asignar clases.' using errcode='42501'; end if;
      perform pg_advisory_xact_lock(hashtextextended('schedule-write:'||p_inst,0));
      update public.classes set teacher_id=null where institution_id=p_inst and teacher_id=p_id and academic_year_id=year_id and active and not id=any(ids);
      update public.classes set teacher_id=p_id where institution_id=p_inst and id=any(ids) and teacher_id is distinct from p_id;
    end if;
  elsif p_kind='students' and p_relations?'groupId' then
    select id into year_id from public.academic_years where institution_id=p_inst and is_current and active order by id desc limit 1;
    group_id:=(p_relations->>'groupId')::bigint;
    if year_id is null and group_id is null then return; end if;
    if year_id is null then raise exception 'Configura un año académico actual.' using errcode='22023'; end if;
    if group_id is null then delete from public.enrollments where institution_id=p_inst and student_id=p_id and academic_year_id=year_id;
    else
      if not exists(select 1 from public.groups g where g.id=group_id and g.institution_id=p_inst and g.academic_year_id=year_id and g.active) then raise exception 'Salón fuera del año actual.' using errcode='22023'; end if;
      insert into public.enrollments(institution_id,student_id,group_id,academic_year_id,enrollment_status_id,enrolled_at)
      values(p_inst,p_id,group_id,year_id,(select id from public.catalog_enrollment_statuses where code='ACT' order by id limit 1),current_date)
      on conflict(student_id,academic_year_id) do update set group_id=excluded.group_id,enrollment_status_id=excluded.enrollment_status_id;
    end if;
  elsif p_kind='parents' and p_relations?'childIds' then
    if jsonb_typeof(p_relations->'childIds')<>'array' or jsonb_array_length(p_relations->'childIds')>5000 then raise exception 'Hijos inválidos.' using errcode='22023'; end if;
    select coalesce(array_agg(distinct value::bigint),'{}') into ids from jsonb_array_elements_text(p_relations->'childIds');
    if exists(select 1 from unnest(ids) selected(id) where not exists(select 1 from public.students s where s.id=selected.id and s.institution_id=p_inst)) then raise exception 'Estudiante fuera de la institución.' using errcode='22023'; end if;
    delete from public.parent_students where parent_id=p_id and not student_id=any(ids);
    insert into public.parent_students(parent_id,student_id) select p_id,id from unnest(ids) id on conflict(parent_id,student_id) do nothing;
  end if;
end $function$
;
