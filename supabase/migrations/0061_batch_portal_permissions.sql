-- Save multiple module permissions atomically. Reuse the existing authorized
-- single-rule writer so tenant/role/user checks, precedence, audit and realtime
-- revisions remain identical. Existing clients can still save single rules.
create function public.manage_portal_permissions(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare codes jsonb:=p_payload->'permissions'; code text;
begin
  if not public.class_admin_actor() or not public.admin_can('roles.edit') then
    raise exception 'No tienes permiso para gestionar accesos.' using errcode='42501';
  end if;
  if jsonb_typeof(codes) is distinct from 'array' then
    raise exception 'Selecciona uno o varios permisos.' using errcode='22023';
  end if;
  if jsonb_array_length(codes) not between 1 and 11
      or jsonb_typeof(p_payload->'allowed') is distinct from 'boolean' then
    raise exception 'Indica los permisos y si están habilitados.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(codes) value where jsonb_typeof(value)<>'string')
      or (select count(distinct value) from jsonb_array_elements_text(codes) value)<>jsonb_array_length(codes)
      or exists(select 1 from jsonb_array_elements_text(codes) value where value not in (
        'grades.view','payments.view','attendance.view','schedule.view','assignments.view',
        'assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view')) then
    raise exception 'Selecciona permisos válidos, sin repetir.' using errcode='22023';
  end if;
  for code in select jsonb_array_elements_text(codes) loop
    perform public.manage_portal_access('save_permission',(p_payload-'permissions')||jsonb_build_object('permission',code));
  end loop;
  return public.portal_access_admin();
end $$;
revoke all on function public.manage_portal_permissions(jsonb) from public,anon;
grant execute on function public.manage_portal_permissions(jsonb) to authenticated;
notify pgrst,'reload schema';
