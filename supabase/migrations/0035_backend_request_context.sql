-- Service-only RPC called AFTER Supabase Auth verifies the exact bearer token.
-- Business queries still run under the caller's JWT/RLS. No context is cached
-- between requests, so role, account, session and MFA revocation remain live.
create table public.backend_user_quotas (
  user_id bigint primary key references public.users(id) on delete cascade,
  count integer not null check(count>=0),
  resets_at timestamptz not null
);
alter table public.backend_user_quotas enable row level security;
revoke all on public.backend_user_quotas from public,anon,authenticated;
grant all on public.backend_user_quotas to service_role;

create or replace function public.backend_request_context(p_auth_user_id uuid,p_session_id uuid,
  p_window_ms integer default 900000,p_limit integer default 1200)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor public.users%rowtype; codes text[]; permissions jsonb; quota public.backend_user_quotas%rowtype;
  at_time timestamptz:=clock_timestamp();
begin
  if p_window_ms is null or p_window_ms<1 or p_window_ms>86400000 or p_limit is null or p_limit<1 or p_limit>1000000 then
    raise exception 'Configuración de cupo inválida.' using errcode='22023';
  end if;
  if p_auth_user_id is null or p_session_id is null or not exists(
    select 1 from auth.sessions where id=p_session_id and user_id=p_auth_user_id) then
    raise exception 'Sesión inválida o revocada.' using errcode='28000';
  end if;
  select u.* into actor from public.users u join public.institutions i on i.id=u.institution_id
    where u.auth_user_id=p_auth_user_id and u.active and u.deleted_at is null and i.active and i.deleted_at is null;
  if actor.id is null then raise exception 'Cuenta no disponible.' using errcode='42501'; end if;
  if exists(select 1 from public.auth_two_factor_settings where user_id=actor.id and enabled)
    and not exists(select 1 from public.auth_two_factor_verified_sessions where session_id=p_session_id and user_id=actor.id) then
    raise exception 'Completa la verificación de seguridad e inicia sesión nuevamente.' using errcode='42501',detail='two_factor_required';
  end if;
  select array_agg(distinct r.code order by r.code) into codes from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=actor.id and (ur.institution_id=actor.institution_id or ur.institution_id is null)
      and (r.institution_id=actor.institution_id or r.institution_id is null);
  if coalesce(array_length(codes,1),0)=0 then raise exception 'Usuario sin roles asignados.' using errcode='42501'; end if;

  -- A single row per account serializes increments across every backend process.
  -- Return denial instead of raising: raising would roll back the increment.
  insert into public.backend_user_quotas(user_id,count,resets_at)
    values(actor.id,1,at_time+make_interval(secs=>p_window_ms/1000.0))
    on conflict(user_id) do update set
      count=case when backend_user_quotas.resets_at<=at_time then 1 else least(backend_user_quotas.count+1,1000001) end,
      resets_at=case when backend_user_quotas.resets_at<=at_time then excluded.resets_at else backend_user_quotas.resets_at end
    returning * into quota;
  if quota.count>p_limit then
    return jsonb_build_object('allowed',false,'retryAfterSeconds',greatest(1,ceil(extract(epoch from quota.resets_at-at_time))),
      'limit',p_limit,'remaining',0,'resetsAt',quota.resets_at);
  end if;

  select jsonb_object_agg(permission,public.portal_permission_for_user(actor.id,permission)) into permissions
    from unnest(array['grades.view','payments.view','attendance.view','schedule.view','assignments.view','assignments.submit',
      'reports.view','reports.download','announcements.view','messages.send','materials.view']) permission;
  return jsonb_build_object('allowed',true,'authUserId',actor.auth_user_id,'sessionId',p_session_id,
    'userId',actor.id,'institutionId',actor.institution_id,'personId',actor.person_id,'fullName',actor.full_name,
    'roles',codes,'adminPermissions',actor.admin_permissions,'portalPermissions',permissions,
    'teacherId',(select id from public.teachers where person_id=actor.person_id and institution_id=actor.institution_id and active order by id limit 1),
    'studentId',(select id from public.students where person_id=actor.person_id and institution_id=actor.institution_id and active order by id limit 1),
    'parentId',(select id from public.parents where person_id=actor.person_id and institution_id=actor.institution_id order by id limit 1),
    'limit',p_limit,'remaining',greatest(0,p_limit-quota.count),'resetsAt',quota.resets_at);
end $$;
revoke all on function public.backend_request_context(uuid,uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.backend_request_context(uuid,uuid,integer,integer) to service_role;
