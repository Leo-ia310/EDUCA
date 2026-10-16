-- Secrets and pending sessions belong to service-only tables, never profiles.
create table if not exists public.auth_two_factor_settings (
 user_id bigint primary key references public.users(id) on delete cascade,
 enabled boolean not null default false,
 method text not null default 'email' check(method in ('email','totp')),
 secret text, pending_method text, pending_secret text,
 recovery_codes jsonb not null default '[]', verified_at timestamptz,
 failed_attempts int not null default 0, locked_until timestamptz
);
insert into public.auth_two_factor_settings(user_id,enabled,method,secret,pending_method,pending_secret,recovery_codes,failed_attempts,locked_until,verified_at)
 select id,coalesce(two_factor,false),coalesce(two_factor_method,'email'),two_factor_secret,two_factor_pending_method,two_factor_pending_secret,
 two_factor_recovery_codes,two_factor_failed_attempts,two_factor_locked_until,case when two_factor then now() end from public.users
 on conflict(user_id) do nothing;
update public.users set two_factor_secret=null,two_factor_pending_secret=null,two_factor_pending_method=null,two_factor_recovery_codes='[]'
 where two_factor_secret is not null or two_factor_pending_secret is not null or two_factor_pending_method is not null or two_factor_recovery_codes<>'[]'::jsonb;
alter table public.auth_two_factor_challenges add column if not exists purpose text not null default 'login' check(purpose in ('login','setup','disable'));
alter table public.auth_two_factor_challenges add column if not exists secret_snapshot text;
alter table public.auth_two_factor_challenges add column if not exists delivery_status text not null default 'ready';
-- Invalidate the old protocol's outstanding sessions without touching accounts.
update public.auth_two_factor_challenges set consumed_at=now(),session_payload='{}',auth_user_payload='{}' where consumed_at is null;
create table if not exists public.auth_two_factor_verified_sessions (
 session_id uuid primary key references auth.sessions(id) on delete cascade,
 user_id bigint not null references public.users(id) on delete cascade,
 verified_at timestamptz not null default now()
);
create index if not exists auth_2fa_verified_user on public.auth_two_factor_verified_sessions(user_id);
do $$ declare tbl text; begin
 foreach tbl in array array['auth_two_factor_settings','auth_two_factor_challenges','auth_two_factor_verified_sessions'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on public.%I from public,anon,authenticated',tbl);
  execute format('grant all on public.%I to service_role',tbl);
 end loop;
end $$;

create or replace function public.auth_2fa_begin(p_id uuid,p_user_id bigint,p_method text,p_purpose text,p_secret text,p_code_hash text,p_session jsonb,p_auth jsonb,p_replace uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u public.users%rowtype; s public.auth_two_factor_settings%rowtype; c public.auth_two_factor_challenges%rowtype; expiry timestamptz:=now()+interval '5 minutes';
begin
 select * into u from public.users where id=p_user_id for update;
 if u.id is null or not u.active or u.deleted_at is not null or not exists(select 1 from public.institutions where id=u.institution_id and active and deleted_at is null) then return jsonb_build_object('ok',false,'error','account_unavailable'); end if;
 insert into public.auth_two_factor_settings(user_id) values(u.id) on conflict do nothing;
 select * into s from public.auth_two_factor_settings where user_id=u.id;
 if s.locked_until>now() then return jsonb_build_object('ok',false,'error','locked'); end if;
 if p_method not in ('email','totp') or p_purpose not in ('setup','login','disable') then return jsonb_build_object('ok',false,'error','invalid'); end if;
 if p_purpose='setup' and s.enabled then return jsonb_build_object('ok',false,'error','already_enabled'); end if;
 if p_purpose<>'setup' and (not s.enabled or s.method<>p_method) then return jsonb_build_object('ok',false,'error','method_changed'); end if;
 if p_method='email' and p_code_hash is not null then
  if exists(select 1 from public.auth_two_factor_challenges where user_id=u.id and method='email' and created_at>now()-interval '60 seconds') then return jsonb_build_object('ok',false,'error','cooldown'); end if;
  if (select count(*) from public.auth_two_factor_challenges where user_id=u.id and method='email' and created_at>now()-interval '1 hour')>=5 then return jsonb_build_object('ok',false,'error','send_limit'); end if;
 end if;
 if p_replace is not null and not exists(select 1 from public.auth_two_factor_challenges where id=p_replace and user_id=u.id and purpose=p_purpose and consumed_at is null and expires_at>now()) then return jsonb_build_object('ok',false,'error','expired'); end if;
 if p_purpose='setup' then
  update public.auth_two_factor_settings set pending_method=p_method,pending_secret=p_secret where user_id=u.id;
 elsif p_method='totp' and (s.secret is null or s.secret is distinct from p_secret) then return jsonb_build_object('ok',false,'error','method_changed'); end if;
 if s.locked_until is not null and s.locked_until<=now() then update public.auth_two_factor_settings set failed_attempts=0,locked_until=null where user_id=u.id; end if;
 update public.auth_two_factor_challenges set consumed_at=now(),session_payload='{}',auth_user_payload='{}' where user_id=u.id and purpose=p_purpose and consumed_at is null;
 insert into public.auth_two_factor_challenges(id,user_id,institution_id,method,purpose,code_hash,secret_snapshot,session_payload,auth_user_payload,expires_at,delivery_status)
 values(p_id,u.id,u.institution_id,p_method,p_purpose,p_code_hash,p_secret,coalesce(p_session,'{}'),coalesce(p_auth,'{}'),expiry,case when p_method='email' then 'pending' else 'ready' end) returning * into c;
 return jsonb_build_object('ok',true,'id',c.id,'method',c.method,'expiresAt',c.expires_at,'resendAt',c.created_at+interval '60 seconds');
end $$;

create or replace function public.auth_2fa_verify(p_id uuid,p_user_id bigint,p_purpose text,p_hash text,p_totp_valid boolean,p_secret text,p_recovery_hash text,p_recovery_codes jsonb,p_session_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u public.users%rowtype; s public.auth_two_factor_settings%rowtype; c public.auth_two_factor_challenges%rowtype; valid boolean:=false; result jsonb; sid uuid; lock_until timestamptz;
begin
 select * into c from public.auth_two_factor_challenges where id=p_id;
 if c.id is null or c.purpose<>p_purpose or (p_user_id is not null and c.user_id<>p_user_id) or (p_user_id is null and p_purpose<>'login') then return jsonb_build_object('ok',false,'error','invalid'); end if;
 select * into u from public.users where id=c.user_id for update;
 select * into c from public.auth_two_factor_challenges where id=p_id for update;
 select * into s from public.auth_two_factor_settings where user_id=u.id;
 if not u.active or u.deleted_at is not null or not exists(select 1 from public.institutions where id=u.institution_id and active and deleted_at is null) then return jsonb_build_object('ok',false,'error','account_unavailable'); end if;
 if c.consumed_at is not null then return jsonb_build_object('ok',false,'error','used'); end if;
 if c.expires_at<=now() then return jsonb_build_object('ok',false,'error','expired'); end if;
 if c.delivery_status not in ('sent','ready') then return jsonb_build_object('ok',false,'error','not_sent'); end if;
 sid:=case when p_purpose='login' then (c.session_payload->>'session_id')::uuid else p_session_id end;
 if p_purpose<>'disable' and (sid is null or not exists(select 1 from auth.sessions where id=sid and user_id=u.auth_user_id)) then return jsonb_build_object('ok',false,'error','invalid'); end if;
 if s.locked_until>now() or c.failed_attempts>=5 then return jsonb_build_object('ok',false,'error','locked'); end if;
 if p_purpose='setup' then
  if s.enabled or s.pending_method is distinct from c.method or s.pending_secret is distinct from c.secret_snapshot then return jsonb_build_object('ok',false,'error','method_changed'); end if;
 elsif not s.enabled or s.method<>c.method or (c.method='totp' and s.secret is distinct from c.secret_snapshot) then return jsonb_build_object('ok',false,'error','method_changed'); end if;
 if p_recovery_hash is not null and p_purpose<>'setup' then
  valid:=s.recovery_codes ? p_recovery_hash;
 elsif c.method='email' then valid:=coalesce(c.code_hash=p_hash,false);
 else valid:=coalesce(p_totp_valid,false) and p_secret is not distinct from c.secret_snapshot; end if;
 if not valid then
  update public.auth_two_factor_challenges set failed_attempts=failed_attempts+1 where id=c.id;
  update public.auth_two_factor_settings set failed_attempts=case when locked_until<=now() then 1 else failed_attempts+1 end,
   locked_until=case when (case when locked_until<=now() then 1 else failed_attempts+1 end)>=5 then now()+interval '15 minutes' else null end where user_id=u.id returning locked_until into lock_until;
  return jsonb_build_object('ok',false,'error',case when lock_until>now() then 'locked' else 'incorrect' end);
 end if;
 if p_purpose='setup' then
  if jsonb_typeof(p_recovery_codes)<>'array' or jsonb_array_length(p_recovery_codes)<>10 then return jsonb_build_object('ok',false,'error','invalid'); end if;
  update public.auth_two_factor_settings set enabled=true,method=c.method,secret=c.secret_snapshot,pending_method=null,pending_secret=null,
   recovery_codes=p_recovery_codes,verified_at=now(),failed_attempts=0,locked_until=null where user_id=u.id;
  update public.users set two_factor=true,two_factor_method=c.method where id=u.id;
 elsif p_purpose='disable' then
  update public.auth_two_factor_settings set enabled=false,method='email',secret=null,pending_method=null,pending_secret=null,recovery_codes='[]',verified_at=null,failed_attempts=0,locked_until=null where user_id=u.id;
  update public.users set two_factor=false,two_factor_method='email' where id=u.id;
  delete from public.auth_two_factor_verified_sessions where user_id=u.id;
 else
  update public.auth_two_factor_settings set recovery_codes=case when p_recovery_hash is null then recovery_codes else recovery_codes-p_recovery_hash end,failed_attempts=0,locked_until=null where user_id=u.id;
  update public.users set last_sign_in=now(),failed_attempts=0 where id=u.id;
 end if;
 -- Enrollment validates the current session; login validates only its withheld session.
 if p_purpose<>'disable' and sid is not null and exists(select 1 from auth.sessions where id=sid and user_id=u.auth_user_id) then
  insert into public.auth_two_factor_verified_sessions(session_id,user_id) values(sid,u.id) on conflict(session_id) do update set verified_at=now();
 end if;
 result:=jsonb_build_object('ok',true,'userId',u.id,'method',c.method,'session',c.session_payload,'authUser',c.auth_user_payload);
 update public.auth_two_factor_challenges set consumed_at=now(),session_payload='{}',auth_user_payload='{}',code_hash=null,secret_snapshot=null
 where user_id=u.id and consumed_at is null and (id=c.id or p_purpose in ('setup','disable'));
 return result;
end $$;
revoke all on function public.auth_2fa_begin(uuid,bigint,text,text,text,text,jsonb,jsonb,uuid),public.auth_2fa_verify(uuid,bigint,text,text,boolean,text,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.auth_2fa_begin(uuid,bigint,text,text,text,text,jsonb,jsonb,uuid),public.auth_2fa_verify(uuid,bigint,text,text,boolean,text,text,jsonb,uuid) to service_role;

-- A password-only Supabase token cannot bypass the backend's second step.
create or replace function public.auth_2fa_session_allowed() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select not coalesce(s.enabled,false) or exists(select 1 from public.auth_two_factor_verified_sessions v
  where v.user_id=u.id and v.session_id::text=auth.jwt()->>'session_id')
 from public.users u left join public.auth_two_factor_settings s on s.user_id=u.id
 where u.auth_user_id=auth.uid() and u.active and u.deleted_at is null),false);
$$;
revoke all on function public.auth_2fa_session_allowed() from public,anon;
grant execute on function public.auth_2fa_session_allowed() to authenticated,service_role;
-- Existing SECURITY DEFINER business RPCs also scope themselves with this helper.
create or replace function public.current_institution_id() returns bigint language sql stable as $$
 select case when auth.uid() is null or public.auth_2fa_session_allowed() then coalesce(
  nullif(current_setting('request.jwt.claims',true)::jsonb->>'institution_id','')::bigint,
  (current_setting('request.jwt.claims',true)::jsonb->'app_metadata'->>'institution_id')::bigint
 ) end;
$$;
do $$ declare tbl text; begin
 for tbl in select t.tablename from pg_tables t where t.schemaname='public' and t.tablename not like 'auth_%'
 and exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t.tablename and c.relrowsecurity) loop
  execute format('drop policy if exists auth_second_factor on public.%I',tbl);
  execute format('create policy auth_second_factor on public.%I as restrictive for all to authenticated using(public.auth_2fa_session_allowed()) with check(public.auth_2fa_session_allowed())',tbl);
 end loop;
end $$;
drop policy if exists auth_second_factor on storage.objects;
create policy auth_second_factor on storage.objects as restrictive for all to authenticated using(public.auth_2fa_session_allowed()) with check(public.auth_2fa_session_allowed());
create or replace function public.guard_two_factor_profile() returns trigger language plpgsql as $$
begin
 if current_user in ('authenticated','anon') and (
  (tg_op='UPDATE' and (new.two_factor is distinct from old.two_factor or new.two_factor_method is distinct from old.two_factor_method))
  or (tg_op='INSERT' and new.two_factor=true) or new.two_factor_secret is not null or new.two_factor_pending_secret is not null
  or new.two_factor_pending_method is not null or new.two_factor_recovery_codes<>'[]'::jsonb) then
  raise exception 'La configuración 2FA solo puede cambiarse mediante una verificación.' using errcode='42501'; end if;
 return new;
end $$;
drop trigger if exists two_factor_profile_guard on public.users;
create trigger two_factor_profile_guard before insert or update on public.users for each row execute function public.guard_two_factor_profile();
notify pgrst,'reload schema';
