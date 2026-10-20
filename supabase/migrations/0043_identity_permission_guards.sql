-- Module grants must also govern direct Data API writes, including accounts
-- with more than one role. Platform privileges cannot be self-assigned.
do $$ declare tbl text; cmd text; expr text; code text; begin
  foreach tbl in array array['roles','user_roles'] loop
    foreach cmd in array array['insert','update','delete'] loop
      code:=case when tbl='user_roles' then 'roles.edit' when cmd='insert' then 'roles.create' when cmd='update' then 'roles.edit' else 'roles.delete' end;
      expr:=format('public.administrative_permission(institution_id,%L)',code);
      if tbl='roles' then expr:=expr||' and (code<>''super_admin'' or public.has_role(''super_admin''))';
      else expr:=expr||' and exists(select 1 from public.users target join public.roles target_role on target_role.id=role_id
        where target.id=user_id and target.institution_id=public.user_roles.institution_id
          and (target_role.institution_id is null or target_role.institution_id=target.institution_id)
          and (target_role.code<>''super_admin'' or public.has_role(''super_admin'')))'; end if;
      if cmd='insert' then execute format('create policy identity_module_insert on public.%I as restrictive for insert to authenticated with check(%s)',tbl,expr);
      elsif cmd='update' then execute format('create policy identity_module_update on public.%I as restrictive for update to authenticated using(%s) with check(%s)',tbl,expr,expr);
      else execute format('create policy identity_module_delete on public.%I as restrictive for delete to authenticated using(%s)',tbl,expr); end if;
    end loop;
  end loop;
end $$;

create or replace function public.user_management_permission(p_user_id bigint,p_action text) returns boolean
language sql stable security definer set search_path=public as $$
  select p_action in('edit','delete') and exists(select 1 from public.users target where target.id=p_user_id and (
    public.administrative_permission(target.institution_id,'roles.'||p_action) or not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_id=target.id and r.code in('admin','director','coordinator','super_admin')
        and (ur.institution_id is null or ur.institution_id=target.institution_id) and (r.institution_id is null or r.institution_id=target.institution_id)) and (
      public.administrative_permission(target.institution_id,'students.'||p_action) and (exists(select 1 from public.students s where s.person_id=target.person_id and s.institution_id=target.institution_id)
        or exists(select 1 from public.parents p where p.person_id=target.person_id and p.institution_id=target.institution_id))
      or public.administrative_permission(target.institution_id,'teachers.'||p_action) and exists(select 1 from public.teachers t where t.person_id=target.person_id and t.institution_id=target.institution_id))))
$$;
revoke all on function public.user_management_permission(bigint,text) from public,anon;
grant execute on function public.user_management_permission(bigint,text) to authenticated;
create policy user_module_delete on public.users as restrictive for delete to authenticated using(public.user_management_permission(id,'delete'));

create or replace function public.guard_collaboration_identity() returns trigger language plpgsql security definer set search_path=public as $$
declare can_manage boolean;
begin
  if auth.uid() is null then return new; end if; -- Trusted backend provisioning.
  if new.auth_user_id is distinct from old.auth_user_id or new.person_id is distinct from old.person_id or new.institution_id is distinct from old.institution_id then
    raise exception 'La identidad de la cuenta solo se gestiona desde el backend.' using errcode='42501';
  end if;
  can_manage:=public.user_management_permission(old.id,'edit') or
    ((new.active=false and old.active is distinct from false or new.deleted_at is not null and old.deleted_at is null)
      and public.user_management_permission(old.id,'delete'));
  if not can_manage and (old.auth_user_id is distinct from auth.uid() or new.admin_permissions is distinct from old.admin_permissions
    or new.active is distinct from old.active or new.deleted_at is distinct from old.deleted_at) then
    raise exception 'No puedes cambiar la identidad ni los permisos de esta cuenta.' using errcode='42501';
  end if;
  return new;
end $$;
