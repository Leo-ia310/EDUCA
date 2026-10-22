-- Keep live role, tenant and optional MFA checks; remove nested role lookups
-- repeated by the InitPlans of an academic query. No cross-request cache.
create or replace function public.current_roles() returns text[]
language sql stable security definer set search_path=public as $$
  with actor as materialized (
    select u.id,u.institution_id from public.users u
    where u.auth_user_id=(select auth.uid()) and u.active and u.deleted_at is null
      and u.institution_id=(select public.current_institution_id())
  )
  select coalesce(array_agg(distinct r.code order by r.code),array[]::text[])
  from actor u join public.user_roles ur on ur.user_id=u.id
  join public.roles r on r.id=ur.role_id and r.active
  where (ur.institution_id is null or ur.institution_id=u.institution_id)
    and (r.institution_id is null or r.institution_id=u.institution_id)
$$;

create or replace function public.portal_staff(p_user_id bigint) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.users u
    join public.institutions i on i.id=u.institution_id and i.active and i.deleted_at is null
    join public.user_roles ur on ur.user_id=u.id
    join public.roles r on r.id=ur.role_id and r.active
    where u.id=p_user_id and u.active and u.deleted_at is null
      and r.code=any(array['teacher','admin','coordinator','director','super_admin']::text[])
      and (ur.institution_id is null or ur.institution_id=u.institution_id)
      and (r.institution_id is null or r.institution_id=u.institution_id)
  )
$$;

create or replace function public.class_admin_actor() returns boolean
language sql stable security definer set search_path=public as $$
  select public.current_roles() && array['admin','coordinator','director','super_admin']::text[]
$$;

create or replace function public.is_teacher_actor() returns boolean
language sql stable security definer set search_path=public as $$
  with roles as materialized (select public.current_roles() codes)
  select 'teacher'=any(codes)
    and not codes && array['admin','coordinator','director','super_admin']::text[] from roles
$$;
