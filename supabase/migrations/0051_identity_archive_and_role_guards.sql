create function public.admin_account_archive(p_inst bigint,p_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); target public.users%rowtype;
begin
 if not public.administrative_permission(p_inst,'roles.delete') or p_id=actor then raise exception 'No puedes archivar esa cuenta.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('admin-write:'||p_inst,0));
 select * into target from public.users where id=p_id and institution_id=p_inst for update;
 if target.id is null then raise exception 'Cuenta no encontrada.' using errcode='P0002'; end if;
 if exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_id and r.code='super_admin') and not public.has_role('super_admin')
   or exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=p_id and r.code='admin') and not (public.has_role('admin') or public.has_role('super_admin')) then raise exception 'Cuenta protegida.' using errcode='42501'; end if;
 update public.users set active=false,deleted_at=coalesce(deleted_at,clock_timestamp()),updated_at=clock_timestamp() where id=p_id;
 return public.admin_user_document(p_inst,p_id);
end $$;
create function public.admin_person_archive(p_inst bigint,p_kind text,p_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); module text; entity jsonb; linked public.users%rowtype; linked_person_id bigint;
begin
 module:=case p_kind when 'teachers' then 'teachers' when 'students' then 'students' when 'parents' then 'students' end;
 if module is null or not public.administrative_permission(p_inst,module||'.delete') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('admin-write:'||p_inst,0));
 entity:=public.admin_record_write(p_kind,p_inst,p_id,'{}');linked_person_id:=(entity->>'person_id')::bigint;
 for linked in select * from public.users u where u.person_id=linked_person_id and u.institution_id=p_inst for update loop
  if linked.id=actor or not public.user_management_permission(linked.id,'delete')
    or exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=linked.id and r.code='super_admin') and not public.has_role('super_admin')
    or exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=linked.id and r.code='admin') and not (public.has_role('admin') or public.has_role('super_admin')) then raise exception 'La cuenta vinculada está protegida.' using errcode='42501'; end if;
 end loop;
 if p_kind in('students','teachers') then perform public.admin_record_write(p_kind,p_inst,p_id,jsonb_build_object('active',false)); end if;
 update public.persons set deleted_at=coalesce(deleted_at,clock_timestamp()) where id=linked_person_id and institution_id=p_inst;
 update public.users u set active=false,deleted_at=coalesce(deleted_at,clock_timestamp()),updated_at=clock_timestamp() where u.person_id=linked_person_id and u.institution_id=p_inst;
 return jsonb_build_object('ok',true);
end $$;
create function public.admin_role_write(p_inst bigint,p_id bigint,p_changes jsonb,p_archive boolean default false) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); target public.roles%rowtype; updated public.roles%rowtype; permission text;
begin
 permission:=case when p_archive then 'roles.delete' when p_id is null then 'roles.create' else 'roles.edit' end;
 if not public.administrative_permission(p_inst,permission) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
 if p_archive is null or jsonb_typeof(p_changes) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p_changes) k where k not in('name','code','description','active','is_system')) then raise exception 'Rol inválido.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('admin-write:'||p_inst,0));
 if p_id is not null then
  select * into target from public.roles where id=p_id and institution_id=p_inst for update;
  if target.id is null then raise exception 'Rol no encontrado o global protegido.' using errcode='P0002'; end if;
  if p_changes?'code' and p_changes->>'code' is distinct from target.code and exists(select 1 from public.user_roles where role_id=p_id) then raise exception 'El código de un rol asignado es inmutable.' using errcode='22023'; end if;
  if (p_archive or p_changes?'active' and not (p_changes->>'active')::boolean) and exists(select 1 from public.user_roles where role_id=p_id and user_id=actor) then raise exception 'No puedes desactivar tu propio rol.' using errcode='42501'; end if;
 end if;
 updated:=jsonb_populate_record(target,p_changes);
 if (updated.code='super_admin' or target.code='super_admin') and not public.has_role('super_admin') then raise exception 'Rol reservado.' using errcode='42501'; end if;
 if (updated.code='admin' or target.code='admin') and not (public.has_role('admin') or public.has_role('super_admin')) then raise exception 'Rol administrativo protegido.' using errcode='42501'; end if;
 if nullif(trim(updated.name),'') is null or nullif(trim(updated.code),'') is null then raise exception 'Nombre y código requeridos.' using errcode='22023'; end if;
 if p_id is null then
  insert into public.roles(institution_id,name,code,description,active,is_system) values(p_inst,updated.name,updated.code,updated.description,coalesce(updated.active,true),false) returning * into updated;
 else
  update public.roles set name=updated.name,code=updated.code,description=updated.description,active=case when p_archive then false else coalesce(updated.active,true) end where id=p_id returning * into updated;
 end if;
 return to_jsonb(updated);
end $$;
revoke all on function public.admin_account_archive(bigint,bigint),public.admin_person_archive(bigint,text,bigint),public.admin_role_write(bigint,bigint,jsonb,boolean) from public,anon;
grant execute on function public.admin_account_archive(bigint,bigint),public.admin_person_archive(bigint,text,bigint),public.admin_role_write(bigint,bigint,jsonb,boolean) to authenticated;
notify pgrst,'reload schema';
