-- Private helpers are callable only by the checked transaction entrypoints.
create function public.admin_record_write(p_table text,p_inst bigint,p_id bigint,p_changes jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare allowed text[]; key text; columns text; assignments text; data jsonb; result jsonb;
begin
  allowed:=case p_table
    when 'persons' then array['first_name','last_name','document_number','birth_date','email','phone','address','photo_url']
    when 'students' then array['person_id','student_code','enrollment_date','blood_type','allergies','medical_notes','active']
    when 'teachers' then array['person_id','teacher_code','specialty','academic_title','hired_at','active']
    when 'parents' then array['person_id','occupation','workplace','work_phone','is_emergency_contact']
    when 'users' then array['person_id','auth_user_id','username','email','phone','full_name','avatar_url','active','admin_permissions'] end;
  if allowed is null or jsonb_typeof(p_changes) is distinct from 'object' then raise exception 'Registro inválido.' using errcode='22023'; end if;
  for key in select jsonb_object_keys(p_changes) loop
    if not key=any(allowed) then raise exception 'Campo no permitido.' using errcode='22023'; end if;
  end loop;
  if p_id is null then
    data:=p_changes||jsonb_build_object('institution_id',p_inst);
    select string_agg(format('%I',k),',') into columns from jsonb_object_keys(data) k;
    execute format('insert into public.%I(%s) select %s from jsonb_populate_record(null::public.%I,$1) returning to_jsonb(%I.*)',p_table,columns,columns,p_table,p_table) into result using data;
  else
    if p_changes='{}'::jsonb then
      execute format('select to_jsonb(t.*) from public.%I t where id=$1 and institution_id=$2 for update',p_table) into result using p_id,p_inst;
    else
      select string_agg(format('%I=(jsonb_populate_record(null::public.%I,$1)).%I',k,p_table,k),',') into assignments from jsonb_object_keys(p_changes) k;
      execute format('update public.%I t set %s where id=$2 and institution_id=$3 returning to_jsonb(t.*)',p_table,assignments) into result using p_changes,p_id,p_inst;
    end if;
    if result is null then raise exception 'Registro no encontrado.' using errcode='P0002'; end if;
  end if;
  return result;
end $$;
revoke all on function public.admin_record_write(text,bigint,bigint,jsonb) from public,anon,authenticated;

create function public.admin_user_document(p_inst bigint,p_id bigint) returns jsonb
language sql stable security definer set search_path=public as $$
 select to_jsonb(u.*)||jsonb_build_object('user_roles',coalesce((select jsonb_agg(jsonb_build_object('role_id',ur.role_id,'roles',to_jsonb(r.*)))
   from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id and (ur.institution_id is null or ur.institution_id=p_inst)), '[]'::jsonb))
 from public.users u where u.id=p_id and u.institution_id=p_inst
$$;
revoke all on function public.admin_user_document(bigint,bigint) from public,anon,authenticated;

create function public.admin_role_set(p_inst bigint,p_user bigint,p_codes text[]) returns void
language plpgsql security definer set search_path=public as $$
declare role_code text; rid bigint; ids bigint[]:='{}'; target public.users%rowtype; caller public.users%rowtype;
begin
  select * into target from public.users where id=p_user and institution_id=p_inst for update;
  select * into caller from public.users where id=public.current_user_id();
  if target.id is null or caller.id is null or p_codes is null or cardinality(p_codes)>30 then raise exception 'Roles inválidos.' using errcode='22023'; end if;
  if exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_user and r.code='admin')
    and not (public.has_role('admin') or public.has_role('super_admin')) then raise exception 'Cuenta administrativa protegida.' using errcode='42501'; end if;
  if (exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_user and r.code='super_admin')
      or 'super_admin'=any(p_codes)) and not public.has_role('super_admin') then raise exception 'Solo superadministración puede modificar ese rol.' using errcode='42501'; end if;
  if p_user=caller.id and (select coalesce(array_agg(x.code::text order by x.code::text),'{}'::text[]) from (select distinct unnest(p_codes) code) x)
      is distinct from (select coalesce(array_agg(x.code::text order by x.code::text),'{}'::text[]) from (select distinct r.code from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_user) x) then
    raise exception 'No puedes cambiar tus propios roles.' using errcode='42501'; end if;
  if 'admin'=any(p_codes) and not (public.has_role('admin') or public.has_role('super_admin')) then raise exception 'No puedes asignar administración.' using errcode='42501'; end if;
  if p_codes&&array['admin','coordinator','director'] and not public.has_role('super_admin') and caller.admin_permissions is not null
    and (target.admin_permissions is null or not target.admin_permissions<@caller.admin_permissions) then
    raise exception 'No puedes conceder permisos superiores a los tuyos.' using errcode='42501'; end if;
  foreach role_code in array p_codes loop
    select r.id into rid from public.roles r where r.code=role_code and r.active and (r.institution_id=p_inst or r.institution_id is null)
      order by (r.institution_id=p_inst) desc nulls last,r.id limit 1;
    if rid is null then raise exception 'Rol no disponible.' using errcode='22023'; end if;
    ids:=array_append(ids,rid);
  end loop;
  delete from public.user_roles where user_id=p_user;
  insert into public.user_roles(institution_id,user_id,role_id) select p_inst,p_user,id from unnest(ids) id group by id;
end $$;
revoke all on function public.admin_role_set(bigint,bigint,text[]) from public,anon,authenticated;

create function public.admin_people_relations(p_inst bigint,p_kind text,p_id bigint,p_relations jsonb) returns void
language plpgsql security definer set search_path=public as $$
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
end $$;
revoke all on function public.admin_people_relations(bigint,text,bigint,jsonb) from public,anon,authenticated;

create function public.admin_person_write(p_inst bigint,p_kind text,p_id bigint,p_person jsonb default '{}',p_entity jsonb default '{}',p_relations jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); module text; resource jsonb; person jsonb; linked public.users%rowtype;
begin
  module:=case p_kind when 'teachers' then 'teachers' when 'students' then 'students' when 'parents' then 'students' end;
  if module is null or not public.administrative_permission(p_inst,module||'.edit') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('admin-write:'||p_inst,0));
  if p_kind='teachers' and p_relations?'classIds' then perform pg_advisory_xact_lock(hashtextextended('schedule-write:'||p_inst,0)); end if;
  resource:=public.admin_record_write(p_kind,p_inst,p_id,'{}');
  if p_entity?'person_id' then raise exception 'La identidad no se puede reemplazar.' using errcode='42501'; end if;
  select * into linked from public.users where person_id=(resource->>'person_id')::bigint and institution_id=p_inst;
  if linked.id is not null and not public.user_management_permission(linked.id,'edit') then raise exception 'No puedes modificar esa cuenta.' using errcode='42501'; end if;
  person:=public.admin_record_write('persons',p_inst,(resource->>'person_id')::bigint,p_person);
  resource:=public.admin_record_write(p_kind,p_inst,p_id,p_entity);
  perform public.admin_people_relations(p_inst,p_kind,p_id,p_relations);
  if linked.id is not null then
    update public.users set full_name=concat_ws(' ',person->>'first_name',person->>'last_name'),phone=person->>'phone',
      active=case when p_entity?'active' then (p_entity->>'active')::boolean else active end,updated_at=clock_timestamp() where id=linked.id;
  end if;
  return resource||jsonb_build_object('persons',person);
end $$;
revoke all on function public.admin_person_write(bigint,text,bigint,jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.admin_person_write(bigint,text,bigint,jsonb,jsonb,jsonb) to authenticated;

create function public.admin_account_write(p_inst bigint,p_id bigint,p_changes jsonb,p_roles text[] default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); caller public.users%rowtype; target public.users%rowtype; doc jsonb;
begin
  if not public.administrative_permission(p_inst,case when p_id is null then 'roles.create' else 'roles.edit' end) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('admin-write:'||p_inst,0));
  select * into caller from public.users where id=actor;
  if p_id is not null then
    select * into target from public.users where id=p_id and institution_id=p_inst for update;
    if target.id is null then raise exception 'Cuenta no encontrada.' using errcode='P0002'; end if;
    if exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_id and r.code='super_admin') and not public.has_role('super_admin') then raise exception 'Cuenta protegida.' using errcode='42501'; end if;
    if exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_id and r.code='admin')
      and not (public.has_role('admin') or public.has_role('super_admin')) then raise exception 'Cuenta administrativa protegida.' using errcode='42501'; end if;
    if target.auth_user_id is not null and p_changes?'email' and lower(p_changes->>'email') is distinct from lower(target.email) then
      raise exception 'El correo de acceso requiere un cambio verificado en Auth.' using errcode='22023'; end if;
    if p_id=actor and (p_changes?'admin_permissions' or p_changes?'active' and (p_changes->>'active')::boolean=false) then raise exception 'No puedes cambiar tus propios permisos ni desactivarte.' using errcode='42501'; end if;
  elsif p_roles is null or cardinality(p_roles)=0 then raise exception 'Asigna al menos un rol.' using errcode='22023';
  end if;
  if p_changes?'person_id' and p_changes->>'person_id' is not null and not exists(select 1 from public.persons where id=(p_changes->>'person_id')::bigint and institution_id=p_inst) then raise exception 'Persona fuera de la institución.' using errcode='22023'; end if;
  if p_id is null and p_changes->>'auth_user_id' is not null and not exists(select 1 from auth.users u where u.id=(p_changes->>'auth_user_id')::uuid
    and u.raw_app_meta_data->>'institution_id'=p_inst::text and lower(u.email)=lower(p_changes->>'email')) then raise exception 'Identidad de acceso no verificada.' using errcode='42501'; end if;
  if p_changes?'admin_permissions' and jsonb_typeof(p_changes->'admin_permissions') not in('array','null') then raise exception 'Permisos inválidos.' using errcode='22023'; end if;
  if p_changes?'admin_permissions' and not public.has_role('super_admin') and caller.admin_permissions is not null and
    (p_changes->'admin_permissions'='null'::jsonb or exists(select 1 from jsonb_array_elements_text(p_changes->'admin_permissions') p where not p=any(caller.admin_permissions))) then
    raise exception 'No puedes conceder permisos que no tienes.' using errcode='42501'; end if;
  doc:=public.admin_record_write('users',p_inst,p_id,p_changes);
  if p_roles is not null then perform public.admin_role_set(p_inst,(doc->>'id')::bigint,p_roles); end if;
  return public.admin_user_document(p_inst,(doc->>'id')::bigint);
end $$;
revoke all on function public.admin_account_write(bigint,bigint,jsonb,text[]) from public,anon;
grant execute on function public.admin_account_write(bigint,bigint,jsonb,text[]) to authenticated;
notify pgrst,'reload schema';
