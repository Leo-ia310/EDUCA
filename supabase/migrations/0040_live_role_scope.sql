-- Live roles are bound to both the user's institution and the role/grant's
-- institution; NULL denotes a global system role. Never trust stale JWT roles.
create or replace function public.user_has_role(p_user_id bigint,p_code text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users u join public.institutions i on i.id=u.institution_id and i.active and i.deleted_at is null
    join public.user_roles ur on ur.user_id=u.id join public.roles r on r.id=ur.role_id and r.active
    where u.id=p_user_id and u.active and u.deleted_at is null and r.code=p_code
      and (ur.institution_id is null or ur.institution_id=u.institution_id)
      and (r.institution_id is null or r.institution_id=u.institution_id))
$$;
revoke all on function public.user_has_role(bigint,text) from public,anon,authenticated;

create or replace function public.current_institution_id() returns bigint
language sql stable security definer set search_path=public as $$
  select u.institution_id from public.users u join public.institutions i on i.id=u.institution_id and i.active and i.deleted_at is null
  where u.auth_user_id=(select auth.uid()) and u.active and u.deleted_at is null
    and u.institution_id=coalesce(nullif(auth.jwt()->>'institution_id','')::bigint,(auth.jwt()->'app_metadata'->>'institution_id')::bigint)
    and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id and r.active where ur.user_id=u.id
      and (ur.institution_id is null or ur.institution_id=u.institution_id) and (r.institution_id is null or r.institution_id=u.institution_id))
    and public.auth_2fa_session_allowed()
$$;
create or replace function public.current_roles() returns text[]
language sql stable security definer set search_path=public as $$
  select coalesce(array_agg(distinct r.code order by r.code),array[]::text[])
    from public.users u join public.user_roles ur on ur.user_id=u.id join public.roles r on r.id=ur.role_id
    where u.auth_user_id=auth.uid() and u.institution_id=public.current_institution_id() and public.user_has_role(u.id,r.code)
      and r.active and (r.institution_id is null or r.institution_id=u.institution_id)
      and (ur.institution_id is null or ur.institution_id=u.institution_id)
$$;
create or replace function public.has_role(role_code text) returns boolean
language sql stable security definer set search_path=public as $$ select role_code=any(public.current_roles()) $$;
create or replace function public.portal_staff(p_user_id bigint) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from unnest(array['teacher','admin','coordinator','director','super_admin']) code where public.user_has_role(p_user_id,code))
$$;
create or replace function public.class_admin_actor() returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.institution_id=public.current_institution_id()
    and (public.user_has_role(u.id,'admin') or public.user_has_role(u.id,'coordinator') or public.user_has_role(u.id,'director') or public.user_has_role(u.id,'super_admin')))
$$;
create or replace function public.is_teacher_actor() returns boolean
language sql stable security definer set search_path=public as $$
  select not public.class_admin_actor() and exists(select 1 from public.users u where u.auth_user_id=auth.uid()
    and u.institution_id=public.current_institution_id() and public.user_has_role(u.id,'teacher'))
$$;
create or replace function public.class_permission(p_class_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.classes c join public.users u on u.institution_id=c.institution_id
    where c.id=p_class_id and c.active and c.institution_id=public.current_institution_id() and u.auth_user_id=auth.uid() and u.active and u.deleted_at is null
      and (public.class_admin_actor() or public.user_has_role(u.id,'teacher') and exists(select 1 from public.teachers t
        where t.person_id=u.person_id and t.institution_id=c.institution_id and t.active and (t.id=c.teacher_id
          or p_permission<>'collaborators.manage' and exists(select 1 from public.class_collaborators cc
            where cc.class_id=c.id and cc.institution_id=c.institution_id and cc.teacher_id=t.id and cc.teacher_user_id=u.id
              and cc.status='active' and p_permission=any(cc.permissions))))))
$$;

create or replace function public.administrative_permission(p_institution_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.institution_id=public.current_institution_id()
    and (public.user_has_role(u.id,'super_admin') or u.institution_id=p_institution_id
      and (public.user_has_role(u.id,'admin') or public.user_has_role(u.id,'coordinator') or public.user_has_role(u.id,'director'))
      and (u.admin_permissions is null or p_permission=any(u.admin_permissions))))
$$;
create or replace function public.schedule_admin_allowed(p_institution_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$ select public.administrative_permission(p_institution_id,p_permission) $$;
create or replace function public.admin_can(code text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users u where u.auth_user_id=auth.uid() and u.institution_id=public.current_institution_id()
    and (not public.class_admin_actor() or public.administrative_permission(u.institution_id,code)))
$$;

-- Exact family scope is separate from the staff-wide academic scope. A mixed
-- parent/admin account cannot use its parent exception for unrelated children.
create or replace function public.family_student_scope(p_student_id bigint,p_parent_only boolean default false) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users u join public.students s on s.institution_id=u.institution_id
    where u.auth_user_id=auth.uid() and u.institution_id=public.current_institution_id() and s.id=p_student_id
      and (not p_parent_only and public.user_has_role(u.id,'student') and s.person_id=u.person_id
        or public.user_has_role(u.id,'parent') and exists(select 1 from public.parents p join public.parent_students ps on ps.parent_id=p.id
          where p.institution_id=u.institution_id and p.person_id=u.person_id and ps.student_id=s.id)))
$$;
revoke all on function public.family_student_scope(bigint,boolean),public.administrative_permission(bigint,text),
  public.current_institution_id(),public.current_roles(),public.has_role(text) from public,anon;
grant execute on function public.family_student_scope(bigint,boolean),public.administrative_permission(bigint,text),
  public.current_institution_id(),public.current_roles(),public.has_role(text) to authenticated,service_role;

do $$ declare tbl text; cmd text; permission text; expr text; begin
  foreach tbl in array array['charges','payments','payment_concepts'] loop
    foreach cmd in array array['select','insert','update','delete'] loop
      permission:=case cmd when 'select' then 'payments.view' when 'insert' then 'payments.create' when 'update' then 'payments.edit' else 'payments.cancel' end;
      expr:=format('public.administrative_permission(institution_id,%L)',permission);
      if cmd='select' and tbl in('charges','payments') then expr:=expr||' or public.family_student_scope(student_id)'; end if;
      if cmd='select' and tbl='payment_concepts' then expr:=expr||' or public.has_role(''parent'') or public.has_role(''student'')'; end if;
      if cmd='insert' and tbl='payments' then expr:=expr||' or public.family_student_scope(student_id,true)'; end if;
      execute format('drop policy if exists admin_guard_%s on public.%I',cmd,tbl);
      if cmd='insert' then execute format('create policy admin_guard_insert on public.%I as restrictive for insert to authenticated with check(%s)',tbl,expr);
      elsif cmd='update' then execute format('create policy admin_guard_update on public.%I as restrictive for update to authenticated using(%s) with check(%s)',tbl,expr,expr);
      else execute format('create policy admin_guard_%s on public.%I as restrictive for %s to authenticated using(%s)',cmd,tbl,cmd,expr); end if;
    end loop;
  end loop;
end $$;

create or replace function public.register_charge_payment(
  p_charge_id bigint,p_amount numeric,p_method text,p_reference text,p_uuid uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor public.users%rowtype; c public.charges%rowtype; existing public.payments%rowtype;
  result bigint; parent_key bigint; currency_key bigint; is_parent boolean; is_super boolean;
begin
  select * into actor from public.users where auth_user_id=auth.uid()
    and institution_id=public.current_institution_id() and active and deleted_at is null;
  if actor.id is null or not public.portal_can('payments.view') then
    raise exception 'No tienes permiso para realizar esta acción.' using errcode='42501';
  end if;
  is_parent:=public.user_has_role(actor.id,'parent');
  is_super:=public.user_has_role(actor.id,'super_admin');
  if not is_parent and not public.administrative_permission(actor.institution_id,'payments.create') then
    raise exception 'No tienes permiso para realizar esta acción.' using errcode='42501';
  end if;
  if p_uuid is null or p_amount is null or p_amount<=0 or p_amount='NaN'::numeric
      or p_charge_id is null
      or p_amount<>round(p_amount,2) or p_method is null or p_method not in ('cash','transfer','card','wallet')
      or length(p_reference)>150 then
    raise exception 'Datos de pago inválidos.' using errcode='22023';
  end if;
  -- Same key + same payload replays even when the first payment closed the charge.
  perform pg_advisory_xact_lock(hashtextextended(p_uuid::text,0));
  select * into existing from public.payments where uuid=p_uuid;
  if found then
    if existing.institution_id<>actor.institution_id or existing.recorded_by<>actor.id
        or existing.charge_id is distinct from p_charge_id or existing.amount<>p_amount
        or existing.payment_method<>p_method or existing.reference is distinct from p_reference then
      raise exception 'La llave de idempotencia ya corresponde a otro pago.' using errcode='23505';
    end if;
    if not (public.administrative_permission(actor.institution_id,'payments.create') or public.family_student_scope(existing.student_id,true)) then
      raise exception 'Acceso denegado.' using errcode='42501';
    end if;
    return public.charge_payment_receipt(existing.id);
  end if;
  select * into c from public.charges where id=p_charge_id and institution_id=actor.institution_id for update;
  if not found then raise exception 'Cargo no encontrado.' using errcode='P0002'; end if;
  if not (public.administrative_permission(actor.institution_id,'payments.create') or public.family_student_scope(c.student_id,true)) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if c.status in ('paid','cancelled') then raise exception 'Este cargo ya está cerrado.' using errcode='22023'; end if;
  if is_parent then select id into parent_key from public.parents where person_id=actor.person_id and institution_id=actor.institution_id; end if;
  select currency_id into currency_key from public.payment_concepts where id=c.concept_id;
  insert into public.payments(uuid,institution_id,charge_id,student_id,parent_id,payment_method,amount,currency_id,reference,receipt_number,status,paid_at,recorded_by)
    values(p_uuid,actor.institution_id,c.id,c.student_id,parent_key,p_method,p_amount,currency_key,p_reference,'RC-'||p_uuid::text,'paid',now(),actor.id)
    returning id into result;
  return public.charge_payment_receipt(result);
end $$;

create or replace function public.cancel_unpaid_charge(p_charge_id bigint) returns void
language plpgsql security definer set search_path=public as $$
declare actor public.users%rowtype; is_super boolean;
begin
  select * into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id() and active and deleted_at is null;
  if actor.id is null or not public.administrative_permission(actor.institution_id,'payments.cancel') then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  -- UPDATE obtains the same charge lock as payment registration; the trigger
  -- checks the committed balance after any competing payment finishes.
  update public.charges set status='cancelled' where id=p_charge_id and institution_id=actor.institution_id;
  if not found then raise exception 'Cargo no encontrado.' using errcode='P0002'; end if;
end $$;


create or replace function public.portal_permission_for_user(p_user_id bigint,p_permission text) returns boolean language plpgsql stable security definer set search_path=public as $$
declare actor public.users%rowtype; result boolean;
begin
 select * into actor from public.users where id=p_user_id and active and deleted_at is null;
 if actor.id is null then return false; end if;
 if public.portal_staff(actor.id) then return true; end if;
 if p_permission not in ('grades.view','payments.view','attendance.view','schedule.view','assignments.view','assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view') then return false; end if;
 select bool_and(allowed) into result from public.portal_permission_rules q where q.institution_id=actor.institution_id and q.permission=p_permission
   and ((q.scope='user' and q.user_id=actor.id) or (q.scope='role' and public.user_has_role(actor.id,q.role_code)) or q.scope='institution')
   and case q.scope when 'user' then 3 when 'role' then 2 else 1 end=(
    select max(case x.scope when 'user' then 3 when 'role' then 2 else 1 end) from public.portal_permission_rules x where x.institution_id=actor.institution_id and x.permission=p_permission
    and ((x.scope='user' and x.user_id=actor.id) or (x.scope='role' and public.user_has_role(actor.id,x.role_code)) or x.scope='institution'));
 return coalesce(result,true);
end $$;

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
    where ur.user_id=actor.id and r.active and (ur.institution_id=actor.institution_id or ur.institution_id is null)
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

create or replace function public.portal_can_view_grades(p_student_id bigint,p_period_id bigint default null) returns boolean language plpgsql stable security definer set search_path=public as $$
declare actor public.users%rowtype; result boolean; year_id bigint;
begin
 select * into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id() and active and deleted_at is null;
 if actor.id is null or not public.portal_student_scope(p_student_id) then return false; end if;
 if public.portal_staff(actor.id) then return true; end if;
 if not public.portal_can('grades.view') then return false; end if;
 if p_period_id is not null then
   select academic_year_id into year_id from public.academic_periods where id=p_period_id and institution_id=actor.institution_id;
   if not found then return false; end if;
 else
   -- Annual aggregates/PDFs must not disclose a restricted period indirectly.
   if exists(select 1 from public.academic_periods p where p.institution_id=actor.institution_id and not public.portal_can_view_grades(p_student_id,p.id)) then return false; end if;
 end if;
 select q.allowed into result from public.grade_visibility_rules q where q.institution_id=actor.institution_id and (q.academic_period_id is null or q.academic_period_id=p_period_id)
 and (q.scope='institution' or (q.scope='user' and q.user_id=actor.id) or (q.scope='student' and q.student_id=p_student_id)
   or (q.scope='role' and public.user_has_role(actor.id,q.role_code))
   or (q.scope='group' and exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.group_id=q.group_id and (year_id is null or e.academic_year_id=year_id))))
 order by case q.scope when 'user' then 5 when 'student' then 4 when 'group' then 3 when 'role' then 2 else 1 end desc,
   (q.academic_period_id is not null) desc,q.allowed asc limit 1;
 return coalesce(result,true);
end $$;


create or replace function public.payment_charge_totals(p_charge_ids bigint[])
returns table(charge_id bigint,paid numeric) language plpgsql stable security definer set search_path=public as $$
declare inst bigint:=public.current_institution_id();
begin
  if inst is null or not public.portal_can('payments.view') then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  if cardinality(p_charge_ids)>200 then raise exception 'Máximo 200 cargos por lote.' using errcode='22023'; end if;
  return query with allowed as materialized (
    select requested.id from public.charges requested
    where requested.id=any(p_charge_ids) and requested.institution_id=inst
      and (public.administrative_permission(inst,'payments.view') or public.family_student_scope(requested.student_id))
  ) select p.charge_id,sum(p.amount) from public.payments p
  join public.charges c on c.id=p.charge_id and c.student_id=p.student_id and c.institution_id=p.institution_id
  join allowed on allowed.id=c.id
  where p.institution_id=inst and p.status='paid'
    and p.charge_id=any(p_charge_ids)
  group by p.charge_id;
end;
$$;


create or replace function public.payment_collection_summary() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare result jsonb; actor public.users%rowtype; is_super boolean;
begin
  select * into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id() and active and deleted_at is null;
  if actor.id is null or not public.administrative_permission(actor.institution_id,'payments.view') then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  with institution as (
    select i.id,coalesce(cur.iso_code,'USD') currency_code,
      (now() at time zone coalesce(i.timezone,'America/Managua'))::date today,
      date_trunc('month',now() at time zone coalesce(i.timezone,'America/Managua')) at time zone coalesce(i.timezone,'America/Managua') month_start,
      (date_trunc('month',now() at time zone coalesce(i.timezone,'America/Managua'))+interval '1 month') at time zone coalesce(i.timezone,'America/Managua') month_end
    from public.institutions i left join public.catalog_currencies cur on cur.id=i.currency_id
    where i.id=public.current_institution_id()
  ), paid as (
    select p.charge_id,sum(p.amount) amount from public.payments p join institution i on p.institution_id=i.id
    where p.status='paid' group by p.charge_id
  ), balances as (
    select c.id,coalesce(cur.iso_code,i.currency_code) currency_code,c.due_at,
      coalesce(c.total_amount,c.amount-coalesce(c.discount,0)+coalesce(c.late_fee,0)) total,
      greatest(coalesce(c.total_amount,c.amount-coalesce(c.discount,0)+coalesce(c.late_fee,0))-coalesce(paid.amount,0),0) balance,
      case when c.status in ('paid','cancelled') then c.status when c.due_at<i.today then 'overdue' else coalesce(c.status,'pending') end status
    from public.charges c join institution i on c.institution_id=i.id
    left join public.payment_concepts pc on pc.id=c.concept_id
    left join public.catalog_currencies cur on cur.id=pc.currency_id
    left join paid on paid.charge_id=c.id
  ), currencies as (
    select currency_code from balances union select currency_code from institution
    union select coalesce(cur.iso_code,i.currency_code) from public.payments p join institution i on p.institution_id=i.id
      left join public.catalog_currencies cur on cur.id=p.currency_id where p.status='paid'
  ), summaries as (
    select code.currency_code,
      jsonb_build_object('currencyCode',code.currency_code,
        'collectedThisMonth',(select coalesce(sum(p.amount),0) from public.payments p
          left join public.catalog_currencies cur on cur.id=p.currency_id
          where p.institution_id=i.id and p.status='paid' and p.paid_at>=i.month_start and p.paid_at<i.month_end
            and coalesce(cur.iso_code,i.currency_code)=code.currency_code),
        'expectedThisMonth',coalesce(sum(b.total) filter(where b.status<>'cancelled' and b.due_at>=date_trunc('month',i.today)::date and b.due_at<(date_trunc('month',i.today)+interval '1 month')::date),0),
        'overdueAmount',coalesce(sum(b.balance) filter(where b.status='overdue'),0),
        'overdueCount',count(b.id) filter(where b.status='overdue'),
        'pendingAmount',coalesce(sum(b.balance) filter(where b.status in ('pending','partial')),0),
        'chargesByStatus',coalesce((select jsonb_object_agg(status,n) from
          (select status,count(*) n from balances where currency_code=code.currency_code group by status) counts),'{}')) payload
    from currencies code cross join institution i left join balances b on b.currency_code=code.currency_code
    group by code.currency_code,i.id,i.currency_code,i.month_start,i.month_end,i.today
  ) select coalesce((select payload from summaries where currency_code=(select currency_code from institution)),
      jsonb_build_object('currencyCode','USD','collectedThisMonth',0,'expectedThisMonth',0,'overdueAmount',0,'overdueCount',0,'pendingAmount',0,'chargesByStatus','{}'::jsonb))
    ||jsonb_build_object('byCurrency',coalesce((select jsonb_object_agg(currency_code,payload) from summaries),'{}')) into result;
  return result;
end $$;

revoke all on function public.payment_charge_totals(bigint[]),public.payment_collection_summary() from public,anon;
grant execute on function public.payment_charge_totals(bigint[]),public.payment_collection_summary() to authenticated;
