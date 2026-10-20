-- Auth and PostgreSQL cannot share a transaction. Reserve the Auth UUID and
-- keep the request durably, so a crash never leaves an untracked account.
create table public.admin_provisionings(
 id uuid primary key default gen_random_uuid(), institution_id bigint not null references public.institutions(id) on delete cascade,
 actor_id bigint not null references public.users(id) on delete cascade, request_key uuid not null,
 kind text not null check(kind in('students','teachers','parents','profile')),
 email text not null, auth_user_id uuid not null unique default gen_random_uuid(),
 request_hash bytea not null, payload jsonb not null, status text not null default 'pending' check(status in('pending','completed','needs_review','cancelled')),
 observed_auth_user_id uuid, result jsonb, retired_at timestamptz, created_at timestamptz not null default clock_timestamp(), updated_at timestamptz not null default clock_timestamp(),
 unique(institution_id,actor_id,request_key)
);
create unique index admin_provisionings_email on public.admin_provisionings(lower(email)) where retired_at is null;
create index admin_provisionings_pending on public.admin_provisionings(updated_at) where status in('pending','needs_review');
alter table public.admin_provisionings enable row level security;
revoke all on public.admin_provisionings from public,anon,authenticated;

create function public.admin_provision_authorize(p_inst bigint,p_kind text,p_payload jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare module text; account jsonb:=p_payload->'account'; caller public.users%rowtype; ids bigint[]; current_year bigint; role_code text; code text;
begin
 module:=case p_kind when 'teachers' then 'teachers' when 'students' then 'students' when 'parents' then 'students' when 'profile' then 'roles' end;
 if module is null or not public.administrative_permission(p_inst,module||'.create') then raise exception 'No puedes crear esa cuenta.' using errcode='42501'; end if;
 if jsonb_typeof(p_payload) is distinct from 'object' or jsonb_typeof(account) is distinct from 'object'
   or nullif(trim(account->>'full_name'),'') is null or length(account->>'full_name')>200 or length(account->>'email')>150
   or coalesce(account->>'email','')!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or exists(select 1 from jsonb_object_keys(account) k where k not in('email','full_name','username','phone','active','admin_permissions')) then
  raise exception 'Datos de cuenta inválidos.' using errcode='22023'; end if;
 if p_kind='profile' then
  role_code:=p_payload->>'roleCode';
  if role_code is null or role_code not in('admin','coordinator','director') then raise exception 'Perfil inválido.' using errcode='22023'; end if;
  if role_code='admin' and not (public.has_role('admin') or public.has_role('super_admin')) then raise exception 'No puedes crear administradores.' using errcode='42501'; end if;
  if jsonb_typeof(account->'admin_permissions') is distinct from 'array' or jsonb_array_length(account->'admin_permissions')>100 then raise exception 'Permisos inválidos.' using errcode='22023'; end if;
  select * into caller from public.users where id=public.current_user_id();
  if not public.has_role('super_admin') and caller.admin_permissions is not null and exists(select 1 from jsonb_array_elements_text(account->'admin_permissions') p where not p=any(caller.admin_permissions)) then raise exception 'Permisos superiores a los del creador.' using errcode='42501'; end if;
 else
  if account?'admin_permissions' then raise exception 'Un perfil académico no concede permisos administrativos.' using errcode='42501'; end if;
  if jsonb_typeof(p_payload->'person') is distinct from 'object' or jsonb_typeof(p_payload->'entity') is distinct from 'object' or jsonb_typeof(p_payload->'relations') is distinct from 'object'
    or nullif(trim(p_payload->'person'->>'first_name'),'') is null or nullif(trim(p_payload->'person'->>'last_name'),'') is null then raise exception 'Persona inválida.' using errcode='22023'; end if;
  if p_kind in('students','teachers') and nullif(trim(p_payload->'entity'->>case p_kind when 'students' then 'student_code' else 'teacher_code' end),'') is null then raise exception 'Código requerido.' using errcode='22023'; end if;
  select id into current_year from public.academic_years where institution_id=p_inst and is_current and active order by id desc limit 1;
  if p_kind='students' and p_payload->'relations'?'groupId' and p_payload->'relations'->>'groupId' is not null and not exists(select 1 from public.groups g
    where g.id=(p_payload->'relations'->>'groupId')::bigint and g.institution_id=p_inst and g.academic_year_id=current_year and g.active) then raise exception 'Salón inválido.' using errcode='22023'; end if;
  if p_kind='parents' and p_payload->'relations'?'childIds' then
   if jsonb_typeof(p_payload->'relations'->'childIds')<>'array' or jsonb_array_length(p_payload->'relations'->'childIds')>5000 then raise exception 'Hijos inválidos.' using errcode='22023'; end if;
   if exists(select 1 from jsonb_array_elements_text(p_payload->'relations'->'childIds') requested(id) where not exists(select 1 from public.students s where s.id=requested.id::bigint and s.institution_id=p_inst)) then raise exception 'Estudiante fuera de la institución.' using errcode='22023'; end if;
  end if;
  if p_kind='teachers' and p_payload->'relations'?'classIds' then
   if jsonb_typeof(p_payload->'relations'->'classIds')<>'array' or jsonb_array_length(p_payload->'relations'->'classIds')>1000 then raise exception 'Clases inválidas.' using errcode='22023'; end if;
   if jsonb_array_length(p_payload->'relations'->'classIds')>0 and not public.administrative_permission(p_inst,'classes.edit') then raise exception 'No puedes asignar clases.' using errcode='42501'; end if;
   if exists(select 1 from jsonb_array_elements_text(p_payload->'relations'->'classIds') requested(id) where not exists(select 1 from public.classes c
     where c.id=requested.id::bigint and c.institution_id=p_inst and c.active and c.academic_year_id=current_year)) then raise exception 'Clase fuera del año actual.' using errcode='22023'; end if;
  end if;
 end if;
end $$;
revoke all on function public.admin_provision_authorize(bigint,text,jsonb) from public,anon,authenticated;

create function public.admin_provision_begin(p_inst bigint,p_kind text,p_key uuid,p_payload jsonb,p_password_proof text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); job public.admin_provisionings%rowtype; fingerprint bytea; mail text;
begin
 perform public.admin_provision_authorize(p_inst,p_kind,p_payload);
 if p_key is null or p_password_proof is null or p_password_proof!~'^[0-9a-f]{64}$' then raise exception 'Solicitud inválida.' using errcode='22023'; end if;
 mail:=lower(trim(p_payload->'account'->>'email'));
 fingerprint:=sha256(convert_to(jsonb_build_object('kind',p_kind,'payload',p_payload,'passwordProof',p_password_proof)::text,'UTF8'));
 perform pg_advisory_xact_lock(hashtextextended('provision-email:'||mail,0));
 select * into job from public.admin_provisionings where institution_id=p_inst and actor_id=actor and request_key=p_key for update;
 if found then
  if job.request_hash<>fingerprint then raise exception 'La solicitud ya tiene otro contenido.' using errcode='23505'; end if;
  if job.status in('cancelled','needs_review') then raise exception 'La solicitud requiere revisión administrativa.' using errcode='22023'; end if;
 else
  if exists(select 1 from public.users where institution_id=p_inst and lower(email)=mail and deleted_at is null) then raise exception 'La cuenta ya existe.' using errcode='23505'; end if;
  if nullif(p_payload->'account'->>'username','') is not null and exists(select 1 from public.users where username=p_payload->'account'->>'username') then raise exception 'Nombre de acceso ocupado.' using errcode='23505'; end if;
  -- Keep the old receipt, but permit explicit account recreation after an Auth deletion.
  update public.admin_provisionings p set retired_at=clock_timestamp() where lower(p.email)=mail and p.status='completed' and p.retired_at is null
    and not exists(select 1 from auth.users u where u.id=p.auth_user_id);
  insert into public.admin_provisionings(institution_id,actor_id,request_key,kind,email,request_hash,payload)
   values(p_inst,actor,p_key,p_kind,mail,fingerprint,p_payload) returning * into job;
 end if;
 return jsonb_build_object('id',job.id,'authUserId',job.auth_user_id,'email',job.email,'status',job.status,'result',job.result);
end $$;
revoke all on function public.admin_provision_begin(bigint,text,uuid,jsonb,text) from public,anon;
grant execute on function public.admin_provision_begin(bigint,text,uuid,jsonb,text) to authenticated;

create function public.admin_provision_complete(p_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); job public.admin_provisionings%rowtype; person jsonb; entity jsonb; account jsonb; role_code text; created jsonb;
begin
 select * into job from public.admin_provisionings where id=p_id;
 if job.id is null or job.actor_id<>actor and not public.has_role('super_admin') then raise exception 'Solicitud no autorizada.' using errcode='42501'; end if;
 perform public.admin_provision_authorize(job.institution_id,job.kind,job.payload);
 perform pg_advisory_xact_lock(hashtextextended('admin-write:'||job.institution_id,0));
 select * into job from public.admin_provisionings where id=p_id for update;
 if job.status='completed' then return job.result; end if;
 if job.status<>'pending' then raise exception 'La solicitud requiere revisión.' using errcode='22023'; end if;
 if not exists(select 1 from auth.users u where u.id=job.auth_user_id and lower(u.email)=job.email
   and u.raw_app_meta_data->>'provisioning_id'=job.id::text and u.raw_app_meta_data->>'institution_id'=job.institution_id::text) then raise exception 'Auth todavía no confirmó la identidad reservada.' using errcode='22023'; end if;
 account:=job.payload->'account';
 if job.kind='profile' then role_code:=job.payload->>'roleCode';
 else
  if job.kind='teachers' then perform pg_advisory_xact_lock(hashtextextended('schedule-write:'||job.institution_id,0)); end if;
  person:=public.admin_record_write('persons',job.institution_id,null,job.payload->'person');
  entity:=public.admin_record_write(job.kind,job.institution_id,null,(job.payload->'entity')||jsonb_build_object('person_id',(person->>'id')::bigint));
  perform public.admin_people_relations(job.institution_id,job.kind,(entity->>'id')::bigint,job.payload->'relations');
  account:=account||jsonb_build_object('person_id',(person->>'id')::bigint);
  role_code:=case job.kind when 'students' then 'student' when 'teachers' then 'teacher' else 'parent' end;
 end if;
 account:=account||jsonb_build_object('email',job.email,'auth_user_id',job.auth_user_id);
 created:=public.admin_record_write('users',job.institution_id,null,account);
 perform public.admin_role_set(job.institution_id,(created->>'id')::bigint,array[role_code]);
 created:=public.admin_user_document(job.institution_id,(created->>'id')::bigint);
 job.result:=jsonb_build_object('user',created,'entity',case when entity is null then null else entity||jsonb_build_object('persons',person) end);
 update public.admin_provisionings set status='completed',result=job.result,updated_at=clock_timestamp() where id=p_id;
 return job.result;
end $$;
revoke all on function public.admin_provision_complete(uuid) from public,anon;
grant execute on function public.admin_provision_complete(uuid) to authenticated;
-- An ambiguous external result is retained for retry/reconciliation. Operators
-- inspect this table with the service role; no browser can alter or erase it.
grant select,update on public.admin_provisionings to service_role;
notify pgrst,'reload schema';

create function public.admin_provision_observe(p_id uuid,p_auth_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
declare job public.admin_provisionings%rowtype; actor bigint:=public.chat_actor();
begin
 select * into job from public.admin_provisionings where id=p_id for update;
 if job.id is null or job.actor_id<>actor then raise exception 'Solicitud no autorizada.' using errcode='42501'; end if;
 perform public.admin_provision_authorize(job.institution_id,job.kind,job.payload);
 if not exists(select 1 from auth.users u where u.id=p_auth_id and lower(u.email)=job.email and u.raw_app_meta_data->>'provisioning_id'=p_id::text)
  then raise exception 'Identidad externa no verificada.' using errcode='42501'; end if;
 if job.status='pending' then update public.admin_provisionings set observed_auth_user_id=p_auth_id,
  status=case when auth_user_id=p_auth_id then status else 'needs_review' end,updated_at=clock_timestamp() where id=p_id; end if;
 return true;
end $$;
create function public.admin_provision_reject(p_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
declare job public.admin_provisionings%rowtype; actor bigint:=public.chat_actor();
begin
 select * into job from public.admin_provisionings where id=p_id for update;
 if job.id is null or job.actor_id<>actor then raise exception 'Solicitud no autorizada.' using errcode='42501'; end if;
 perform public.admin_provision_authorize(job.institution_id,job.kind,job.payload);
 -- Used only after an explicit provider 4xx, never after a lost response.
 if job.status='pending' and job.observed_auth_user_id is null and not exists(select 1 from auth.users where id=job.auth_user_id) then
  update public.admin_provisionings set status='cancelled',retired_at=clock_timestamp(),updated_at=clock_timestamp() where id=p_id; return true;
 end if;
 return false;
end $$;
revoke all on function public.admin_provision_observe(uuid,uuid),public.admin_provision_reject(uuid) from public,anon;
grant execute on function public.admin_provision_observe(uuid,uuid),public.admin_provision_reject(uuid) to authenticated;
notify pgrst,'reload schema';
