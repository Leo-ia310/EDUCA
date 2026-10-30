-- Effective switches for the family-user editor, without impersonating a user
-- or exposing another institution's settings. Global rules are never rewritten.
create function public.portal_user_permissions(p_user_id bigint) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare inst bigint:=public.current_institution_id(); result jsonb;
begin
  if not public.class_admin_actor() or not public.admin_can('roles.edit') then
    raise exception 'No tienes permiso para gestionar accesos.' using errcode='42501';
  end if;
  if not exists(select 1 from public.users u where u.id=p_user_id and u.institution_id=inst
      and u.active and u.deleted_at is null and not public.portal_staff(u.id)) then
    raise exception 'Usuario fuera de tu institución o perfil de personal.' using errcode='42501';
  end if;
  select jsonb_build_object('userId',p_user_id,
    'permissions',(select jsonb_object_agg(code,public.portal_permission_for_user(p_user_id,code))
      from unnest(array['grades.view','payments.view','attendance.view','schedule.view','assignments.view',
        'assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view']) code),
    'overrides',(select coalesce(jsonb_object_agg(permission,allowed),'{}'::jsonb)
      from public.portal_permission_rules where institution_id=inst and scope='user' and user_id=p_user_id)) into result;
  return result;
end $$;

create function public.manage_portal_user_permissions(p_user_id bigint,p_changes jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare change jsonb;
begin
  -- Validate authorization and target before accepting any writes.
  perform public.portal_user_permissions(p_user_id);
  if jsonb_typeof(p_changes) is distinct from 'array' then
    raise exception 'Indica los permisos y su estado.' using errcode='22023';
  end if;
  if jsonb_array_length(p_changes) not between 1 and 11 then
    raise exception 'Selecciona entre uno y once permisos.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_changes) v
    where jsonb_typeof(v) is distinct from 'object'
      or jsonb_typeof(v->'allowed') is distinct from 'boolean'
      or (v->>'permission') is null or (v->>'permission') not in (
        'grades.view','payments.view','attendance.view','schedule.view','assignments.view',
        'assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view'))
    or (select count(distinct v->>'permission') from jsonb_array_elements(p_changes) v)<>jsonb_array_length(p_changes) then
    raise exception 'Indica permisos válidos y su estado, sin repetir.' using errcode='22023';
  end if;
  for change in select value from jsonb_array_elements(p_changes) loop
    perform public.manage_portal_access('save_permission',jsonb_build_object(
      'scope','user','userId',p_user_id,'permission',change->>'permission','allowed',change->'allowed'));
  end loop;
  return public.portal_user_permissions(p_user_id);
end $$;
revoke all on function public.portal_user_permissions(bigint),public.manage_portal_user_permissions(bigint,jsonb) from public,anon;
grant execute on function public.portal_user_permissions(bigint),public.manage_portal_user_permissions(bigint,jsonb) to authenticated;
notify pgrst,'reload schema';
