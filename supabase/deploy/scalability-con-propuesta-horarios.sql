-- NIVRA: actualización completa 0029–0053. Generado; no editar manualmente.
-- Ejecutar en Supabase SQL Editor como postgres, DESPUÉS de backup recuperable
-- y de detener escritores/workers antiguos. Actualizar backend, Edge y clientes.
-- Requiere esquema anterior compatible con 0028. No activa 2FA a ningún usuario.
-- Contiene una propuesta de 9 franjas, bloqueada por defecto; requiere aprobación expresa.
-- La única edición manual permitida es confirmar horario_aprobado tras revisar la propuesta.
-- Una sola transacción: cualquier error revierte TODAS las migraciones.
-- Si falla, ejecutar ROLLBACK antes de reutilizar la misma conexión.
-- Repetir este archivo después de una aplicación completa se rechaza expresamente.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';
SELECT pg_advisory_xact_lock(hashtextextended('nivra/scalability-0029-0053', 0));

DO $baseline$
BEGIN
  IF to_regprocedure('public.backend_readiness_v1()') IS NOT NULL THEN
    RAISE EXCEPTION 'El marcador de esta actualización ya existe. Revisar el historial antes de repetir el script.';
  END IF;
  IF to_regprocedure('public.auth_2fa_session_allowed()') IS NULL THEN
    RAISE EXCEPTION 'Falta el esquema base 0028. No aplicar este paquete sobre una base incompleta.';
  END IF;
END
$baseline$;

-- PROPUESTA: cambia 9 franjas de Big School; conserva días, duración,
-- maestros, materias, grupos y aulas. Algunas clases terminarán a las 13:00.
-- NO EJECUTAR sin confirmar disponibilidad real de alumnos/docentes/recesos.
-- Tras aprobar expresamente la tabla de cambios, cambiar solamente
-- horario_aprobado := false por horario_aprobado := true.
LOCK TABLE public.schedules IN SHARE ROW EXCLUSIVE MODE;
DO $schedule_plan$
DECLARE horario_aprobado boolean := false; matches integer;
BEGIN
 IF NOT horario_aprobado THEN
  RAISE EXCEPTION 'Propuesta de horarios pendiente de aprobación. Revisar PROPUESTA_HORARIOS_BIGSCHOOL.md antes de cambiar horario_aprobado a true.';
 END IF;
 CREATE TEMP TABLE approved_schedule_plan ON COMMIT DROP AS
 SELECT * FROM (VALUES
 (7,13,5,3,3,3,'10:00:00'::time,'11:30:00'::time,'11:30'::time,'13:00'::time),
 (10,15,7,8,5,1,'08:00:00'::time,'09:30:00'::time,'09:30'::time,'11:00'::time),
 (14,17,6,5,4,2,'08:00:00'::time,'09:30:00'::time,'09:30'::time,'11:00'::time),
 (15,17,6,5,4,4,'10:00:00'::time,'11:30:00'::time,'08:30'::time,'10:00'::time),
 (20,20,6,8,4,3,'08:00:00'::time,'09:30:00'::time,'11:30'::time,'13:00'::time),
 (21,20,6,8,4,5,'10:00:00'::time,'11:30:00'::time,'08:30'::time,'10:00'::time),
 (23,21,7,8,5,5,'10:00:00'::time,'11:30:00'::time,'11:30'::time,'13:00'::time),
 (25,22,5,7,3,5,'10:00:00'::time,'11:30:00'::time,'08:30'::time,'10:00'::time),
 (26,23,6,7,4,1,'08:00:00'::time,'09:30:00'::time,'09:30'::time,'11:00'::time)
 ) AS p(id,class_id,group_id,teacher_id,classroom_id,weekday_id,old_start,old_end,new_start,new_end);
 SELECT count(*) INTO matches FROM approved_schedule_plan p
 JOIN public.schedules s ON s.id=p.id JOIN public.classes c ON c.id=s.class_id
 WHERE s.institution_id=2 AND c.institution_id=2 AND c.academic_year_id=2
   AND s.kind='class' AND s.class_id=p.class_id AND c.group_id=p.group_id
   AND c.teacher_id=p.teacher_id AND s.classroom_id=p.classroom_id
   AND s.weekday_id=p.weekday_id AND s.start_time=p.old_start AND s.end_time=p.old_end;
 IF matches<>9 THEN
  RAISE EXCEPTION 'Los horarios o asignaciones ya cambiaron. Revisar una propuesta nueva; no se actualizó ningún horario.';
 END IF;
 UPDATE public.schedules s SET start_time=p.new_start,end_time=p.new_end
 FROM approved_schedule_plan p WHERE s.id=p.id;
 GET DIAGNOSTICS matches = ROW_COUNT;
 IF matches<>9 THEN RAISE EXCEPTION 'No se actualizaron exactamente los 9 bloques previstos.'; END IF;
END
$schedule_plan$;

-- Mantener estable el conjunto de horarios entre la revisión y las exclusiones.
LOCK TABLE public.schedules IN SHARE ROW EXCLUSIVE MODE;
DO $preflight$
DECLARE issues jsonb := '[]'::jsonb; found_issues jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(to_jsonb(check_row)), '[]'::jsonb)
    INTO found_issues FROM (with source as (
  select s.*,c.institution_id class_institution,c.group_id class_group,c.academic_year_id class_year,
    coalesce(case when s.kind='class' then c.group_id else s.group_id end,null) effective_group,
    case when s.kind='class' then c.academic_year_id else g.academic_year_id end linked_year,
    g.institution_id group_institution,g.academic_year_id group_year,
    room.institution_id room_institution,room.name room_name,
    (select count(*) from academic_years y where y.institution_id=s.institution_id and y.is_current and y.active) current_years
  from schedules s left join classes c on c.id=s.class_id
    left join groups g on g.id=case when s.kind='class' then c.group_id else s.group_id end
    left join classrooms room on room.id=s.classroom_id
)
select id,'Datos incompletos o referencias incompatibles; corregir antes de migrar' problem from source
where institution_id is null or weekday_id is null or weekday_id not between 1 and 7
  or start_time is null or end_time is null or start_time>=end_time
  or extract(second from start_time)<>0 or extract(second from end_time)<>0
  or kind='class' and (class_institution is distinct from institution_id or class_group is null
    or class_year is null or class_year is distinct from group_year)
  or effective_group is not null and (group_institution is distinct from institution_id or group_year is null)
  or kind='break' and effective_group is null and current_years<>1
  or kind='class' and classroom_id is not null and (room_institution is distinct from institution_id or nullif(trim(room_name),'') is null)) check_row;
  issues := issues || found_issues;
  SELECT coalesce(jsonb_agg(to_jsonb(check_row)), '[]'::jsonb)
    INTO found_issues FROM (with normalized as (
  select s.id,s.institution_id,s.weekday_id,s.start_time,s.end_time,
    coalesce(case when s.kind='class' then c.academic_year_id else g.academic_year_id end,
      (select min(y.id) from academic_years y where y.institution_id=s.institution_id and y.is_current and y.active)) year_id,
    case when s.kind='class' then c.group_id else s.group_id end group_id,
    case when s.kind='class' then c.teacher_id end teacher_id,
    case when s.kind='class' then lower(trim(room.name)) end room_key
  from schedules s left join classes c on c.id=s.class_id left join groups g on g.id=s.group_id
    left join classrooms room on room.id=s.classroom_id
)
select a.id first_id,b.id second_id,'Cruce de grupo, maestro o aula' problem
from normalized a join normalized b on a.id<b.id and a.institution_id=b.institution_id and a.year_id=b.year_id
  and a.weekday_id=b.weekday_id and a.start_time<b.end_time and a.end_time>b.start_time
where a.group_id is null or b.group_id is null or a.group_id=b.group_id
  or a.teacher_id=b.teacher_id or a.room_key=b.room_key) check_row;
  issues := issues || found_issues;
  IF jsonb_array_length(issues) > 0 THEN
    RAISE EXCEPTION USING ERRCODE = '23P01',
      MESSAGE = 'Actualización detenida: corregir los horarios incompatibles antes de migrar.',
      DETAIL = issues::text,
      HINT = 'No se aplicó ninguna migración. Revisar IDs y motivos; no borrar ni desplazar clases automáticamente.';
  END IF;
END
$preflight$;


-- BEGIN 0029_atomic_payments.sql
-- SHA256 388f9710b199deddabc32d11fc404bd4fef564cf25337669518b0fab4d1bd443
-- Serialize every payment writer (including direct Supabase clients) on the
-- charge. Monetary arithmetic and status changes belong to one transaction.
create or replace function public.payment_balance_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare c public.charges%rowtype;
begin
  if tg_op = 'UPDATE' and (new.charge_id,new.institution_id,new.student_id)
      is distinct from (old.charge_id,old.institution_id,old.student_id) then
    raise exception 'No se puede trasladar un pago entre cargos.' using errcode='22023';
  end if;
  select * into c from public.charges where id=coalesce(new.charge_id,old.charge_id) for update;
  if not found then
    -- A foreign-key cascade deletes the parent before its payment children.
    -- There is no remaining balance to lock/recalculate in that case.
    if tg_op='DELETE' then return old; end if;
    raise exception 'Cargo no encontrado.' using errcode='P0002';
  end if;
  if tg_op <> 'DELETE' then
    if new.institution_id is distinct from c.institution_id or new.student_id is distinct from c.student_id then
      raise exception 'El pago no corresponde al cargo.' using errcode='22023';
    end if;
    if new.amount is null or new.amount <= 0 or new.amount = 'NaN'::numeric then
      raise exception 'El monto debe ser mayor que cero.' using errcode='22023';
    end if;
    if new.status='paid' then
      if c.status='cancelled' then
        raise exception 'Este cargo está anulado.' using errcode='22023';
      end if;
    end if;
    return new;
  end if;
  return old;
end $$;

create or replace function public.payment_balance_refresh() returns trigger
language plpgsql security definer set search_path = public as $$
declare affected bigint[]; c public.charges%rowtype; paid numeric; total numeric;
begin
  -- Transition tables reduce a bulk insert from one ledger scan per payment
  -- to one scan per affected charge. Validation still rolls back the complete
  -- statement, under the locks acquired by the BEFORE trigger.
  if tg_op='INSERT' then select array_agg(distinct charge_id) into affected from new_payments;
  elsif tg_op='DELETE' then select array_agg(distinct charge_id) into affected from old_payments;
  else select array_agg(charge_id) into affected from
    (select charge_id from new_payments union select charge_id from old_payments) changes;
  end if;
  for c in select * from public.charges where id=any(affected) order by id for update loop
    select coalesce(sum(amount),0) into paid from public.payments where charge_id=c.id and status='paid';
    total:=coalesce(c.total_amount,c.amount-coalesce(c.discount,0)+coalesce(c.late_fee,0));
    if total is null or paid>total then
      raise exception 'El monto excede el saldo pendiente.' using errcode='22023';
    end if;
    update public.charges set status=case when paid>=total then 'paid'
      when paid>0 then 'partial' else 'pending' end where id=c.id and status<>'cancelled';
  end loop;
  return null;
end $$;

create or replace function public.charge_balance_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare paid numeric;
begin
  select coalesce(sum(amount),0) into paid from public.payments where charge_id=old.id and status='paid';
  if paid>0 and new.status='cancelled' then
    raise exception 'No se puede anular un cargo con pagos registrados.' using errcode='22023';
  end if;
  if paid>coalesce(new.total_amount,new.amount-coalesce(new.discount,0)+coalesce(new.late_fee,0)) then
    raise exception 'El total no puede ser inferior a lo pagado.' using errcode='22023';
  end if;
  return new;
end $$;

create trigger payment_balance_before before insert or update or delete on public.payments
  for each row execute function public.payment_balance_guard();
create trigger payment_balance_insert after insert on public.payments
  referencing new table as new_payments for each statement execute function public.payment_balance_refresh();
create trigger payment_balance_update after update on public.payments
  referencing new table as new_payments old table as old_payments for each statement execute function public.payment_balance_refresh();
create trigger payment_balance_delete after delete on public.payments
  referencing old table as old_payments for each statement execute function public.payment_balance_refresh();
create trigger charge_balance_before before update of status,amount,discount,late_fee,total_amount on public.charges
  for each row execute function public.charge_balance_guard();

-- Internal projection: callers of the write RPC may receive their receipt
-- without requiring permission to browse the entire payment ledger.
create or replace function public.charge_payment_receipt(p_id bigint) returns jsonb
language sql stable set search_path=public as $$
  select jsonb_build_object('id',p.id::text,'uuid',p.uuid::text,'chargeId',p.charge_id::text,
    'chargeConcept',coalesce(pc.name,c.description,'Pago'),'studentName',coalesce(nullif(trim(person.first_name||' '||person.last_name),''),'Estudiante'),
    'method',p.payment_method,'amount',p.amount,'currencyCode',coalesce(cur.iso_code,'USD'),
    'status',p.status,'paidAt',p.paid_at,'receiptNumber',p.receipt_number,'reference',p.reference)
  from public.payments p left join public.charges c on c.id=p.charge_id
  left join public.payment_concepts pc on pc.id=c.concept_id
  left join public.catalog_currencies cur on cur.id=p.currency_id
  left join public.students s on s.id=p.student_id left join public.persons person on person.id=s.person_id
  where p.id=p_id;
$$;
revoke all on function public.charge_payment_receipt(bigint) from public,anon,authenticated;

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
  select coalesce(bool_or(r.code='parent'),false),coalesce(bool_or(r.code='super_admin'),false)
    into is_parent,is_super from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=actor.id;
  if not is_parent and (not public.class_admin_actor() or
      (not is_super and actor.admin_permissions is not null and not ('payments.create'=any(actor.admin_permissions)))) then
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
    if not public.portal_student_scope(existing.student_id) then
      raise exception 'Acceso denegado.' using errcode='42501';
    end if;
    return public.charge_payment_receipt(existing.id);
  end if;
  select * into c from public.charges where id=p_charge_id and institution_id=actor.institution_id for update;
  if not found then raise exception 'Cargo no encontrado.' using errcode='P0002'; end if;
  if not public.portal_student_scope(c.student_id) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
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
  select exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=actor.id and r.code='super_admin') into is_super;
  if actor.id is null or not public.class_admin_actor() or
      (not is_super and actor.admin_permissions is not null and not ('payments.cancel'=any(actor.admin_permissions))) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  -- UPDATE obtains the same charge lock as payment registration; the trigger
  -- checks the committed balance after any competing payment finishes.
  update public.charges set status='cancelled' where id=p_charge_id and institution_id=actor.institution_id;
  if not found then raise exception 'Cargo no encontrado.' using errcode='P0002'; end if;
end $$;

revoke all on function public.register_charge_payment(bigint,numeric,text,text,uuid), public.cancel_unpaid_charge(bigint),
  public.payment_balance_guard(),public.payment_balance_refresh(),public.charge_balance_guard() from public,anon;
grant execute on function public.register_charge_payment(bigint,numeric,text,text,uuid), public.cancel_unpaid_charge(bigint) to authenticated;
create index if not exists payments_paid_charge_balance on public.payments(charge_id) include(amount) where status='paid';
-- END 0029_atomic_payments.sql


-- BEGIN 0030_payment_read_aggregates.sql
-- SHA256 38d0b8a1983a4aa31b88a5e97ffdb9fd2c89b38ab30de6620b518d013f21d7cc
-- Authorize the actor and tenant once, then aggregate the ledger without
-- repeating MFA/role policy functions per installment. No tenant or actor is
-- accepted as an argument. Parent access is checked per requested charge.
create or replace function public.payment_charge_totals(p_charge_ids bigint[])
returns table(charge_id bigint,paid numeric) language plpgsql stable security definer set search_path=public as $$
declare inst bigint:=public.current_institution_id();
begin
  if inst is null or not public.portal_can('payments.view') or not public.admin_can('payments.view') then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  if cardinality(p_charge_ids)>200 then raise exception 'Máximo 200 cargos por lote.' using errcode='22023'; end if;
  return query with allowed as materialized (
    select requested.id from public.charges requested
    where requested.id=any(p_charge_ids) and requested.institution_id=inst
      and public.portal_student_scope(requested.student_id)
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
  select exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=actor.id and r.code='super_admin') into is_super;
  if actor.id is null or not public.class_admin_actor() or
      (not is_super and actor.admin_permissions is not null and not ('payments.view'=any(actor.admin_permissions))) then
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
-- END 0030_payment_read_aggregates.sql


-- BEGIN 0031_dashboard_aggregates.sql
-- SHA256 ff2c3a64ba63e17c05a077924feb965c1701584df0ba5efbd22febf142871412
create or replace function public.dashboard_attendance_pct(p_student_id bigint default null)
returns numeric language plpgsql stable set search_path=public as $$
declare result numeric;
begin
  if p_student_id is null then
    if not public.class_admin_actor() or not public.admin_can('dashboard.view') then
      raise exception 'Acceso denegado.' using errcode='42501';
    end if;
  elsif not public.portal_student_scope(p_student_id) or not public.portal_can('attendance.view') then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  select coalesce(round(100.0*count(*) filter(where status.code='PRE')/nullif(count(*),0),1),0)
    into result from public.attendances a
    join public.class_sessions s on s.id=a.class_session_id
    join public.classes c on c.id=s.class_id
    join public.academic_years y on y.id=c.academic_year_id and y.is_current
    join public.catalog_attendance_statuses status on status.id=a.attendance_status_id
    where a.institution_id=public.current_institution_id()
      and (p_student_id is null or a.student_id=p_student_id)
      and (y.start_date is null or s.date>=y.start_date) and (y.end_date is null or s.date<=y.end_date);
  return result;
end $$;

create or replace function public.dashboard_institutional_average() returns numeric
language plpgsql stable set search_path=public as $$
declare result numeric;
begin
  if not public.class_admin_actor() or not public.admin_can('dashboard.view') then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  select coalesce(round(avg(v.weighted_pct)/10,1),0) into result
    from public.student_weighted_averages v
    join public.academic_periods p on p.id=v.academic_period_id
    join public.academic_years y on y.id=p.academic_year_id and y.is_current
    where v.institution_id=public.current_institution_id();
  return result;
end $$;

create or replace function public.dashboard_assignment_counts(p_assignment_ids bigint[])
returns table(assignment_id bigint,total bigint,delivered bigint,graded bigint)
language sql stable set search_path=public as $$
  select a.id,
    (select count(distinct e.student_id) from public.enrollments e
      join public.students student on student.id=e.student_id and student.active
      join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
      where e.institution_id=a.institution_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id),
    (select count(*) from public.submissions s join public.catalog_task_statuses status on status.id=s.task_status_id
      where s.assignment_id=a.id and status.code in ('ENTR','CALI','REV') and exists(
        select 1 from public.enrollments e join public.students student on student.id=e.student_id and student.active
        join public.catalog_enrollment_statuses enrolled on enrolled.id=e.enrollment_status_id and enrolled.code='ACT'
        where e.student_id=s.student_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id)),
    (select count(*) from public.submissions s join public.catalog_task_statuses status on status.id=s.task_status_id
      where s.assignment_id=a.id and status.code='CALI' and exists(
        select 1 from public.enrollments e join public.students student on student.id=e.student_id and student.active
        join public.catalog_enrollment_statuses enrolled on enrolled.id=e.enrollment_status_id and enrolled.code='ACT'
        where e.student_id=s.student_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id))
  from public.assignments a join public.classes c on c.id=a.class_id
  where a.id=any(p_assignment_ids) and a.institution_id=public.current_institution_id() and a.deleted_at is null;
$$;

create or replace function public.dashboard_student_average(p_student_id bigint) returns numeric
language plpgsql stable set search_path=public as $$
declare result numeric;
begin
  if p_student_id is null or not public.portal_can_view_grades(p_student_id,null) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  select coalesce(avg(v.weighted_pct),0) into result
    from public.student_weighted_averages v
    join public.academic_periods p on p.id=v.academic_period_id
    join public.academic_years y on y.id=p.academic_year_id and y.is_current
    where v.institution_id=public.current_institution_id() and v.student_id=p_student_id;
  return result;
end $$;

create or replace function public.dashboard_pending_grading(p_class_ids bigint[]) returns bigint
language sql stable set search_path=public as $$
  select count(*) from public.submissions s
    join public.assignments a on a.id=s.assignment_id and a.deleted_at is null
    join public.classes c on c.id=a.class_id
    join public.academic_years y on y.id=c.academic_year_id and y.is_current
    join public.catalog_task_statuses status on status.id=s.task_status_id and status.code in ('ENTR','REV')
    join public.enrollments e on e.student_id=s.student_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id
    join public.students student on student.id=e.student_id and student.active
    join public.catalog_enrollment_statuses enrolled on enrolled.id=e.enrollment_status_id and enrolled.code='ACT'
    where a.institution_id=public.current_institution_id() and a.class_id=any(p_class_ids);
$$;

revoke all on function public.dashboard_attendance_pct(bigint),public.dashboard_institutional_average(),
  public.dashboard_assignment_counts(bigint[]),public.dashboard_pending_grading(bigint[]),public.dashboard_student_average(bigint) from public,anon;
grant execute on function public.dashboard_attendance_pct(bigint),public.dashboard_institutional_average(),
  public.dashboard_assignment_counts(bigint[]),public.dashboard_pending_grading(bigint[]),public.dashboard_student_average(bigint) to authenticated;
-- END 0031_dashboard_aggregates.sql


-- BEGIN 0032_assignment_feed.sql
-- SHA256 d55ff22f935b85a1b223449cfa7790d1095b463f949cfab26cd70dbfdc1a304b
alter table public.assignments add column kind text not null default 'homework'
  check(kind in ('homework','exam','project','quiz','presentation'));
update public.assignments a set kind=case typed.code when 'EXM' then 'exam' when 'PRO' then 'project'
  when 'QZ' then 'quiz' when 'EXP' then 'presentation' else 'homework' end
from (select distinct on(e.assignment_id) e.assignment_id,t.code from public.evaluations e
  join public.catalog_evaluation_types t on t.id=e.evaluation_type_id where e.assignment_id is not null order by e.assignment_id,e.id) typed
where typed.assignment_id=a.id;

-- One bounded query per feed page. It retains table RLS, class collaboration
-- grants, student scope, visibility rules and MFA. The cursor uses due_at + id;
-- equal timestamps and NULL due dates cannot silently skip assignments.
create or replace function public.assignment_feed(
  p_student_id bigint default null,p_class_id bigint default null,p_search text default null,
  p_only_open boolean default false,p_kinds text[] default null,p_subject text default null,
  p_after_due_at timestamptz default null,p_after_id bigint default null,p_limit integer default 50
) returns jsonb language plpgsql stable set search_path=public as $$
declare actor bigint; result jsonb;
begin
  select id into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id()
    and active and deleted_at is null;
  if actor is null then raise exception 'Sesión requerida.' using errcode='42501'; end if;
  if p_student_id is null then
    if not public.portal_staff(actor) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  elsif not public.portal_can('assignments.view') or not public.portal_student_scope(p_student_id) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  if p_limit is null or p_limit not between 1 and 100 or length(p_search)>150 or length(p_subject)>100
      or (p_kinds is not null and not p_kinds<@array['homework','exam','project','quiz','presentation']::text[])
      or (p_after_id is null and p_after_due_at is not null) then
    raise exception 'Filtros o cursor inválidos.' using errcode='22023';
  end if;
  with base as materialized (
    select a.*,c.group_id,c.academic_year_id,coalesce(subject.name,'Materia') subject_name,
      coalesce(g.name,'Grupo') group_name,trim(person.first_name||' '||person.last_name) teacher_name
    from public.assignments a join public.classes c on c.id=a.class_id
    join public.academic_years y on y.id=c.academic_year_id and y.is_current
    left join public.subjects subject on subject.id=c.subject_id left join public.groups g on g.id=c.group_id
    left join public.teachers teacher on teacher.id=c.teacher_id left join public.persons person on person.id=teacher.person_id
    where a.institution_id=public.current_institution_id() and a.deleted_at is null and c.active
      and (p_class_id is null or a.class_id=p_class_id) and (p_kinds is null or a.kind=any(p_kinds))
      and (p_subject is null or strpos(lower(trim(subject.name)),lower(trim(p_subject)))>0 or strpos(lower(trim(p_subject)),lower(trim(subject.name)))>0)
      and (nullif(trim(p_search),'') is null or strpos(lower(a.title||' '||coalesce(subject.name,'')),lower(trim(p_search)))>0)
      and (not p_only_open or (a.published and (a.due_at is null or a.due_at>=now())))
      and (p_student_id is null or (a.published and exists(select 1 from public.enrollments e
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
        where e.student_id=p_student_id and e.institution_id=a.institution_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id)))
      and (p_after_id is null or
        (p_after_due_at is null and a.due_at is null and a.id>p_after_id) or
        (p_after_due_at is not null and (a.due_at is null or (a.due_at,a.id)>(p_after_due_at,p_after_id))))
    order by a.due_at nulls last,a.id
    limit case when p_only_open then null else p_limit+1 end
  ), group_scope as (select distinct group_id,academic_year_id from base), enrolled as materialized (
    select e.group_id,e.academic_year_id,e.student_id
    from public.enrollments e join group_scope scope on scope.group_id=e.group_id and scope.academic_year_id=e.academic_year_id
    join public.students student on student.id=e.student_id and student.active
    join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
    where e.institution_id=public.current_institution_id() and (p_student_id is null or e.student_id=p_student_id)
  ), roster as (
    select group_id,academic_year_id,count(distinct student_id) total from enrolled group by group_id,academic_year_id
  ), submissions as (
    select s.assignment_id,count(*) filter(where status.code in ('ENTR','CALI','REV')) submitted,
      count(*) filter(where status.code='CALI') graded
    from public.submissions s join base a on a.id=s.assignment_id join public.catalog_task_statuses status on status.id=s.task_status_id
    join enrolled on enrolled.student_id=s.student_id and enrolled.group_id=a.group_id and enrolled.academic_year_id=a.academic_year_id
    where s.institution_id=public.current_institution_id() and (p_student_id is null or s.student_id=p_student_id)
    group by s.assignment_id
  ), counted as (
    select a.*,coalesce(roster.total,0) total_students,coalesce(s.submitted,0) submitted_count,coalesce(s.graded,0) graded_count
    from base a left join roster on roster.group_id=a.group_id and roster.academic_year_id=a.academic_year_id
    left join submissions s on s.assignment_id=a.id
  ), page as materialized (
    select a.*,row_number() over(order by a.due_at nulls last,a.id) position from counted a
    where not p_only_open or a.total_students=0 or a.graded_count<a.total_students
    order by a.due_at nulls last,a.id limit p_limit+1
  ), files as (
    select link.assignment_id,jsonb_agg(jsonb_build_object('id',f.id::text,'name',coalesce(f.original_name,'archivo'),'url',coalesce(f.url,''),
      'sizeBytes',f.size_bytes,'mimeType',f.mime_type) order by link.id) attachments
    from public.assignment_files link join page a on a.id=link.assignment_id
    join public.files f on f.id=link.file_id and f.deleted_at is null group by link.assignment_id
  ), items as (
    select a.position,jsonb_build_object('id',a.id::text,'classId',a.class_id::text,'subjectName',a.subject_name,'groupName',a.group_name,
      'teacherName',a.teacher_name,'title',a.title,'description',a.description,'instructions',a.instructions,
      'assignedAt',coalesce(a.assigned_at::text,a.created_at::text,''),'dueAt',a.due_at,'kind',a.kind,'maxScore',coalesce(a.max_score,100),
      'allowLate',coalesce(a.allow_late,false),'published',coalesce(a.published,true),'attachments',coalesce(files.attachments,'[]'),
      'totalStudents',a.total_students,'submittedCount',a.submitted_count,'gradedCount',a.graded_count,
      'progress',case when p_student_id is null then null else jsonb_build_object(
        'status',(select case when status.code='CALI' then 'graded' when s.is_late then 'late' else 'submitted' end
          from public.submissions s join public.catalog_task_statuses status on status.id=s.task_status_id
          where s.assignment_id=a.id and s.student_id=p_student_id and status.code in ('ENTR','CALI','REV') limit 1),
        'score',(select g.score from public.grades g join public.evaluations e on e.id=g.evaluation_id
          where e.assignment_id=a.id and g.student_id=p_student_id order by e.id desc,g.id desc limit 1)) end) payload
    from page a left join files on files.assignment_id=a.id where a.position<=p_limit
  ) select jsonb_build_object('assignments',coalesce((select jsonb_agg(payload order by position) from items),'[]'),
      'nextCursor',case when exists(select 1 from page where position>p_limit)
        then (select jsonb_build_object('id',id::text,'dueAt',due_at) from page where position=p_limit) else null end) into result;
  return result;
end $$;

revoke all on function public.assignment_feed(bigint,bigint,text,boolean,text[],text,timestamptz,bigint,integer) from public,anon;
grant execute on function public.assignment_feed(bigint,bigint,text,boolean,text[],text,timestamptz,bigint,integer) to authenticated;
create index if not exists assignments_feed_due_id on public.assignments(institution_id,due_at,id) where deleted_at is null;

create or replace function public.assignment_counters(p_student_id bigint default null) returns jsonb
language plpgsql stable set search_path=public as $$
declare actor bigint; result jsonb;
begin
  select id into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id() and active and deleted_at is null;
  if actor is null or (p_student_id is null and not public.portal_staff(actor)) or
      (p_student_id is not null and (not public.portal_can('assignments.view') or not public.portal_student_scope(p_student_id))) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  with tasks as materialized (
    select a.id,a.published,a.due_at,c.group_id,c.academic_year_id from public.assignments a
      join public.classes c on c.id=a.class_id join public.academic_years y on y.id=c.academic_year_id and y.is_current
    where a.institution_id=public.current_institution_id() and a.deleted_at is null and c.active and
      (p_student_id is null or (a.published and exists(select 1 from public.enrollments e
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
        where e.student_id=p_student_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id)))
  ), scope as (select distinct group_id,academic_year_id from tasks), enrolled as materialized (
    select e.group_id,e.academic_year_id,e.student_id from public.enrollments e
      join scope on scope.group_id=e.group_id and scope.academic_year_id=e.academic_year_id
      join public.students student on student.id=e.student_id and student.active
      join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
    where e.institution_id=public.current_institution_id() and (p_student_id is null or e.student_id=p_student_id)
  ), roster as (
    select group_id,academic_year_id,count(distinct student_id) total from enrolled group by group_id,academic_year_id
  ), counts as (
    select s.assignment_id,count(*) filter(where status.code in ('ENTR','CALI','REV')) submitted,
      count(*) filter(where status.code='CALI') graded from public.submissions s
      join tasks a on a.id=s.assignment_id join public.catalog_task_statuses status on status.id=s.task_status_id
      join enrolled on enrolled.student_id=s.student_id and enrolled.group_id=a.group_id and enrolled.academic_year_id=a.academic_year_id
    where s.institution_id=public.current_institution_id() and (p_student_id is null or s.student_id=p_student_id)
    group by s.assignment_id
  ) select jsonb_build_object('pending',count(*) filter(where
      case when p_student_id is not null then coalesce(counts.submitted,0)=0
      else a.published and (a.due_at is null or a.due_at>=now()) and (coalesce(roster.total,0)=0 or coalesce(counts.graded,0)<roster.total) end),
    'submitted',coalesce(sum(counts.submitted),0),'graded',coalesce(sum(counts.graded),0),
    'toGrade',coalesce(sum(counts.submitted-counts.graded),0)) into result
    from tasks a left join counts on counts.assignment_id=a.id left join roster on roster.group_id=a.group_id and roster.academic_year_id=a.academic_year_id;
  return result;
end $$;
revoke all on function public.assignment_counters(bigint) from public,anon;
grant execute on function public.assignment_counters(bigint) to authenticated;

-- Grading an exam must not silently create a homework evaluation. Existing
-- grading RPCs insert evaluations before grades; preserve their transaction.
create or replace function public.set_assignment_evaluation_kind() returns trigger
language plpgsql set search_path=public as $$
declare task public.assignments%rowtype; type_code text;
begin
  if new.assignment_id is null then return new; end if;
  select * into task from public.assignments where id=new.assignment_id;
  if not found or task.institution_id is distinct from new.institution_id then
    raise exception 'La evaluación no corresponde a la tarea.' using errcode='42501';
  end if;
  type_code:=case task.kind when 'exam' then 'EXM' when 'project' then 'PRO' when 'quiz' then 'QZ' when 'presentation' then 'EXP' else 'TAR' end;
  select id into new.evaluation_type_id from public.catalog_evaluation_types where code=type_code order by id limit 1;
  if new.evaluation_type_id is null then raise exception 'Tipo de evaluación no configurado.' using errcode='22023'; end if;
  return new;
end $$;
create trigger assignment_evaluation_kind before insert or update of assignment_id on public.evaluations
  for each row execute function public.set_assignment_evaluation_kind();

create or replace function public.sync_assignment_evaluation_kind() returns trigger
language plpgsql security definer set search_path=public as $$
declare type_key integer;
begin
  if new.kind is not distinct from old.kind then return null; end if;
  select id into type_key from public.catalog_evaluation_types where code=case new.kind
    when 'exam' then 'EXM' when 'project' then 'PRO' when 'quiz' then 'QZ' when 'presentation' then 'EXP' else 'TAR' end order by id limit 1;
  if type_key is null then raise exception 'Tipo de evaluación no configurado.' using errcode='22023'; end if;
  update public.evaluations set evaluation_type_id=type_key where assignment_id=new.id and institution_id=new.institution_id;
  return null;
end $$;
create trigger sync_assignment_kind after update of kind on public.assignments
  for each row execute function public.sync_assignment_evaluation_kind();
revoke all on function public.set_assignment_evaluation_kind(),public.sync_assignment_evaluation_kind() from public,anon,authenticated;

create or replace function public.class_enrollment_counts(p_class_ids bigint[])
returns table(class_id bigint,total bigint) language sql stable set search_path=public as $$
  select c.id,count(distinct e.student_id) filter(where student.active and status.code='ACT')
  from public.classes c
  left join public.enrollments e on e.group_id=c.group_id and e.academic_year_id=c.academic_year_id and e.institution_id=c.institution_id
  left join public.students student on student.id=e.student_id
  left join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id
  where c.institution_id=public.current_institution_id() and c.id=any(p_class_ids) group by c.id;
$$;
revoke all on function public.class_enrollment_counts(bigint[]) from public,anon;
grant execute on function public.class_enrollment_counts(bigint[]) to authenticated;
-- END 0032_assignment_feed.sql


-- BEGIN 0033_student_report_context.sql
-- SHA256 9295327feb9d763d0b0cfc4287df9dabbd51883d0c9b0ebbec7415e490751159
-- A report must not invent first place or 100% attendance when no records
-- exist. This scoped read returns missing metrics as NULL and counts the
-- requested academic period, rather than all historical attendance.
create or replace function public.student_report_context(p_student_id bigint,p_period_id bigint default null)
returns jsonb language plpgsql stable set search_path=public as $$
declare year_key bigint; starts date; ends date; attendance numeric; result jsonb;
begin
  if not public.portal_student_scope(p_student_id) or not public.portal_can('reports.view')
      or not public.admin_can('reports.view') or not public.portal_can_view_grades(p_student_id,p_period_id) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  if p_period_id is not null then
    select academic_year_id,start_date,end_date into year_key,starts,ends from public.academic_periods
      where id=p_period_id and institution_id=public.current_institution_id();
    if not found then raise exception 'Periodo no encontrado.' using errcode='P0002'; end if;
  else
    select id,start_date,end_date into year_key,starts,ends from public.academic_years
      where institution_id=public.current_institution_id() and is_current;
  end if;
  if year_key is not null and public.portal_can('attendance.view') then
    select round(100.0*count(*) filter(where not coalesce(status.counts_as_absent,false))/nullif(count(*),0),1)
      into attendance from public.attendances a
      join public.class_sessions session on session.id=a.class_session_id
      join public.classes c on c.id=session.class_id and c.academic_year_id=year_key
      join public.academic_years y on y.id=year_key
      join public.catalog_attendance_statuses status on status.id=a.attendance_status_id
      where a.institution_id=public.current_institution_id() and a.student_id=p_student_id
        and session.date>=coalesce(starts,y.start_date,'-infinity'::date)
        and session.date<=coalesce(ends,y.end_date,'infinity'::date);
  end if;
  select jsonb_build_object('studentName',trim(person.first_name||' '||person.last_name),
    'institutionName',i.name,'gradeLevel',coalesce(nullif(trim(coalesce(level.name,'')||' '||coalesce(section.name,'')),''),g.name,'—'),
    'yearStart',y.start_date,'yearEnd',y.end_date,'attendancePct',attendance,'rank',null,'totalPeers',null)
    into result from public.students student join public.persons person on person.id=student.person_id
    join public.institutions i on i.id=student.institution_id
    left join public.academic_years y on y.id=year_key
    left join public.enrollments e on e.student_id=student.id and e.academic_year_id=year_key and e.institution_id=i.id
    left join public.groups g on g.id=e.group_id left join public.grade_levels level on level.id=g.grade_level_id
    left join public.sections section on section.id=g.section_id
    where student.id=p_student_id and student.institution_id=public.current_institution_id();
  if result is null then raise exception 'Estudiante no encontrado.' using errcode='P0002'; end if;
  return result;
end $$;
revoke all on function public.student_report_context(bigint,bigint) from public,anon;
grant execute on function public.student_report_context(bigint,bigint) to authenticated;
-- END 0033_student_report_context.sql


-- BEGIN 0034_chat_queries.sql
-- SHA256 80d4917c4abdf9b3f6ca5e3e9fa34c0bc1a13f7ddb5283ca4a0fba7ddf0b436a
-- Chat reads are bounded pages. Authorization is performed once per RPC,
-- before reading any participant, message or receipt under SECURITY DEFINER.
create or replace function public.chat_actor() returns bigint
language plpgsql stable security definer set search_path=public as $$
declare actor bigint;
begin
  select u.id into actor from public.users u join public.institutions i on i.id=u.institution_id
    where u.auth_user_id=auth.uid() and u.institution_id=public.current_institution_id()
      and u.active and u.deleted_at is null and i.active and i.deleted_at is null;
  if actor is null or not public.auth_2fa_session_allowed() then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  return actor;
end $$;
revoke all on function public.chat_actor() from public,anon;
grant execute on function public.chat_actor() to authenticated;

create index if not exists idx_messages_conversation_id_live on public.messages(conversation_id,id desc) where deleted_at is null;

create or replace function public.chat_conversations(p_limit integer default 50,p_after_updated_at timestamptz default null,
  p_after_id bigint default null,p_conversation_id bigint default null,p_search text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if p_limit is null or p_limit<1 or p_limit>100 or length(p_search)>100
      or (p_after_updated_at is null)<>(p_after_id is null) then
    raise exception 'Paginación inválida.' using errcode='22023';
  end if;
  with owned as materialized (
    select c.*,last_msg.message,
      coalesce(last_msg.created_at,c.created_at) updated_at,
      (select count(*) from public.messages m where m.conversation_id=c.id and m.deleted_at is null
        and m.sender_id is distinct from actor
        and not exists(select 1 from public.message_reads r where r.message_id=m.id and r.user_id=actor)) unread
    from public.conversation_participants cp join public.conversations c on c.id=cp.conversation_id
    left join lateral (select m.created_at,to_jsonb(m)||jsonb_build_object('files',to_jsonb(f)) message
      from public.messages m left join public.files f on f.id=m.file_id
      where m.conversation_id=c.id and m.deleted_at is null order by m.id desc limit 1) last_msg on true
    where cp.user_id=actor and c.institution_id=public.current_institution_id()
  ), page as materialized (
    select * from owned c where (p_conversation_id is null or c.id=p_conversation_id)
      and (p_after_id is null or (c.updated_at,c.id)<(p_after_updated_at,p_after_id))
      and (nullif(trim(p_search),'') is null or c.title ilike '%'||p_search||'%'
        or c.message->>'content' ilike '%'||p_search||'%'
        or exists(select 1 from public.conversation_participants p join public.users u on u.id=p.user_id
          where p.conversation_id=c.id and u.full_name ilike '%'||p_search||'%'))
    order by updated_at desc,id desc limit p_limit+1
  ), visible as materialized (select * from page order by updated_at desc,id desc limit p_limit),
  people as (select p.conversation_id,jsonb_agg(jsonb_build_object('userId',u.id::text,'name',u.full_name,
    'avatarUrl',u.avatar_url,'isMe',u.id=actor,'role',coalesce((select r.code from public.user_roles ur
      join public.roles r on r.id=ur.role_id where ur.user_id=u.id order by case r.code when 'admin' then 0
      when 'director' then 1 when 'coordinator' then 2 when 'teacher' then 3 when 'parent' then 4 else 5 end,r.id limit 1),'student')) order by u.id) participants
    from visible v join public.conversation_participants p on p.conversation_id=v.id join public.users u on u.id=p.user_id
    group by p.conversation_id)
  select jsonb_build_object('conversations',coalesce((select jsonb_agg(jsonb_build_object(
    'id',v.id::text,'kind',case when v.kind='group' then 'group' else 'individual' end,
    'title',coalesce(nullif(v.title,''),(select string_agg(item->>'name',', ') from jsonb_array_elements(p.participants) item where not (item->>'isMe')::boolean),''),
    'participants',p.participants,'lastMessage',case when v.message is null then null else v.message||jsonb_build_object(
      'id',v.message->>'id','uuid',v.message->>'uuid','conversationId',v.id::text,'senderId',v.message->>'sender_id',
      'senderName',coalesce((select item->>'name' from jsonb_array_elements(p.participants) item where item->>'userId'=v.message->>'sender_id'),'Usuario'),
      'sentAt',v.message->>'created_at','hasAttachment',v.message->>'file_id' is not null,
      'attachment',case when v.message->>'file_id' is null then null else jsonb_build_object(
        'id',v.message->'files'->>'id','name',v.message->'files'->>'original_name',
        'url',v.message->'files'->>'url','sizeBytes',v.message->'files'->'size_bytes','mimeType',v.message->'files'->>'mime_type') end) end,
    'unreadCount',v.unread,'updatedAt',v.updated_at) order by v.updated_at desc,v.id desc)
    from visible v join people p on p.conversation_id=v.id),'[]'::jsonb),
    'totalUnread',coalesce((select sum(unread) from owned),0),
    'nextCursor',case when (select count(*) from page)>p_limit then
      (select jsonb_build_object('updatedAt',updated_at,'id',id::text) from visible order by updated_at,id limit 1) else null end)
    into result;
  return result;
end $$;

create or replace function public.chat_messages(p_conversation_id bigint,p_limit integer default 100,
  p_before_id bigint default null,p_after_id bigint default null,p_message_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if p_limit is null or p_limit<1 or p_limit>300 or (p_before_id is not null and p_after_id is not null) then
    raise exception 'Paginación inválida.' using errcode='22023';
  end if;
  if not exists(select 1 from public.conversations c join public.conversation_participants p on p.conversation_id=c.id
    where c.id=p_conversation_id and c.institution_id=public.current_institution_id() and p.user_id=actor) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  with page as materialized (
    (select m.* from public.messages m where p_after_id is null and m.conversation_id=p_conversation_id and m.deleted_at is null
      and (p_before_id is null or m.id<p_before_id) and (p_message_id is null or m.id=p_message_id) order by m.id desc limit p_limit+1)
    union all
    (select m.* from public.messages m where p_after_id is not null and m.conversation_id=p_conversation_id and m.deleted_at is null
      and m.id>p_after_id and (p_message_id is null or m.id=p_message_id) order by m.id asc limit p_limit+1)),
  visible as materialized (select * from page order by case when p_after_id is not null then id end asc,id desc limit p_limit)
  select jsonb_build_object('messages',coalesce((select jsonb_agg(jsonb_build_object(
    'id',m.id::text,'uuid',m.uuid,'conversationId',m.conversation_id::text,'senderId',m.sender_id::text,
    'senderName',coalesce(u.full_name,'Usuario'),'sentAt',m.created_at,'content',m.content,
    'attachment',case when f.id is null then null else jsonb_build_object('id',f.id::text,'name',f.original_name,
      'url',f.url,'sizeBytes',f.size_bytes,'mimeType',f.mime_type) end,
    'read',exists(select 1 from public.message_reads r where r.message_id=m.id and r.user_id<>m.sender_id)) order by m.id)
    from visible m left join public.users u on u.id=m.sender_id left join public.files f on f.id=m.file_id),'[]'::jsonb),
    'hasMore',(select count(*) from page)>p_limit,
    'nextBeforeId',(select min(id)::text from visible),'nextAfterId',(select max(id)::text from visible)) into result;
  return result;
end $$;

create or replace function public.chat_mark_read(p_conversation_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); read_time timestamptz:=clock_timestamp();
begin
  perform p.id from public.conversation_participants p join public.conversations c on c.id=p.conversation_id
    where c.id=p_conversation_id and c.institution_id=public.current_institution_id() and p.user_id=actor for update of p;
  if not found then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  insert into public.message_reads(message_id,user_id,read_at)
    select m.id,actor,read_time from public.messages m where m.conversation_id=p_conversation_id
      and m.sender_id is distinct from actor and m.deleted_at is null
      and not exists(select 1 from public.message_reads r where r.message_id=m.id and r.user_id=actor)
    on conflict(message_id,user_id) do nothing;
  update public.notifications set read=true,read_at=read_time where user_id=actor
    and institution_id=public.current_institution_id() and not read
    and data->>'conversationId'=p_conversation_id::text and created_at<=read_time;
  return jsonb_build_object('ok',true,'conversationId',p_conversation_id::text,'readAt',read_time);
end $$;

create or replace function public.chat_ensure_individual(p_other_user_id bigint) returns bigint
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); result bigint;
begin
  if p_other_user_id is null or p_other_user_id=actor then raise exception 'Usuario inválido.' using errcode='22023'; end if;
  if not public.portal_can('messages.send') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if not exists(select 1 from public.users where id=p_other_user_id and institution_id=inst and active and deleted_at is null) then
    raise exception 'Usuario destino no encontrado.' using errcode='P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('chat:'||inst||':'||least(actor,p_other_user_id)||':'||greatest(actor,p_other_user_id),0));
  select c.id into result from public.conversations c
    where c.institution_id=inst and c.kind in ('individual','direct')
      and exists(select 1 from public.conversation_participants where conversation_id=c.id and user_id=actor)
      and exists(select 1 from public.conversation_participants where conversation_id=c.id and user_id=p_other_user_id)
      and (select count(*) from public.conversation_participants where conversation_id=c.id)=2
    order by c.id limit 1;
  if result is null then
    insert into public.conversations(institution_id,kind,created_by) values(inst,'individual',actor) returning id into result;
    insert into public.conversation_participants(conversation_id,user_id,role) values(result,actor,'member'),(result,p_other_user_id,'member');
  end if;
  return result;
end $$;

revoke all on function public.chat_conversations(integer,timestamptz,bigint,bigint,text),
  public.chat_messages(bigint,integer,bigint,bigint,bigint),public.chat_mark_read(bigint),public.chat_ensure_individual(bigint) from public,anon;
grant execute on function public.chat_conversations(integer,timestamptz,bigint,bigint,text),
  public.chat_messages(bigint,integer,bigint,bigint,bigint),public.chat_mark_read(bigint),public.chat_ensure_individual(bigint) to authenticated;
-- END 0034_chat_queries.sql


-- BEGIN 0035_backend_request_context.sql
-- SHA256 73ea9f744638a536bda8128ca667044620c9ed6d778b75eec553f660855528b8
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
-- END 0035_backend_request_context.sql


-- BEGIN 0036_admin_people_page.sql
-- SHA256 79eb8e1f40dca6763d3da2099ed980f374a22ebae72e9683bda020b3950ca78c
-- Service-only directory page. The HTTP layer verifies administrative module
-- grants and derives the target institution; clients cannot invoke this RPC.
create or replace function public.admin_people_page(p_institution_id bigint,p_resource text,
  p_search text default null,p_active boolean default null,p_page integer default 1,p_page_size integer default 50,p_id bigint default null,p_group_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_resource is null or p_resource not in ('students','teachers','parents','all') or p_page is null or p_page<1
    or p_page_size is null or p_page_size<1 or p_page_size>100 or length(p_search)>120 then
    raise exception 'Filtros de directorio inválidos.' using errcode='22023';
  end if;
  with current_year as materialized (select id from public.academic_years where (p_institution_id is null or institution_id=p_institution_id) and is_current and active),
  raw as (
    select s.id,s.person_id,s.institution_id,s.active,s.student_code code,'student' role from public.students s where p_resource in ('students','all') and (p_institution_id is null or s.institution_id=p_institution_id)
    union all select t.id,t.person_id,t.institution_id,t.active,t.teacher_code,'teacher' from public.teachers t where p_resource in ('teachers','all') and (p_institution_id is null or t.institution_id=p_institution_id)
    union all select p.id,p.person_id,p.institution_id,true,null::text,'parent' from public.parents p where p_resource in ('parents','all') and (p_institution_id is null or p.institution_id=p_institution_id)
  ), base as materialized (
    select r.*,lower(p.first_name||' '||p.last_name) sort_name from raw r
      join public.persons p on p.id=r.person_id and p.institution_id=r.institution_id and p.deleted_at is null
    where (p_id is null or r.id=p_id)
      and (p_group_id is null or r.role='student' and exists(select 1 from public.enrollments e
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id
        where e.student_id=r.id and e.institution_id=r.institution_id and e.group_id=p_group_id
          and e.academic_year_id in(select id from current_year) and status.code='ACT')) and (p_active is null or r.active=p_active or p_resource='parents')
      and (nullif(trim(p_search),'') is null or p.first_name||' '||p.last_name ilike '%'||trim(p_search)||'%'
        or p.email ilike '%'||trim(p_search)||'%' or p.document_number ilike '%'||trim(p_search)||'%'
        or coalesce(r.code,'') ilike '%'||trim(p_search)||'%')
  ), page as materialized (select * from base order by sort_name,id,role limit p_page_size offset (p_page::bigint-1)*p_page_size),
  enriched as (
    select p.*,
      case p.role when 'student' then (select to_jsonb(s) from public.students s where s.id=p.id)
        when 'teacher' then (select to_jsonb(t) from public.teachers t where t.id=p.id)
        else (select to_jsonb(parent) from public.parents parent where parent.id=p.id) end payload,
      (select to_jsonb(person) from public.persons person where person.id=p.person_id) person,
      enrollment.group_id,g.name group_name,
      coalesce((select jsonb_agg(jsonb_build_object('id',c.id::text,'groupId',c.group_id::text,'subject',s.name,'groupName',cg.name) order by c.id)
        from public.classes c left join public.subjects s on s.id=c.subject_id left join public.groups cg on cg.id=c.group_id
        where c.institution_id=p.institution_id and c.active and c.academic_year_id in(select id from current_year)
          and ((p.role='student' and c.group_id=enrollment.group_id) or (p.role='teacher' and c.teacher_id=p.id))),'[]'::jsonb) classes,
      coalesce((select jsonb_agg(jsonb_build_object('id',child.id::text,'name',person.first_name||' '||person.last_name) order by child.id)
        from public.parent_students ps join public.students child on child.id=ps.student_id and child.institution_id=p.institution_id
        join public.persons person on person.id=child.person_id and person.deleted_at is null
        where p.role='parent' and ps.parent_id=p.id),'[]'::jsonb) children
    from page p left join lateral (select e.group_id from public.enrollments e join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id
      where p.role='student' and e.student_id=p.id and e.institution_id=p.institution_id and e.academic_year_id in(select id from current_year) and status.code='ACT'
      order by e.id desc limit 1) enrollment on true left join public.groups g on g.id=enrollment.group_id
  ), total as (select count(*) n from base)
  select jsonb_build_object('items',coalesce((select jsonb_agg(payload||jsonb_build_object('persons',person,'role',role,
      'group_id',group_id,'group_name',group_name,'classes',classes,'children',children,
      'class_ids',coalesce((select jsonb_agg(item->>'id') from jsonb_array_elements(classes) item),'[]'::jsonb),
      'child_ids',coalesce((select jsonb_agg(item->>'id') from jsonb_array_elements(children) item),'[]'::jsonb)) order by sort_name,id,role) from enriched),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,
      'totalPages',ceil(total.n::numeric/p_page_size),'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_people_page(bigint,text,text,boolean,integer,integer,bigint,bigint) from public,anon,authenticated;
grant execute on function public.admin_people_page(bigint,text,text,boolean,integer,integer,bigint,bigint) to service_role;

create or replace function public.admin_directory_options(p_institution_id bigint,p_kind text,p_search text default null,
  p_page integer default 1,p_page_size integer default 50,p_include_ids bigint[] default '{}')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_kind is null or p_kind not in ('students','teachers','parents','groups','classes') or p_institution_id is null
    or p_page is null or p_page<1 or p_page_size is null or p_page_size<1 or p_page_size>100
    or length(p_search)>120 or coalesce(array_length(p_include_ids,1),0)>100 then
    raise exception 'Filtros inválidos.' using errcode='22023';
  end if;
  with current_year as materialized (select id from public.academic_years where institution_id=p_institution_id and is_current and active),
  people as (
    select s.id,s.person_id from public.students s where p_kind='students' and s.institution_id=p_institution_id
    union all select t.id,t.person_id from public.teachers t where p_kind='teachers' and t.institution_id=p_institution_id
    union all select p.id,p.person_id from public.parents p where p_kind='parents' and p.institution_id=p_institution_id
  ), raw as materialized (
    select p.id,person.first_name||' '||person.last_name label,person.email subtitle,null::bigint group_id,null::bigint teacher_id,null::text room
      from people p join public.persons person on person.id=p.person_id and person.institution_id=p_institution_id and person.deleted_at is null
    union all select g.id,g.name,null,null,null,null from public.groups g
      where p_kind='groups' and g.institution_id=p_institution_id and g.active and g.academic_year_id in(select id from current_year)
    union all select c.id,coalesce(s.name,'Materia')||' ('||coalesce(g.name,'Sin salón')||')',null,c.group_id,c.teacher_id,room.name
      from public.classes c left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      left join public.classrooms room on room.id=g.classroom_id
      where p_kind='classes' and c.institution_id=p_institution_id and c.active and c.academic_year_id in(select id from current_year)
  ), matched as materialized (select * from raw where nullif(trim(p_search),'') is null or label ilike '%'||trim(p_search)||'%' or subtitle ilike '%'||trim(p_search)||'%'),
  page as (select * from matched order by lower(label),id limit p_page_size offset (p_page::bigint-1)*p_page_size),
  total as (select count(*) n from matched)
  select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',id::text,'label',label,'subtitle',subtitle,
    'groupId',group_id::text,'teacherId',teacher_id::text,'room',room) order by lower(label),id) from page),'[]'::jsonb),
    'selected',coalesce((select jsonb_agg(jsonb_build_object('id',id::text,'label',label)) from raw where id=any(p_include_ids)),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_directory_options(bigint,text,text,integer,integer,bigint[]) from public,anon,authenticated;
grant execute on function public.admin_directory_options(bigint,text,text,integer,integer,bigint[]) to service_role;

create or replace function public.admin_directory_counts(p_institution_id bigint) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce((select jsonb_object_agg(code,n) from (
    select 'student' code,count(*) n from public.students s join public.persons p on p.id=s.person_id where s.institution_id=p_institution_id and p.deleted_at is null
    union all select 'teacher',count(*) from public.teachers t join public.persons p on p.id=t.person_id where t.institution_id=p_institution_id and p.deleted_at is null
    union all select 'parent',count(*) from public.parents t join public.persons p on p.id=t.person_id where t.institution_id=p_institution_id and p.deleted_at is null
    union all select 'group',count(*) from public.groups g join public.academic_years y on y.id=g.academic_year_id
      where g.institution_id=p_institution_id and g.active and y.is_current and y.active
    union all select 'class',count(*) from public.classes c join public.academic_years y on y.id=c.academic_year_id
      where c.institution_id=p_institution_id and c.active and y.is_current and y.active
    union all select r.code,count(distinct u.id) from public.users u join public.user_roles ur on ur.user_id=u.id join public.roles r on r.id=ur.role_id
      where u.institution_id=p_institution_id and u.deleted_at is null and r.code in ('admin','super_admin','director','coordinator')
      and (r.institution_id is null or r.institution_id=p_institution_id) and (ur.institution_id is null or ur.institution_id=p_institution_id) group by r.code
  ) counts),'{}'::jsonb);
$$;
revoke all on function public.admin_directory_counts(bigint) from public,anon,authenticated;
grant execute on function public.admin_directory_counts(bigint) to service_role;

create or replace function public.admin_profiles_page(p_institution_id bigint,p_search text default null,p_page integer default 1,p_page_size integer default 50)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_institution_id is null or p_page is null or p_page<1 or p_page_size is null or p_page_size<1 or p_page_size>100 or length(p_search)>120 then
    raise exception 'Filtros inválidos.' using errcode='22023';
  end if;
  with base as materialized (
    select u.id from public.users u where u.institution_id=p_institution_id and u.deleted_at is null
      and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id
        and r.code in ('admin','coordinator','director') and (r.institution_id is null or r.institution_id=p_institution_id)
        and (ur.institution_id is null or ur.institution_id=p_institution_id))
      and (nullif(trim(p_search),'') is null or u.full_name ilike '%'||trim(p_search)||'%' or u.email ilike '%'||trim(p_search)||'%')
  ), page as (select u.id,u.institution_id,u.username,u.email,u.phone,u.full_name,u.active,u.admin_permissions,u.created_at,
    (select jsonb_agg(jsonb_build_object('roles',jsonb_build_object('code',r.code,'name',r.name)) order by r.code)
      from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id
        and (r.institution_id is null or r.institution_id=p_institution_id) and (ur.institution_id is null or ur.institution_id=p_institution_id)) user_roles
    from base b join public.users u on u.id=b.id order by lower(u.full_name),u.id limit p_page_size offset (p_page::bigint-1)*p_page_size),
  total as(select count(*) n from base)
  select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(page) order by lower(full_name),id) from page),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_profiles_page(bigint,text,integer,integer) from public,anon,authenticated;
grant execute on function public.admin_profiles_page(bigint,text,integer,integer) to service_role;

create or replace function public.admin_catalog_page(p_institution_id bigint,p_kind text default 'classes',p_search text default null,
  p_page integer default 1,p_page_size integer default 50,p_group_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_institution_id is null or p_kind is null or p_kind not in ('groups','classes') or p_page is null or p_page<1
    or p_page_size is null or p_page_size<1 or p_page_size>100 or length(p_search)>120 then
    raise exception 'Filtros inválidos.' using errcode='22023';
  end if;
  with current_year as materialized (select id from public.academic_years where institution_id=p_institution_id and active and is_current),
  matched as materialized (
    select g.id,g.name sort_name from public.groups g where p_kind='groups' and g.institution_id=p_institution_id and g.active
      and g.academic_year_id in(select id from current_year) and (p_group_id is null or g.id=p_group_id)
      and (nullif(trim(p_search),'') is null or g.name ilike '%'||trim(p_search)||'%')
    union all select c.id,coalesce(s.name,'')||' '||coalesce(g.name,'') from public.classes c
      left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      left join public.teachers t on t.id=c.teacher_id left join public.persons person on person.id=t.person_id
      where p_kind='classes' and c.institution_id=p_institution_id and c.active and c.academic_year_id in(select id from current_year)
        and (p_group_id is null or c.group_id=p_group_id)
        and (nullif(trim(p_search),'') is null or s.name ilike '%'||trim(p_search)||'%' or g.name ilike '%'||trim(p_search)||'%'
          or person.first_name||' '||person.last_name ilike '%'||trim(p_search)||'%')
  ), page as materialized (select * from matched order by lower(sort_name),id limit p_page_size offset (p_page::bigint-1)*p_page_size),
  class_page as materialized (select c.* from page p join public.classes c on p_kind='classes' and c.id=p.id),
  group_page as materialized (select g.* from public.groups g where g.institution_id=p_institution_id
    and ((p_kind='groups' and g.id in(select id from page)) or (p_kind='classes' and (g.id in(select group_id from class_page)
      or (g.id=p_group_id and g.active and g.academic_year_id in(select id from current_year)))))),
  total as (select count(*) n from matched)
  select jsonb_build_object('classes',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('subjects',jsonb_build_object('name',coalesce(s.name,'Materia')),
      'groups',jsonb_build_object('name',coalesce(g.name,'Sin salón'),'classrooms',jsonb_build_object('name',room.name))) order by lower(coalesce(s.name,'')||' '||coalesce(g.name,'')),c.id)
      from class_page c left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      left join public.classrooms room on room.id=g.classroom_id),'[]'::jsonb),
    'groups',coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('classrooms',
      (select jsonb_build_object('name',room.name) from public.classrooms room where room.id=g.classroom_id),
      'student_count',(select count(distinct e.student_id) from public.enrollments e join public.students student on student.id=e.student_id
        join public.persons person on person.id=student.person_id and person.deleted_at is null
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id where e.institution_id=p_institution_id and e.group_id=g.id and e.academic_year_id=g.academic_year_id and status.code='ACT'),
      'class_count',(select count(*) from public.classes c where c.institution_id=p_institution_id and c.group_id=g.id and c.academic_year_id=g.academic_year_id and c.active)) order by lower(g.name),g.id) from group_page g),'[]'::jsonb),
    'people',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'institution_id',t.institution_id,'person_id',t.person_id,'role','teacher','active',t.active,'group_id',null,'child_ids','[]'::jsonb,'class_ids','[]'::jsonb,
      'persons',jsonb_build_object('id',person.id,'first_name',person.first_name,'last_name',person.last_name,'email',person.email,'phone',person.phone)) order by t.id)
      from public.teachers t join public.persons person on person.id=t.person_id where t.institution_id=p_institution_id and t.id in(select teacher_id from class_page)),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_catalog_page(bigint,text,text,integer,integer,bigint) from public,anon,authenticated;
grant execute on function public.admin_catalog_page(bigint,text,text,integer,integer,bigint) to service_role;
-- END 0036_admin_people_page.sql


-- BEGIN 0037_scoped_directory_reads.sql
-- SHA256 29ad8b8aa660c1f559224da5506e1fa27696e94219f6c9c23bf80dae81f42b5d
create or replace function public.chat_contacts(p_search text default null,p_limit integer default 40) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if p_limit is null or p_limit<1 or p_limit>100 or length(p_search)>100 then raise exception 'Filtros inválidos.' using errcode='22023'; end if;
  with matches as (
    select u.id,u.full_name,u.email,u.avatar_url,coalesce(role.code,'student') code from public.users u
    left join lateral (select r.code from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_id=u.id and (ur.institution_id is null or ur.institution_id=u.institution_id) and (r.institution_id is null or r.institution_id=u.institution_id)
      order by case r.code when 'admin' then 0 when 'director' then 1 when 'coordinator' then 2 when 'teacher' then 3 when 'parent' then 4 else 5 end,r.id limit 1) role on true
    where u.institution_id=public.current_institution_id() and u.id<>actor and u.active and u.deleted_at is null
      and (nullif(trim(p_search),'') is null or u.full_name ilike '%'||trim(p_search)||'%' or u.email ilike '%'||trim(p_search)||'%'
        or exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id
          and (ur.institution_id is null or ur.institution_id=u.institution_id) and (r.institution_id is null or r.institution_id=u.institution_id)
          and (r.code ilike '%'||trim(p_search)||'%' or case r.code when 'teacher' then 'Maestro' when 'parent' then 'Padre'
            when 'student' then 'Estudiante' when 'admin' then 'Administrador' when 'coordinator' then 'Coordinador' when 'director' then 'Director' else r.name end ilike '%'||trim(p_search)||'%')))
    order by lower(u.full_name),u.id limit p_limit
  ) select jsonb_build_object('contacts',coalesce(jsonb_agg(jsonb_build_object('userId',id::text,'name',full_name,'email',coalesce(email,''),
    'role',code,'avatarUrl',avatar_url) order by lower(full_name),id),'[]'::jsonb)) into result from matches;
  return result;
end $$;
revoke all on function public.chat_contacts(text,integer) from public,anon;
grant execute on function public.chat_contacts(text,integer) to authenticated;

-- The dashboard only needs current assigned/collaborating classes, not the
-- complete management workspace with every invitation and teacher option.
create or replace function public.teacher_dashboard_classes() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if not public.portal_staff(actor) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  with candidates as materialized (
    select c.*,cc.permissions
      from public.classes c join public.academic_years y on y.id=c.academic_year_id and y.is_current and y.active
      left join public.class_collaborators cc on cc.class_id=c.id and cc.teacher_user_id=actor and cc.status='active'
      where c.institution_id=public.current_institution_id() and c.active
        and (cc.id is not null or exists(select 1 from public.teachers t join public.users u on u.person_id=t.person_id and u.institution_id=t.institution_id
          where t.id=c.teacher_id and t.active and u.id=actor))
  ), visible as materialized (
    select c.*,s.name subject_name,g.name group_name,public.class_permission(c.id,'collaborators.manage') owner from candidates c
      left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      where public.class_permission(c.id,'class.view')
  ) select jsonb_build_object('classes',coalesce(jsonb_agg(jsonb_build_object('classId',id,'groupId',group_id,'academicYearId',academic_year_id,
    'subjectName',coalesce(subject_name,'Materia'),'groupName',coalesce(group_name,'Grupo'),'isOwner',owner,
    'permissions',case when owner then to_jsonb(array['class.view','students.view','assignments.create','assignments.review','assignments.grade','grades.write','attendance.write','collaborators.manage'])
      else to_jsonb(permissions) end) order by subject_name,group_name,id),'[]'::jsonb)) into result from visible;
  return result;
end $$;
revoke all on function public.teacher_dashboard_classes() from public,anon;
grant execute on function public.teacher_dashboard_classes() to authenticated;

create or replace function public.latest_report_cards(p_period_id bigint default null,p_student_id bigint default null,p_group_id bigint default null,
  p_page integer default 1,p_page_size integer default 50) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); admin_actor boolean:=public.class_admin_actor(); result jsonb;
begin
  if p_page is null or p_page<1 or p_page_size is null or p_page_size<1 or p_page_size>100 then raise exception 'Paginación inválida.' using errcode='22023'; end if;
  if not public.portal_can('reports.view') or not public.admin_can('reports.view') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if not admin_actor and not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=actor and r.code in ('parent','student') and (ur.institution_id is null or ur.institution_id=public.current_institution_id())
      and (r.institution_id is null or r.institution_id=public.current_institution_id())) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if not admin_actor and (p_student_id is null or not exists(select 1 from public.users u join public.students s on s.institution_id=u.institution_id
    where u.id=actor and s.id=p_student_id and (s.person_id=u.person_id or exists(select 1 from public.parents p
      join public.parent_students ps on ps.parent_id=p.id where p.institution_id=u.institution_id and p.person_id=u.person_id and ps.student_id=s.id)))) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  with latest as materialized (
    select distinct on(rc.student_id,rc.academic_period_id) rc.* from public.report_cards rc
      where rc.institution_id=public.current_institution_id() and (p_student_id is null or rc.student_id=p_student_id)
        and (p_period_id is null or rc.academic_period_id=p_period_id)
        and (p_group_id is null or exists(select 1 from public.enrollments e join public.academic_years y on y.id=e.academic_year_id and y.is_current
          join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id join public.students student on student.id=e.student_id and student.active
          where e.student_id=rc.student_id and e.institution_id=rc.institution_id and e.group_id=p_group_id and status.code='ACT'))
      order by rc.student_id,rc.academic_period_id,rc.generated_at desc nulls last,rc.id desc
  ), allowed as materialized (select * from latest where admin_actor or public.portal_can_view_grades(student_id,academic_period_id)),
  page as(select * from allowed order by generated_at desc nulls last,id desc limit p_page_size offset (p_page::bigint-1)*p_page_size),
  total as(select count(*) n from allowed)
  select jsonb_build_object('reportCards',coalesce((select jsonb_agg(jsonb_build_object('id',rc.id::text,'studentId',rc.student_id::text,
    'studentName',trim(person.first_name||' '||person.last_name),'academicPeriodId',rc.academic_period_id::text,'periodName',period.name,
    'overallAverage',rc.overall_average,'status',coalesce(rc.status,'generated'),'generatedAt',rc.generated_at,'generalNotes',rc.general_notes)
    order by rc.generated_at desc nulls last,rc.id desc) from page rc join public.students student on student.id=rc.student_id
    join public.persons person on person.id=student.person_id left join public.academic_periods period on period.id=rc.academic_period_id),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.latest_report_cards(bigint,bigint,bigint,integer,integer) from public,anon;
grant execute on function public.latest_report_cards(bigint,bigint,bigint,integer,integer) to authenticated;
-- END 0037_scoped_directory_reads.sql


-- BEGIN 0038_schedule_integrity.sql
-- SHA256 0ec256b7e8dce669d94f9cc4c3bab49aa3833dcdfee89b244cec21b01b8691b1
-- Run docs/HORARIOS_TRANSACCIONALES.md preflight before deployment. Existing
-- conflicts abort this migration; no timetable is silently deleted or shifted.
create extension if not exists btree_gist;
alter table public.schedules
  add column academic_year_id bigint references public.academic_years(id),
  add column teacher_id bigint references public.teachers(id),
  add column room_key text,
  add column group_span int8range,
  add column time_span tsrange;

create or replace function public.schedule_derive() returns trigger
language plpgsql security definer set search_path=public as $$
declare c public.classes%rowtype; g public.groups%rowtype; room public.classrooms%rowtype;
begin
  if new.institution_id is null or new.weekday_id is null or new.weekday_id not between 1 and 7
    or new.start_time is null or new.end_time is null or new.start_time>=new.end_time
    or extract(second from new.start_time)<>0 or extract(second from new.end_time)<>0 then
    raise exception 'Día u horas inválidos; se requieren minutos completos.' using errcode='22023';
  end if;
  new.teacher_id:=null;
  if new.kind='class' then
    select * into c from public.classes where id=new.class_id for share;
    if not found or c.institution_id is distinct from new.institution_id or c.group_id is null or c.academic_year_id is null then
      raise exception 'Clase inválida para esta institución.' using errcode='22023';
    end if;
    new.group_id:=c.group_id; new.academic_year_id:=c.academic_year_id; new.teacher_id:=c.teacher_id;
    new.label:=null;
  else
    new.class_id:=null; new.classroom_id:=null;
    new.label:=coalesce(nullif(trim(new.label),''),'Receso');
  end if;
  if new.group_id is not null then
    select * into g from public.groups where id=new.group_id for share;
    if not found or g.institution_id is distinct from new.institution_id or g.academic_year_id is null
      or (new.kind='class' and g.academic_year_id is distinct from new.academic_year_id) then
      raise exception 'Grupo o año de clase inválido.' using errcode='22023';
    end if;
    new.academic_year_id:=g.academic_year_id;
  elsif new.academic_year_id is null then
    if (select count(*) from public.academic_years where institution_id=new.institution_id and is_current and active)<>1 then
      raise exception 'Se requiere un único año actual para el receso general.' using errcode='22023';
    end if;
    select id into new.academic_year_id from public.academic_years where institution_id=new.institution_id and is_current and active;
  end if;
  if not exists(select 1 from public.academic_years where id=new.academic_year_id and institution_id=new.institution_id) then
    raise exception 'Año académico inválido.' using errcode='22023';
  end if;
  if new.teacher_id is not null and not exists(select 1 from public.teachers where id=new.teacher_id and institution_id=new.institution_id) then
    raise exception 'Maestro de otra institución.' using errcode='22023';
  end if;
  new.room_key:=null;
  if new.classroom_id is not null then
    select * into room from public.classrooms where id=new.classroom_id for share;
    if not found or room.institution_id is distinct from new.institution_id or nullif(trim(room.name),'') is null then
      raise exception 'Aula inválida.' using errcode='22023';
    end if;
    new.room_key:=lower(trim(room.name));
  end if;
  new.group_span:=case when new.group_id is null then int8range(null,null,'()') else int8range(new.group_id,new.group_id,'[]') end;
  new.time_span:=tsrange(date '2000-01-01'+new.start_time,date '2000-01-01'+new.end_time,'[)');
  return new;
end $$;
create trigger schedules_derive before insert or update on public.schedules for each row execute function public.schedule_derive();
update public.schedules set kind=kind;
alter table public.schedules
  alter column institution_id set not null, alter column academic_year_id set not null,
  alter column weekday_id set not null, alter column start_time set not null, alter column end_time set not null,
  alter column group_span set not null, alter column time_span set not null,
  add constraint schedules_group_overlap exclude using gist
    (institution_id with =,academic_year_id with =,weekday_id with =,group_span with &&,time_span with &&),
  add constraint schedules_teacher_overlap exclude using gist
    (institution_id with =,academic_year_id with =,weekday_id with =,teacher_id with =,time_span with &&) where (teacher_id is not null),
  add constraint schedules_room_overlap exclude using gist
    (institution_id with =,academic_year_id with =,weekday_id with =,room_key with =,time_span with &&) where (room_key is not null);

-- Moving a class/group or renaming a physical room must revalidate its slots.
create or replace function public.schedule_source_refresh() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name='classes' then
    update public.schedules set class_id=class_id where class_id=new.id;
  elsif tg_table_name='groups' then
    update public.schedules set group_id=group_id where group_id=new.id;
  else
    update public.schedules set classroom_id=classroom_id where classroom_id=new.id;
  end if;
  return null;
end $$;
create trigger schedule_class_refresh after update of group_id,teacher_id,academic_year_id,institution_id on public.classes
  for each row when (old.* is distinct from new.*) execute function public.schedule_source_refresh();
create trigger schedule_group_refresh after update of academic_year_id,institution_id on public.groups
  for each row when (old.* is distinct from new.*) execute function public.schedule_source_refresh();
create trigger schedule_room_refresh after update of name,institution_id on public.classrooms
  for each row when (old.* is distinct from new.*) execute function public.schedule_source_refresh();

create or replace function public.schedule_admin_allowed(p_institution_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users u join public.institutions i on i.id=u.institution_id and i.active
    where u.auth_user_id=auth.uid() and u.active and u.deleted_at is null and public.auth_2fa_session_allowed()
    and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id
      and (ur.institution_id is null or ur.institution_id=u.institution_id) and (r.institution_id is null or r.institution_id=u.institution_id)
      and (r.code='super_admin' or r.code in('admin','director','coordinator') and u.institution_id=p_institution_id
        and (u.admin_permissions is null or p_permission=any(u.admin_permissions)))))
$$;
drop policy if exists admin_guard_insert on public.schedules;
drop policy if exists admin_guard_update on public.schedules;
drop policy if exists admin_guard_delete on public.schedules;
create policy admin_guard_insert on public.schedules as restrictive for insert to authenticated
  with check(public.schedule_admin_allowed(institution_id,'schedules.create'));
create policy admin_guard_update on public.schedules as restrictive for update to authenticated
  using(public.schedule_admin_allowed(institution_id,'schedules.edit')) with check(public.schedule_admin_allowed(institution_id,'schedules.edit'));
create policy admin_guard_delete on public.schedules as restrictive for delete to authenticated
  using(public.schedule_admin_allowed(institution_id,'schedules.delete'));

-- One DTO definition for reads and writes. Never granted directly to clients.
create or replace function public.schedule_view(p_id bigint) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',s.id::text,'kind',s.kind,'weekdayId',s.weekday_id,'weekdayIndex',s.weekday_id-1,
    'startTime',to_char(s.start_time,'HH24:MI'),'endTime',to_char(s.end_time,'HH24:MI'),
    'classId',s.class_id::text,'subject',case when s.kind='break' then s.label else coalesce(sub.name,'Clase') end,
    'groupId',s.group_id::text,'groupName',g.name,'teacherId',s.teacher_id::text,
    'teacher',nullif(trim(p.first_name||' '||p.last_name),''),'room',room.name,'shift',s.shift)
    from public.schedules s left join public.classes c on c.id=s.class_id left join public.subjects sub on sub.id=c.subject_id
    left join public.groups g on g.id=s.group_id left join public.teachers t on t.id=s.teacher_id
    left join public.persons p on p.id=t.person_id left join public.classrooms room on room.id=s.classroom_id where s.id=p_id
$$;
revoke all on function public.schedule_view(bigint) from public,anon,authenticated;

create or replace function public.schedule_write(p_institution_id bigint,p_action text,p_payload jsonb default '{}',p_id bigint default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare current_row public.schedules%rowtype; item public.schedules%rowtype; merged jsonb; day integer; days integer[];
  room_id bigint; room_name text; result jsonb:='[]'; permission text;
begin
  permission:=case p_action when 'create' then 'schedules.create' when 'update' then 'schedules.edit' when 'delete' then 'schedules.delete' end;
  if permission is null or not public.schedule_admin_allowed(p_institution_id,permission) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Cuerpo inválido.' using errcode='22023'; end if;
  -- Simultaneous GiST insertions can otherwise deadlock while checking several
  -- exclusion indexes. Serialize administrative writes within one institution;
  -- reads and other institutions remain independent. Direct writers retain the
  -- exclusion constraints and may need to retry an aborted transaction.
  perform pg_advisory_xact_lock(hashtextextended('schedule-write:'||p_institution_id,0));
  if p_action<>'create' then
    select * into current_row from public.schedules where id=p_id and institution_id=p_institution_id for update;
    if not found then raise exception 'Horario no encontrado.' using errcode='P0002'; end if;
    if p_action='delete' then delete from public.schedules where id=p_id; return jsonb_build_object('ok',true); end if;
    merged:=jsonb_build_object('kind',current_row.kind,'classId',current_row.class_id,'groupId',current_row.group_id,
      'label',current_row.label,'shift',current_row.shift,'weekdayId',current_row.weekday_id,
      'startTime',current_row.start_time,'endTime',current_row.end_time,'room',(select name from public.classrooms where id=current_row.classroom_id))||p_payload;
    days:=array[(merged->>'weekdayId')::integer];
  else
    merged:=p_payload;
    select array_agg(distinct value::integer order by value::integer) into days from jsonb_array_elements_text(merged->'weekdayIds');
  end if;
  if cardinality(days) is null or cardinality(days)<1 or cardinality(days)>7 or exists(select 1 from unnest(days) d where d is null or d not between 1 and 7) then
    raise exception 'Elige días válidos (1 a 7).' using errcode='22023';
  end if;
  item.kind:=coalesce(merged->>'kind','class'); item.class_id:=(merged->>'classId')::bigint;
  item.group_id:=(merged->>'groupId')::bigint; item.label:=merged->>'label'; item.shift:=merged->>'shift';
  item.start_time:=(merged->>'startTime')::time; item.end_time:=(merged->>'endTime')::time;
  if item.kind='class' and not exists(select 1 from public.classes c join public.academic_years y on y.id=c.academic_year_id
    where c.id=item.class_id and c.institution_id=p_institution_id and c.active and y.is_current and y.active) then
    raise exception 'Selecciona una clase activa del año actual.' using errcode='22023';
  end if;
  if item.kind='break' and item.group_id is not null and not exists(select 1 from public.groups g join public.academic_years y on y.id=g.academic_year_id
    where g.id=item.group_id and g.institution_id=p_institution_id and g.active and y.is_current and y.active) then
    raise exception 'Selecciona un grupo activo del año actual.' using errcode='22023';
  end if;
  room_name:=nullif(trim(merged->>'room'),'');
  if item.kind='class' and room_name is not null then
    if length(room_name)>50 then raise exception 'Nombre de aula demasiado largo.' using errcode='22023'; end if;
    perform pg_advisory_xact_lock(hashtextextended('schedule-room:'||p_institution_id||':'||lower(room_name),0));
    select id into room_id from public.classrooms where institution_id=p_institution_id and lower(trim(name))=lower(room_name) order by id limit 1;
    if room_id is null then insert into public.classrooms(institution_id,name,active) values(p_institution_id,room_name,true) returning id into room_id; end if;
  end if;
  foreach day in array days loop
    if p_action='create' then
      insert into public.schedules(institution_id,kind,class_id,group_id,label,shift,weekday_id,start_time,end_time,classroom_id)
        values(p_institution_id,item.kind,item.class_id,item.group_id,item.label,item.shift,day,item.start_time,item.end_time,room_id) returning id into item.id;
    else
      update public.schedules set kind=item.kind,class_id=item.class_id,group_id=item.group_id,label=item.label,shift=item.shift,
        weekday_id=day,start_time=item.start_time,end_time=item.end_time,classroom_id=room_id where id=p_id returning id into item.id;
    end if;
    result:=result||jsonb_build_array(public.schedule_view(item.id));
  end loop;
  return case when p_action='create' then jsonb_build_object('schedules',result) else jsonb_build_object('schedule',result->0) end;
end $$;

create or replace function public.schedule_list(p_institution_id bigint,p_filters jsonb default '{}',p_mine boolean default false,p_student_id bigint default null) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); groups_scope bigint[]; classes_scope bigint[]; result jsonb;
  page_number integer:=coalesce((p_filters->>'page')::integer,1); page_size integer:=coalesce((p_filters->>'pageSize')::integer,50);
begin
  if page_number<1 or page_size<1 or page_size>100 then raise exception 'Paginación inválida.' using errcode='22023'; end if;
  if not p_mine then
    if not public.schedule_admin_allowed(p_institution_id,'schedules.view') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  else
    if p_institution_id is distinct from public.current_institution_id() then raise exception 'Acceso denegado.' using errcode='42501'; end if;
    if p_student_id is not null then
      if not exists(select 1 from public.users u join public.students s on s.institution_id=u.institution_id and s.active
        where u.id=actor and s.id=p_student_id and (s.person_id=u.person_id or exists(select 1 from public.parents p
          join public.parent_students ps on ps.parent_id=p.id where p.institution_id=u.institution_id and p.person_id=u.person_id and ps.student_id=s.id))) then
        raise exception 'Acceso denegado.' using errcode='42501'; end if;
      select array_agg(e.group_id) into groups_scope from public.enrollments e join public.academic_years y on y.id=e.academic_year_id and y.is_current and y.active
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
        where e.institution_id=p_institution_id and e.student_id=p_student_id;
      select array_agg(c.id) into classes_scope from public.classes c where c.institution_id=p_institution_id and c.active and c.group_id=any(groups_scope);
    else
      with candidates as materialized (select c.id,c.group_id from public.classes c
        join public.academic_years y on y.id=c.academic_year_id and y.is_current and y.active
        where c.institution_id=p_institution_id and c.active
        and (exists(select 1 from public.teachers t join public.users u on u.person_id=t.person_id and u.institution_id=t.institution_id where t.id=c.teacher_id and u.id=actor and t.active)
          or exists(select 1 from public.class_collaborators cc where cc.class_id=c.id and cc.teacher_user_id=actor and cc.status='active')))
      select array_agg(c.id),array_agg(distinct c.group_id) into classes_scope,groups_scope from candidates c where public.class_permission(c.id,'class.view');
    end if;
  end if;
  with filtered as materialized (
    select s.id,s.weekday_id,s.start_time from public.schedules s join public.academic_years y on y.id=s.academic_year_id and y.is_current and y.active
    where s.institution_id=p_institution_id
      and (not p_mine or s.class_id=any(classes_scope) or s.kind='break' and (s.group_id is null or s.group_id=any(groups_scope))
        and exists(select 1 from public.schedules assigned where assigned.class_id=any(classes_scope) and assigned.academic_year_id=s.academic_year_id))
      and (nullif(p_filters->>'groupId','') is null or s.group_id is null or s.group_id=(p_filters->>'groupId')::bigint)
      and (nullif(p_filters->>'classId','') is null or s.class_id=(p_filters->>'classId')::bigint)
      and (nullif(p_filters->>'teacherId','') is null or s.teacher_id=(p_filters->>'teacherId')::bigint)
      and (nullif(p_filters->>'weekdayId','') is null or s.weekday_id=(p_filters->>'weekdayId')::integer)
      and (nullif(p_filters->>'shift','') is null or s.shift=p_filters->>'shift')
  ), page as(select * from filtered order by weekday_id,start_time,id limit case when p_mine then null else page_size end
    offset case when p_mine then 0 else (page_number::bigint-1)*page_size end), total as(select count(*) n from filtered)
  select jsonb_build_object('schedules',coalesce((select jsonb_agg(public.schedule_view(id) order by weekday_id,start_time,id) from page),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',page_number,'pageSize',page_size,'total',n,'totalPages',ceil(n::numeric/page_size),
      'hasNextPage',page_number::bigint*page_size<n,'hasPreviousPage',page_number>1)) into result from total;
  return result;
end $$;
revoke all on function public.schedule_derive(),public.schedule_source_refresh(),public.schedule_admin_allowed(bigint,text),
  public.schedule_write(bigint,text,jsonb,bigint),public.schedule_list(bigint,jsonb,boolean,bigint) from public,anon;
grant execute on function public.schedule_admin_allowed(bigint,text),public.schedule_write(bigint,text,jsonb,bigint),
  public.schedule_list(bigint,jsonb,boolean,bigint) to authenticated;
create index schedules_year_day_start on public.schedules(institution_id,academic_year_id,weekday_id,start_time,id);
-- END 0038_schedule_integrity.sql


-- BEGIN 0039_rls_query_plans.sql
-- SHA256 c3165069e1692b517b543d4738cfe753b6f6ccb6e1018331f032a9e3ddde0a5c
-- Cache ONLY statement-invariant helpers. Row-dependent class/student grants
-- remain evaluated against each resource; there is no cache across requests.
do $$
declare p record; expr text; check_expr text; pattern text;
begin
  for p in select pol.polname,n.nspname,c.relname,pg_get_expr(pol.polqual,pol.polrelid) qual,
      pg_get_expr(pol.polwithcheck,pol.polrelid) check_qual
    from pg_policy pol join pg_class c on c.oid=pol.polrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in('public','storage') loop
    expr:=p.qual; check_expr:=p.check_qual;
    foreach pattern in array array[
      '\m(public\.)?auth_2fa_session_allowed\(\)',
      '\m(public\.)?current_institution_id\(\)',
      '\m(public\.)?class_admin_actor\(\)',
      '\m(public\.)?is_teacher_actor\(\)',
      '\mauth\.uid\(\)', '\mauth\.jwt\(\)',
      '\m(public\.)?admin_can\(''[^'']+''::text\)',
      '\m(public\.)?portal_can\(''[^'']+''::text\)'
    ] loop
      expr:=regexp_replace(expr,pattern,'(select \& )','g');
      check_expr:=regexp_replace(check_expr,pattern,'(select \& )','g');
    end loop;
    if expr is distinct from p.qual or check_expr is distinct from p.check_qual then
      execute format('alter policy %I on %I.%I %s %s',p.polname,p.nspname,p.relname,
        case when expr is null then '' else 'using ('||expr||')' end,
        case when check_expr is null then '' else 'with check ('||check_expr||')' end);
    end if;
  end loop;
end $$;

-- Match actual filters/order or relationship lookups. Existing leading-key
-- indexes are retained; none is dropped on speculation about other clients.
create index parent_students_parent_student on public.parent_students(parent_id,student_id);
create index teachers_institution_person on public.teachers(institution_id,person_id);
create index parents_institution_person on public.parents(institution_id,person_id);
create index students_institution_person on public.students(institution_id,person_id);
create index notifications_user_recent on public.notifications(user_id,created_at desc,id desc);
create index enrollments_current_roster on public.enrollments(institution_id,academic_year_id,group_id,enrollment_status_id,student_id);
create index classes_current_teacher on public.classes(institution_id,academic_year_id,teacher_id,id) where active;
create index persons_full_name_search on public.persons using gin ((first_name||' '||last_name) gin_trgm_ops) where deleted_at is null;
-- END 0039_rls_query_plans.sql


-- BEGIN 0040_live_role_scope.sql
-- SHA256 1b2bdd0c78d6134007275c55119bb282b6da50858e9c91323c623f591f3fd479
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
-- END 0040_live_role_scope.sql


-- BEGIN 0041_schedule_read_scope.sql
-- SHA256 26287ee329150a119b47f36ee6d7a0ade065fd8244a100ab8f3602d1dc524ccb
-- One uncorrelated scope per statement; never cache it across sessions/queries.
create or replace function public.schedule_visible_ids() returns setof bigint
language sql stable security definer set search_path=public as $$
  with actor as materialized(select u.*,public.user_has_role(u.id,'teacher') teacher,public.user_has_role(u.id,'parent') parent,
      public.user_has_role(u.id,'student') student from public.users u where u.auth_user_id=auth.uid() and u.institution_id=(select public.current_institution_id())),
  teacher_classes as materialized (
    select c.id,c.group_id,c.academic_year_id from actor u join public.teachers t on t.institution_id=u.institution_id and t.person_id=u.person_id and t.active
      join public.classes c on c.teacher_id=t.id and c.institution_id=u.institution_id and c.active where u.teacher
    union
    select c.id,c.group_id,c.academic_year_id from actor u join public.teachers t on t.institution_id=u.institution_id and t.person_id=u.person_id and t.active
      join public.class_collaborators cc on cc.teacher_user_id=u.id and cc.teacher_id=t.id and cc.institution_id=u.institution_id and cc.status='active' and 'class.view'=any(cc.permissions)
      join public.classes c on c.id=cc.class_id and c.institution_id=u.institution_id and c.active where u.teacher
  ), family_students as materialized (
    select s.id,s.institution_id from actor u join public.students s on s.person_id=u.person_id and s.institution_id=u.institution_id and s.active where u.student
    union
    select s.id,s.institution_id from actor u join public.parents p on p.person_id=u.person_id and p.institution_id=u.institution_id
      join public.parent_students ps on ps.parent_id=p.id join public.students s on s.id=ps.student_id and s.institution_id=u.institution_id and s.active where u.parent
  ), family_classes as materialized (
    select c.id,c.group_id,c.academic_year_id from family_students student join public.enrollments e on e.student_id=student.id and e.institution_id=student.institution_id
      join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
      join public.classes c on c.group_id=e.group_id and c.academic_year_id=e.academic_year_id and c.institution_id=e.institution_id and c.active
  ), own_classes as materialized (
    select c.id,c.group_id from (select * from teacher_classes union select * from family_classes) c
      join public.academic_years y on y.id=c.academic_year_id and y.is_current and y.active
  ) select s.id from public.schedules s join public.academic_years y on y.id=s.academic_year_id and y.is_current and y.active
    where s.institution_id=(select public.current_institution_id()) and (
      s.class_id in(select id from own_classes) or s.kind='break' and (s.group_id is null or s.group_id in(select group_id from own_classes))
        and exists(select 1 from public.schedules assigned where assigned.class_id in(select id from own_classes)))
$$;
revoke all on function public.schedule_visible_ids() from public,anon;
grant execute on function public.schedule_visible_ids() to authenticated;
create policy schedule_scoped_read on public.schedules as restrictive for select to authenticated
  using ((select public.administrative_permission(public.current_institution_id(),'schedules.view')) or id in(select public.schedule_visible_ids()));
-- END 0041_schedule_read_scope.sql


-- BEGIN 0042_class_role_permissions.sql
-- SHA256 f21fd66dcc41d0b54825abad759fffa9513c8e36635c87e1c0ad2870738c8a00
-- A teacher grant is a resource grant even when that account also has a limited
-- administrative profile. It does not give that profile a tenant-wide bypass.
create or replace function public.teacher_class_permission(p_class_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.classes c join public.users u on u.institution_id=c.institution_id
    join public.teachers t on t.institution_id=u.institution_id and t.person_id=u.person_id and t.active
    where c.id=p_class_id and c.active and c.institution_id=public.current_institution_id() and u.auth_user_id=auth.uid()
      and public.user_has_role(u.id,'teacher') and (c.teacher_id=t.id or p_permission<>'collaborators.manage'
        and exists(select 1 from public.class_collaborators cc where cc.class_id=c.id and cc.institution_id=c.institution_id
          and cc.teacher_id=t.id and cc.teacher_user_id=u.id and cc.status='active' and p_permission=any(cc.permissions))))
$$;
revoke all on function public.teacher_class_permission(bigint,text) from public,anon;
grant execute on function public.teacher_class_permission(bigint,text) to authenticated;

create or replace function public.class_permission(p_class_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$
  select public.teacher_class_permission(p_class_id,p_permission) or exists(select 1 from public.classes c
    where c.id=p_class_id and c.active and c.institution_id=public.current_institution_id()
      and exists(select 1 from unnest(case p_permission
        when 'class.view' then array['classes.view','reports.view','schedules.view','dashboard.view']
        when 'students.view' then array['students.view','classes.view','reports.view']
        when 'assignments.review' then array['classes.view','reports.view']
        when 'assignments.grade' then array['reports.generate']
        when 'grades.write' then array['reports.generate']
        when 'assignments.create' then array['classes.edit']
        when 'attendance.write' then array['classes.edit']
        when 'collaborators.manage' then array['classes.edit']
        else array[]::text[] end) permission where public.administrative_permission(c.institution_id,permission)))
$$;

do $$ declare tbl text; cmd text; permission text; cid text; expr text; begin
  foreach tbl in array array['evaluations','grades','period_grades'] loop
    cid:=case when tbl='grades' then '(select class_id from public.evaluations where id=evaluation_id)' else 'class_id' end;
    foreach cmd in array array['select','insert','update','delete'] loop
      permission:=case when cmd='select' then 'reports.view' else 'reports.generate' end;
      expr:=format('(select public.admin_can(%L)) or public.teacher_class_permission(%s,%L)',permission,cid,
        case when cmd='select' then 'class.view' else 'grades.write' end);
      execute format('drop policy if exists admin_guard_%s on public.%I',cmd,tbl);
      if cmd='insert' then execute format('create policy admin_guard_insert on public.%I as restrictive for insert to authenticated with check(%s)',tbl,expr);
      elsif cmd='update' then execute format('create policy admin_guard_update on public.%I as restrictive for update to authenticated using(%s) with check(%s)',tbl,expr,expr);
      else execute format('create policy admin_guard_%s on public.%I as restrictive for %s to authenticated using(%s)',cmd,tbl,cmd,expr); end if;
    end loop;
  end loop;
end $$;
-- END 0042_class_role_permissions.sql


-- BEGIN 0043_identity_permission_guards.sql
-- SHA256 6c5c9943a5c12440eef785a8b9a11d33190927d31338d8ecef68a0739d290c00
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
-- END 0043_identity_permission_guards.sql


-- BEGIN 0044_year_grade_visibility.sql
-- SHA256 dcd0078bf0809b3aa909870d002c423f94c816591de77a98bdb2f6b70d9c3f23
-- Known-year aggregates do not consult unrelated historical periods. Legacy
-- annual documents without a year keep the conservative all-period check.
create or replace function public.portal_can_view_year_grades(p_student_id bigint,p_year_id bigint) returns boolean
language plpgsql stable security definer set search_path=public as $$
declare actor public.users%rowtype; result boolean;
begin
  if p_year_id is null then return public.portal_can_view_grades(p_student_id,null); end if;
  select * into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id();
  if actor.id is null or not public.portal_student_scope(p_student_id) or not exists(select 1 from public.academic_years where id=p_year_id and institution_id=actor.institution_id) then return false; end if;
  if public.portal_staff(actor.id) then return true; end if;
  if not public.portal_can('grades.view') then return false; end if;
  if exists(select 1 from public.academic_periods p where p.institution_id=actor.institution_id and p.academic_year_id=p_year_id
    and not public.portal_can_view_grades(p_student_id,p.id)) then return false; end if;
  select q.allowed into result from public.grade_visibility_rules q where q.institution_id=actor.institution_id and q.academic_period_id is null
    and (q.scope='institution' or q.scope='user' and q.user_id=actor.id or q.scope='student' and q.student_id=p_student_id
      or q.scope='role' and public.user_has_role(actor.id,q.role_code) or q.scope='group' and exists(select 1 from public.enrollments e
        where e.student_id=p_student_id and e.group_id=q.group_id and e.academic_year_id=p_year_id and e.institution_id=actor.institution_id))
    order by case q.scope when 'user' then 5 when 'student' then 4 when 'group' then 3 when 'role' then 2 else 1 end desc,q.allowed asc limit 1;
  return coalesce(result,true);
end $$;
revoke all on function public.portal_can_view_year_grades(bigint,bigint) from public,anon;
grant execute on function public.portal_can_view_year_grades(bigint,bigint) to authenticated;

create or replace function public.report_document_scope(p_student_id bigint,p_year_id bigint) returns boolean
language sql stable security definer set search_path=public as $$
  select public.administrative_permission(public.current_institution_id(),'reports.view') or public.family_student_scope(p_student_id)
    or exists(select 1 from public.enrollments e join public.classes c on c.group_id=e.group_id and c.academic_year_id=e.academic_year_id
      and c.institution_id=e.institution_id where e.student_id=p_student_id and e.institution_id=public.current_institution_id()
        and (p_year_id is null or e.academic_year_id=p_year_id) and public.teacher_class_permission(c.id,'students.view'))
$$;
revoke all on function public.report_document_scope(bigint,bigint) from public,anon;
grant execute on function public.report_document_scope(bigint,bigint) to authenticated;

drop policy if exists portal_grade_read on public.grades;
create policy portal_grade_read on public.grades as restrictive for select to authenticated using(exists(
  select 1 from public.evaluations e join public.classes c on c.id=e.class_id where e.id=evaluation_id
    and case when e.academic_period_id is not null then public.portal_can_view_grades(student_id,e.academic_period_id)
      else public.portal_can_view_year_grades(student_id,c.academic_year_id) end));
drop policy if exists portal_grade_read on public.period_grades;
create policy portal_grade_read on public.period_grades as restrictive for select to authenticated using(
  case when academic_period_id is not null then public.portal_can_view_grades(student_id,academic_period_id)
    else public.portal_can_view_year_grades(student_id,(select academic_year_id from public.classes c where c.id=class_id)) end);

-- Backfill only authoritative references; unknown legacy annuals remain unknown.
update public.report_cards r set academic_year_id=e.academic_year_id from public.enrollments e
  where r.academic_year_id is null and r.enrollment_id=e.id and r.student_id=e.student_id and r.institution_id=e.institution_id;
update public.report_cards r set academic_year_id=p.academic_year_id from public.academic_periods p
  where r.academic_year_id is null and r.academic_period_id=p.id and r.institution_id=p.institution_id;

create or replace function public.dashboard_student_average(p_student_id bigint) returns numeric
language plpgsql stable set search_path=public as $$
declare result numeric; year_id bigint;
begin
  select id into year_id from public.academic_years where institution_id=public.current_institution_id() and is_current and active;
  if p_student_id is null or year_id is null or not public.portal_can_view_year_grades(p_student_id,year_id) then
    raise exception 'Acceso denegado.' using errcode='42501'; end if;
  select coalesce(avg(v.weighted_pct),0) into result from public.student_weighted_averages v
    join public.academic_periods p on p.id=v.academic_period_id and p.academic_year_id=year_id
    where v.institution_id=public.current_institution_id() and v.student_id=p_student_id;
  return result;
end $$;

drop policy if exists portal_grade_read on public.report_cards;
create policy portal_grade_read on public.report_cards as restrictive for select to authenticated
  using ((select public.portal_can('reports.view')) and (select public.portal_can('reports.download')) and public.report_document_scope(student_id,academic_year_id) and
    case when academic_period_id is not null then public.portal_can_view_grades(student_id,academic_period_id)
      else public.portal_can_view_year_grades(student_id,academic_year_id) end);

create or replace function public.student_report_context(p_student_id bigint,p_period_id bigint default null)
returns jsonb language plpgsql stable set search_path=public as $$
declare year_key bigint; starts date; ends date; attendance numeric; result jsonb;
begin
  if not public.portal_student_scope(p_student_id) or not public.portal_can('reports.view')
      or not public.admin_can('reports.view') then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  if p_period_id is not null then
    select academic_year_id,start_date,end_date into year_key,starts,ends from public.academic_periods
      where id=p_period_id and institution_id=public.current_institution_id();
    if not found then raise exception 'Periodo no encontrado.' using errcode='P0002'; end if;
  else
    select id,start_date,end_date into year_key,starts,ends from public.academic_years
      where institution_id=public.current_institution_id() and is_current;
  end if;
  if not (case when p_period_id is null then public.portal_can_view_year_grades(p_student_id,year_key) else public.portal_can_view_grades(p_student_id,p_period_id) end) then
    raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if year_key is not null and public.portal_can('attendance.view') then
    select round(100.0*count(*) filter(where not coalesce(status.counts_as_absent,false))/nullif(count(*),0),1)
      into attendance from public.attendances a
      join public.class_sessions session on session.id=a.class_session_id
      join public.classes c on c.id=session.class_id and c.academic_year_id=year_key
      join public.academic_years y on y.id=year_key
      join public.catalog_attendance_statuses status on status.id=a.attendance_status_id
      where a.institution_id=public.current_institution_id() and a.student_id=p_student_id
        and session.date>=coalesce(starts,y.start_date,'-infinity'::date)
        and session.date<=coalesce(ends,y.end_date,'infinity'::date);
  end if;
  select jsonb_build_object('studentName',trim(person.first_name||' '||person.last_name),
    'institutionName',i.name,'gradeLevel',coalesce(nullif(trim(coalesce(level.name,'')||' '||coalesce(section.name,'')),''),g.name,'—'),
    'yearStart',y.start_date,'yearEnd',y.end_date,'attendancePct',attendance,'rank',null,'totalPeers',null)
    into result from public.students student join public.persons person on person.id=student.person_id
    join public.institutions i on i.id=student.institution_id
    left join public.academic_years y on y.id=year_key
    left join public.enrollments e on e.student_id=student.id and e.academic_year_id=year_key and e.institution_id=i.id
    left join public.groups g on g.id=e.group_id left join public.grade_levels level on level.id=g.grade_level_id
    left join public.sections section on section.id=g.section_id
    where student.id=p_student_id and student.institution_id=public.current_institution_id();
  if result is null then raise exception 'Estudiante no encontrado.' using errcode='P0002'; end if;
  return result;
end $$;

create or replace function public.latest_report_cards(p_period_id bigint default null,p_student_id bigint default null,p_group_id bigint default null,
  p_page integer default 1,p_page_size integer default 50) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); admin_actor boolean:=public.class_admin_actor(); result jsonb;
begin
  if p_page is null or p_page<1 or p_page_size is null or p_page_size<1 or p_page_size>100 then raise exception 'Paginación inválida.' using errcode='22023'; end if;
  if not public.portal_can('reports.view') or not public.admin_can('reports.view') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if not admin_actor and not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=actor and r.code in ('parent','student') and (ur.institution_id is null or ur.institution_id=public.current_institution_id())
      and (r.institution_id is null or r.institution_id=public.current_institution_id())) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if not admin_actor and (p_student_id is null or not exists(select 1 from public.users u join public.students s on s.institution_id=u.institution_id
    where u.id=actor and s.id=p_student_id and (s.person_id=u.person_id or exists(select 1 from public.parents p
      join public.parent_students ps on ps.parent_id=p.id where p.institution_id=u.institution_id and p.person_id=u.person_id and ps.student_id=s.id)))) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  with latest as materialized (
    select distinct on(rc.student_id,rc.academic_period_id) rc.* from public.report_cards rc
      where rc.institution_id=public.current_institution_id() and (p_student_id is null or rc.student_id=p_student_id)
        and (p_period_id is null or rc.academic_period_id=p_period_id)
        and (p_group_id is null or exists(select 1 from public.enrollments e join public.academic_years y on y.id=e.academic_year_id and y.is_current
          join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id join public.students student on student.id=e.student_id and student.active
          where e.student_id=rc.student_id and e.institution_id=rc.institution_id and e.group_id=p_group_id and status.code='ACT'))
      order by rc.student_id,rc.academic_period_id,rc.generated_at desc nulls last,rc.id desc
  ), allowed as materialized (select * from latest where admin_actor or case when academic_period_id is null then public.portal_can_view_year_grades(student_id,academic_year_id) else public.portal_can_view_grades(student_id,academic_period_id) end),
  page as(select * from allowed order by generated_at desc nulls last,id desc limit p_page_size offset (p_page::bigint-1)*p_page_size),
  total as(select count(*) n from allowed)
  select jsonb_build_object('reportCards',coalesce((select jsonb_agg(jsonb_build_object('id',rc.id::text,'studentId',rc.student_id::text,
    'studentName',trim(person.first_name||' '||person.last_name),'academicPeriodId',rc.academic_period_id::text,'periodName',period.name,
    'overallAverage',rc.overall_average,'status',coalesce(rc.status,'generated'),'generatedAt',rc.generated_at,'generalNotes',rc.general_notes)
    order by rc.generated_at desc nulls last,rc.id desc) from page rc join public.students student on student.id=rc.student_id
    join public.persons person on person.id=student.person_id left join public.academic_periods period on period.id=rc.academic_period_id),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;

create or replace function public.portal_access_me() returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor public.users%rowtype; perms jsonb:='{}'; children jsonb; code text; year_key bigint;
begin
 select * into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id() and active and deleted_at is null;
 if actor.id is null then raise exception 'Sesión requerida.' using errcode='42501'; end if;
 select id into year_key from public.academic_years where institution_id=actor.institution_id and is_current and active;
 foreach code in array array['grades.view','payments.view','attendance.view','schedule.view','assignments.view','assignments.submit','reports.view','reports.download','announcements.view','messages.send','materials.view'] loop
   perms:=perms||jsonb_build_object(code,public.portal_can(code));
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'name',p.first_name||' '||p.last_name,
   'academicYearId',year_key,'annualVisible',case when year_key is null then false else public.portal_can_view_year_grades(s.id,year_key) end,'periods',(select coalesce(jsonb_agg(jsonb_build_object('id',ap.id,'name',ap.name,'visible',public.portal_can_view_grades(s.id,ap.id)) order by ap.start_date),'[]') from public.academic_periods ap where ap.institution_id=actor.institution_id)) order by s.id),'[]') into children
 from public.students s join public.persons p on p.id=s.person_id where s.institution_id=actor.institution_id and not public.portal_staff(actor.id) and public.portal_student_scope(s.id);
 return jsonb_build_object('permissions',perms,'students',children,'staff',public.portal_staff(actor.id));
end $$;


create or replace function public.portal_file_read(p_file_id bigint) returns boolean language plpgsql stable security definer set search_path=public as $$
declare f public.files%rowtype; actor public.users%rowtype;
begin
 select * into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id() and active and deleted_at is null;
 select * into f from public.files where id=p_file_id and institution_id=actor.institution_id;
 if actor.id is null or f.id is null then return false; end if;
 if exists(select 1 from public.report_cards r where r.institution_id=actor.institution_id and r.pdf_url=f.url) then
   return public.admin_can('reports.view') and public.portal_can('reports.view') and public.portal_can('reports.download') and exists(select 1 from public.report_cards r where r.pdf_url=f.url and public.report_document_scope(r.student_id,r.academic_year_id) and (case when r.academic_period_id is null then public.portal_can_view_year_grades(r.student_id,r.academic_year_id) else public.portal_can_view_grades(r.student_id,r.academic_period_id) end));
 end if;
 if public.portal_staff(actor.id) then return true; end if;
 if f.uploaded_by=actor.id then return true; end if;
 if exists(select 1 from public.assignment_files af where af.file_id=f.id) then
   return public.portal_can('materials.view') and public.portal_can('assignments.view') and exists(select 1 from public.assignment_files af join public.assignments a on a.id=af.assignment_id where af.file_id=f.id and public.portal_class_scope(a.class_id));
 end if;
 if exists(select 1 from public.submission_files sf where sf.file_id=f.id) then
   return public.portal_can('materials.view') and public.portal_can('assignments.view') and exists(select 1 from public.submission_files sf join public.submissions s on s.id=sf.submission_id where sf.file_id=f.id and public.portal_student_scope(s.student_id));
 end if;
 return public.portal_can('materials.view');
end $$;
-- END 0044_year_grade_visibility.sql


-- BEGIN 0045_announcement_delivery_scaling.sql
-- SHA256 726875cc9b44843cd919649f1e3293ed88399a5bd3bd727062c62730738e37bc
alter table public.announcement_delivery_jobs add column prepared_at timestamptz,add column last_claimed_at timestamptz,
  add column email_review integer not null default 0;
alter table public.announcement_delivery_recipients add column email_first_attempt_at timestamptz,add column email_key_suffix uuid;
alter table public.announcement_delivery_recipients drop constraint announcement_delivery_recipients_email_status_check;
alter table public.announcement_delivery_recipients add constraint announcement_delivery_recipients_email_status_check
  check(email_status in('pending','sent','skipped','failed','needs_review'));
update public.announcement_delivery_jobs j set prepared_at=j.updated_at where phase='email' or status in('completed','completed_with_errors')
  or total>0 or exists(select 1 from public.announcement_delivery_recipients r where r.job_id=j.id);
-- Previous workers did not persist the first email attempt. Publication time
-- is the only conservative lower bound; do not restart a stale provider key.
update public.announcement_delivery_recipients r set email_first_attempt_at=j.created_at
  from public.announcement_delivery_jobs j where r.job_id=j.id and j.prepared_at is not null and r.email_status='pending';
-- A one-time backfill supports jobs already processed by the previous worker.
with counts as(select job_id,count(*) filter(where email_status<>'pending' and push_status<>'pending') processed,
  count(*) filter(where email_status='sent') emailed,count(*) filter(where email_status='failed') email_failed,
  count(*) filter(where email_status='skipped') email_skipped,count(*) filter(where push_status='failed') push_failed
  from public.announcement_delivery_recipients group by job_id)
update public.announcement_delivery_jobs j set processed=c.processed,emailed=c.emailed,email_failed=c.email_failed,
  email_skipped=c.email_skipped,push_failed=c.push_failed from counts c where j.id=c.job_id;

create or replace function public.claim_announcement_delivery() returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype;
begin
  -- Serialize only admission, not delivery. One active job per institution and
  -- four globally; a successful slice returns to the back of the ready queue.
  perform pg_advisory_xact_lock(hashtext('announcement_delivery_worker'));
  if (select count(*) from public.announcement_delivery_jobs where status='processing' and lease_until>clock_timestamp())>=4 then return null; end if;
  select candidate.* into j from public.announcement_delivery_jobs candidate
    where ((candidate.status='queued' and candidate.next_attempt_at<=clock_timestamp())
      or (candidate.status='processing' and candidate.lease_until<=clock_timestamp()))
      and not exists(select 1 from public.announcement_delivery_jobs active where active.institution_id=candidate.institution_id
        and active.id<>candidate.id and active.status='processing' and active.lease_until>clock_timestamp())
    order by coalesce(candidate.last_claimed_at,'-infinity'),candidate.next_attempt_at,candidate.id for update of candidate skip locked limit 1;
  if not found then return null; end if;
  update public.announcement_delivery_jobs set status='processing',phase=case when prepared_at is null then 'notifications' else 'email' end,
    lock_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes',attempts=attempts+1,
    last_claimed_at=clock_timestamp(),updated_at=clock_timestamp() where id=j.id returning * into j;
  return to_jsonb(j);
end $$;

create or replace function public.record_announcement_delivery(
  p_job_id bigint,p_lock uuid,p_user_id bigint,p_email_status text,p_push_status text,p_email_id text default null,p_error text default null
) returns void language plpgsql security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype; r public.announcement_delivery_recipients%rowtype;
  next_email text; next_push text;
begin
  if p_email_status is null or p_email_status not in('pending','sent','skipped','failed','needs_review')
    or p_push_status is null or p_push_status not in('pending','sent','skipped','failed') then
    raise exception 'delivery_status_invalid' using errcode='22023'; end if;
  select * into j from public.announcement_delivery_jobs where id=p_job_id and lock_token=p_lock and status='processing'
    and lease_until>clock_timestamp() for update;
  if not found then raise exception 'delivery_lease_lost'; end if;
  select * into r from public.announcement_delivery_recipients where job_id=j.id and user_id=p_user_id for update;
  if not found then
    if not exists(select 1 from public.users where id=p_user_id) then return; end if;
    raise exception 'delivery_recipient_missing';
  end if;
  next_email:=case when r.email_status in('sent','needs_review') then r.email_status
    when p_email_status='pending' and r.email_status<>'pending' then r.email_status else p_email_status end;
  next_push:=case when r.push_status='sent' then 'sent' when p_push_status='pending' and r.push_status<>'pending' then r.push_status else p_push_status end;
  if r.email_status='pending' and next_email in('sent','failed','needs_review') then
    insert into public.notification_deliveries(notification_id,channel_id,destination,status,provider,external_ref,error,sent_at)
      values(r.notification_id,(select id from public.catalog_notification_channels where code='EMAIL'),r.email,
        case when next_email='sent' then 'sent' else 'failed' end,'resend',p_email_id,p_error,case when next_email='sent' then clock_timestamp() end);
  end if;
  update public.announcement_delivery_recipients set email_status=next_email,push_status=next_push,
    email_id=coalesce(email_id,p_email_id),last_error=case when next_email='sent' then null
      when next_email='needs_review' then coalesce(p_error,last_error) else p_error end where job_id=j.id and user_id=p_user_id;
  -- Differences, not five scans of the job for every recipient. Replayed
  -- checkpoints have zero difference and never count a sent email twice.
  update public.announcement_delivery_jobs set
    processed=processed+(next_email<>'pending' and next_push<>'pending')::integer-(r.email_status<>'pending' and r.push_status<>'pending')::integer,
    emailed=emailed+(next_email='sent')::integer-(r.email_status='sent')::integer,
    email_failed=email_failed+(next_email in('failed','needs_review'))::integer-(r.email_status in('failed','needs_review'))::integer,
    email_review=email_review+(next_email='needs_review')::integer-(r.email_status='needs_review')::integer,
    email_skipped=email_skipped+(next_email='skipped')::integer-(r.email_status='skipped')::integer,
    push_failed=push_failed+(next_push='failed')::integer-(r.push_status='failed')::integer,
    lease_until=clock_timestamp()+interval '2 minutes',updated_at=clock_timestamp() where id=j.id;
end $$;

create or replace function public.pause_announcement_delivery(p_job_id bigint,p_lock uuid,p_failed boolean default false,p_delay_ms integer default 0) returns void
language plpgsql security definer set search_path=public as $$
begin
  if p_delay_ms is null or p_delay_ms<0 or p_delay_ms>86400000 then raise exception 'delivery_delay_invalid' using errcode='22023'; end if;
  update public.announcement_delivery_jobs set status='queued',phase=case when prepared_at is null then 'queued' else 'email' end,
    lock_token=null,lease_until=null,attempts=case when p_failed then attempts else 0 end,
    next_attempt_at=clock_timestamp()+make_interval(secs=>p_delay_ms/1000.0),updated_at=clock_timestamp()
    where id=p_job_id and lock_token=p_lock and status='processing' and lease_until>clock_timestamp();
  if not found then raise exception 'delivery_lease_lost'; end if;
end $$;

-- Global per-provider admission covers announcements AND transactional mail.
create table public.provider_request_budgets(provider text primary key,next_available_at timestamptz not null);
alter table public.provider_request_budgets enable row level security;
revoke all on public.provider_request_budgets from public,anon,authenticated;
create or replace function public.reserve_provider_request(p_provider text,p_interval_ms integer default 600,p_max_wait_ms integer default 5000) returns jsonb
language plpgsql security definer set search_path=public as $$
declare next_slot timestamptz; at_time timestamptz:=clock_timestamp(); wait_ms integer;
begin
  if p_provider is distinct from 'resend' or p_interval_ms is null or p_interval_ms<100 or p_interval_ms>60000
    or p_max_wait_ms is null or p_max_wait_ms<0 or p_max_wait_ms>10000 then raise exception 'provider_budget_invalid' using errcode='22023'; end if;
  insert into public.provider_request_budgets values(p_provider,at_time) on conflict(provider) do nothing;
  select next_available_at into next_slot from public.provider_request_budgets where provider=p_provider for update;
  at_time:=clock_timestamp(); next_slot:=greatest(next_slot,at_time);
  wait_ms:=greatest(0,ceil(extract(epoch from next_slot-at_time)*1000));
  if wait_ms>p_max_wait_ms then return jsonb_build_object('allowed',false,'waitMs',wait_ms); end if;
  update public.provider_request_budgets set next_available_at=next_slot+make_interval(secs=>p_interval_ms/1000.0) where provider=p_provider;
  return jsonb_build_object('allowed',true,'waitMs',wait_ms,'slotAt',next_slot);
end $$;
create or replace function public.defer_provider_requests(p_provider text,p_delay_ms integer) returns void
language plpgsql security definer set search_path=public as $$
begin
  if p_provider is distinct from 'resend' or p_delay_ms is null or p_delay_ms<0 or p_delay_ms>86400000 then
    raise exception 'provider_budget_invalid' using errcode='22023'; end if;
  insert into public.provider_request_budgets values(p_provider,clock_timestamp()+make_interval(secs=>p_delay_ms/1000.0))
    on conflict(provider) do update set next_available_at=greatest(provider_request_budgets.next_available_at,excluded.next_available_at);
end $$;
revoke all on function public.pause_announcement_delivery(bigint,uuid,boolean,integer),public.reserve_provider_request(text,integer,integer),
  public.defer_provider_requests(text,integer) from public,anon,authenticated;
grant execute on function public.pause_announcement_delivery(bigint,uuid,boolean,integer),public.reserve_provider_request(text,integer,integer),
  public.defer_provider_requests(text,integer) to service_role;

create or replace function public.prepare_announcement_delivery(p_job_id bigint,p_lock uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype; v_type bigint;
begin
  select * into j from public.announcement_delivery_jobs where id=p_job_id and lock_token=p_lock and status='processing' and lease_until>clock_timestamp() for update;
  if not found then raise exception 'delivery_lease_lost'; end if;
  if j.prepared_at is not null then return to_jsonb(j); end if;
  select id into v_type from public.catalog_notification_types where code='ANN';
  insert into public.announcement_delivery_recipients(job_id,user_id,email,full_name,email_status)
    select j.id,u.id,u.email,u.full_name,
      case when u.email_notifications_enabled=false or coalesce(btrim(u.email),'')='' then 'skipped' else 'pending' end
    from public.users u where u.institution_id=j.institution_id and u.active and u.deleted_at is null and public.portal_permission_for_user(u.id,'announcements.view')
      and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id and r.active and (ur.institution_id is null or ur.institution_id=u.institution_id)
        and (r.institution_id is null or r.institution_id=u.institution_id) and
        case j.payload->>'audience'
          when 'all' then r.code in ('student','parent','teacher','admin','coordinator','director')
          when 'students' then r.code='student' when 'parents' then r.code='parent'
          when 'teachers' then r.code='teacher' when 'staff' then r.code in ('admin','coordinator','director') else false end)
    on conflict(job_id,user_id) do nothing;
  insert into public.notifications(institution_id,user_id,notification_type_id,title,message,data,read,delivery_key)
    select j.institution_id,r.user_id,v_type,j.payload->>'title',j.payload->>'description',
      jsonb_build_object('module','announcements','announcementId',j.announcement_id,'eventId',j.payload->'eventId','deepLink','/announcements'),
      false,'announcement/'||j.announcement_id||'/recipient/'||r.user_id
    from public.announcement_delivery_recipients r where r.job_id=j.id
    on conflict(delivery_key) do nothing;
  update public.announcement_delivery_recipients r set notification_id=n.id from public.notifications n
    where r.job_id=j.id and n.delivery_key='announcement/'||j.announcement_id||'/recipient/'||r.user_id;
  update public.announcement_delivery_jobs set prepared_at=clock_timestamp(),phase='email',total=(select count(*) from public.announcement_delivery_recipients where job_id=j.id),
    email_skipped=(select count(*) from public.announcement_delivery_recipients where job_id=j.id and email_status='skipped'),
    notified=(select count(*) from public.announcement_delivery_recipients where job_id=j.id and notification_id is not null),
    lease_until=clock_timestamp()+interval '2 minutes',updated_at=now() where id=j.id returning * into j;
  return to_jsonb(j);
end $$;


create or replace function public.publish_school_announcement(
  p_institution_id bigint,p_created_by bigint,p_title text,p_content text,
  p_start_at timestamptz,p_audience text,p_request_id uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_event public.calendar_events%rowtype;
  v_announcement public.announcements%rowtype;
  v_job public.announcement_delivery_jobs%rowtype;
  v_key uuid := coalesce(p_request_id,gen_random_uuid());
begin
  if p_institution_id is distinct from public.current_institution_id() or not exists(select 1 from public.users u
    where u.auth_user_id=auth.uid() and u.id=p_created_by and u.institution_id=p_institution_id and public.portal_staff(u.id)) then
    raise exception 'No tienes permiso para publicar anuncios.' using errcode='42501';
  end if;
  if p_title is null or length(btrim(p_title))=0 or length(p_title)>150
    or p_content is null or length(btrim(p_content))=0 or length(p_content)>2000
    or p_start_at is null or p_audience is null or p_audience not in ('all','parents','students','teachers','staff') then
    raise exception 'Datos de anuncio inválidos.' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_institution_id||'/'||p_created_by||'/'||v_key,0));
  select * into v_announcement from public.announcements where institution_id=p_institution_id
    and created_by=p_created_by and publication_key=v_key;
  if found then
    select * into v_event from public.calendar_events where id=v_announcement.event_id;
    if v_announcement.title<>btrim(p_title) or v_announcement.content<>btrim(p_content)
      or v_announcement.audience<>p_audience or v_event.start_at<>p_start_at then
      raise exception 'Esta solicitud ya se utilizó para otro anuncio.' using errcode='22023';
    end if;
    select * into v_job from public.announcement_delivery_jobs where announcement_id=v_announcement.id;
    return jsonb_build_object('event',to_jsonb(v_event),'announcement',to_jsonb(v_announcement),'delivery',to_jsonb(v_job));
  end if;
  insert into public.calendar_events(institution_id,title,description,start_at,audience,type,created_by)
    values(p_institution_id,btrim(p_title),btrim(p_content),p_start_at,p_audience,'announcement',p_created_by) returning * into v_event;
  insert into public.announcements(institution_id,event_id,publication_key,title,content,kind,audience,published,published_at,created_by)
    values(p_institution_id,v_event.id,v_key,btrim(p_title),btrim(p_content),'general',p_audience,true,now(),p_created_by)
    returning * into v_announcement;
  -- Only this authenticated, tenant-checked publication function can enqueue.
  insert into public.announcement_delivery_jobs(announcement_id,institution_id,created_by,payload)
    values(v_announcement.id,p_institution_id,p_created_by,jsonb_build_object(
      'title',btrim(p_title),'description',btrim(p_content),'audience',p_audience,
      'date',p_start_at,'eventId',v_event.id)) returning * into v_job;
  return jsonb_build_object('event',to_jsonb(v_event),'announcement',to_jsonb(v_announcement),'delivery',to_jsonb(v_job));
end $$;

create or replace function public.finish_announcement_delivery(p_job_id bigint,p_lock uuid,p_error text default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype; v_type bigint; v_warning boolean;
begin
  select * into j from public.announcement_delivery_jobs where id=p_job_id and lock_token=p_lock and status='processing' and lease_until>clock_timestamp() for update;
  if not found then raise exception 'delivery_lease_lost'; end if;
  if p_error is null and exists(select 1 from public.announcement_delivery_recipients where job_id=j.id and (email_status='pending' or push_status='pending')) then
    raise exception 'delivery_recipients_pending';
  end if;
  v_warning := p_error is not null or j.email_failed>0 or j.push_failed>0;
  update public.announcement_delivery_jobs set status=case when p_error is not null then 'failed'
    when v_warning then 'completed_with_errors' else 'completed' end,
    phase=case when p_error is not null then 'failed' else 'complete' end,
    last_error=p_error,completed_at=now(),updated_at=now(),lease_until=null,lock_token=null where id=j.id returning * into j;
  select id into v_type from public.catalog_notification_types where code='ANN';
  insert into public.notifications(institution_id,user_id,notification_type_id,title,message,data,read,delivery_key)
    values(j.institution_id,j.created_by,v_type,
      case when v_warning then 'Anuncio publicado con incidencias' else 'Anuncio publicado' end,
      (j.payload->>'title')||case when v_warning then ': el anuncio está guardado, pero el envío necesita atención.'
        else ': publicación y envío completados.' end,
      jsonb_build_object('module','announcements','announcementId',j.announcement_id,'deliveryStatus',j.status,'deepLink','/announcements'),
      false,'announcement/'||j.announcement_id||'/completion/'||j.run_number)
    on conflict(delivery_key) do nothing;
  return to_jsonb(j);
end $$;

create or replace function public.retry_announcement_delivery(p_job_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype;
begin
  select * into j from public.announcement_delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'delivery_job_missing'; end if;
  if j.status not in ('failed','completed_with_errors') then return to_jsonb(j); end if;
  if j.email_review>0 and j.email_failed=j.email_review and j.push_failed=0 and not exists(select 1 from public.announcement_delivery_recipients where job_id=j.id and (email_status='pending' or push_status='pending')) then return to_jsonb(j); end if;
  update public.announcement_delivery_recipients set
    email_status=case when email_status='failed' then 'pending' else email_status end,
    push_status=case when push_status='failed' then 'pending' else push_status end,last_error=null where job_id=j.id;
  update public.announcement_delivery_jobs set status='queued',phase='queued',last_error=null,
    processed=(select count(*) from public.announcement_delivery_recipients where job_id=j.id and email_status<>'pending' and push_status<>'pending'),
    email_failed=email_review,push_failed=0,
    completed_at=null,attempts=0,run_number=run_number+1,next_attempt_at=now(),updated_at=now() where id=j.id returning * into j;
  return to_jsonb(j);
end $$;


drop policy if exists announcement_jobs_read on public.announcement_delivery_jobs;
create policy announcement_jobs_read on public.announcement_delivery_jobs for select to authenticated using(
  institution_id=(select public.current_institution_id()) and ((select public.class_admin_actor()) or created_by=(select id from public.users where auth_user_id=(select auth.uid()))));

create or replace function public.announcement_recipient_allowed(p_institution_id bigint,p_audience text,p_user_id bigint) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.users u join public.institutions i on i.id=u.institution_id and i.active and i.deleted_at is null
    where u.id=p_user_id and u.institution_id=p_institution_id and u.active and u.deleted_at is null
      and public.portal_permission_for_user(u.id,'announcements.view') and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id and r.active
        where ur.user_id=u.id and (ur.institution_id is null or ur.institution_id=u.institution_id) and (r.institution_id is null or r.institution_id=u.institution_id)
          and case p_audience when 'all' then r.code in('student','parent','teacher','admin','coordinator','director')
            when 'students' then r.code='student' when 'parents' then r.code='parent' when 'teachers' then r.code='teacher'
            when 'staff' then r.code in('admin','coordinator','director') else false end))
$$;
revoke all on function public.announcement_recipient_allowed(bigint,text,bigint) from public,anon,authenticated;

create or replace function public.announcement_pending_page(p_job_id bigint,p_lock uuid,p_limit integer default 50) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype; result jsonb;
begin
  if p_limit is null or p_limit<1 or p_limit>100 then raise exception 'delivery_page_invalid' using errcode='22023'; end if;
  select * into j from public.announcement_delivery_jobs where id=p_job_id and lock_token=p_lock and status='processing' and lease_until>clock_timestamp();
  if not found then raise exception 'delivery_lease_lost'; end if;
  select coalesce(jsonb_agg(to_jsonb(page) order by user_id),'[]'::jsonb) into result from (
    select r.*,public.announcement_recipient_allowed(j.institution_id,j.payload->>'audience',r.user_id) eligible,
      jsonb_build_object('active',u.active,'deleted_at',u.deleted_at,'email_notifications_enabled',u.email_notifications_enabled) users
      from public.announcement_delivery_recipients r join public.users u on u.id=r.user_id
      where r.job_id=j.id and (r.email_status='pending' or r.push_status='pending') order by (r.email_status='pending') desc,r.user_id limit p_limit
  ) page;
  return result;
end $$;

create or replace function public.begin_announcement_email(p_job_id bigint,p_lock uuid,p_user_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype; r public.announcement_delivery_recipients%rowtype; u public.users%rowtype;
begin
  select * into j from public.announcement_delivery_jobs where id=p_job_id and lock_token=p_lock and status='processing' and lease_until>clock_timestamp() for update;
  if not found then raise exception 'delivery_lease_lost'; end if;
  select * into r from public.announcement_delivery_recipients where job_id=j.id and user_id=p_user_id for update;
  if not found then return jsonb_build_object('send',false,'status','skipped'); end if;
  if r.email_status<>'pending' then return jsonb_build_object('send',false,'status',r.email_status); end if;
  select * into u from public.users where id=r.user_id;
  if not public.announcement_recipient_allowed(j.institution_id,j.payload->>'audience',r.user_id)
    or u.email_notifications_enabled=false or nullif(trim(u.email),'') is null then
    perform public.record_announcement_delivery(j.id,p_lock,r.user_id,'skipped',r.push_status,null,null);
    return jsonb_build_object('send',false,'status','skipped');
  end if;
  -- The provider retains idempotency keys for 24h. An ambiguous checkpoint
  -- outside our 23h retry window requires reconciliation, not a blind resend.
  if r.email_first_attempt_at is not null and (r.email_first_attempt_at<clock_timestamp()-interval '23 hours' or r.email is distinct from u.email) then
    perform public.record_announcement_delivery(j.id,p_lock,r.user_id,'needs_review',r.push_status,null,'El envío requiere revisión antes de volver a enviar el correo.');
    return jsonb_build_object('send',false,'status','needs_review');
  end if;
  if r.email_first_attempt_at is null then
    update public.announcement_delivery_recipients set email=u.email,full_name=u.full_name,email_first_attempt_at=clock_timestamp()
      where job_id=j.id and user_id=r.user_id returning * into r;
  end if;
  update public.announcement_delivery_jobs set lease_until=clock_timestamp()+interval '2 minutes' where id=j.id;
  return jsonb_build_object('send',true,'email',r.email,'fullName',r.full_name,'status','pending',
    'validUntil',r.email_first_attempt_at+interval '23 hours',
    'idempotencyKey','announcement/'||j.announcement_id||'/recipient/'||r.user_id||case when r.email_key_suffix is null then '' else '/review/'||r.email_key_suffix end);
end $$;

create or replace function public.announcement_recipient_removed() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  -- Account erasure removes its recipient/PII. Keep counters consistent with
  -- the remaining audience, including completed jobs and later retries.
  update public.announcement_delivery_jobs set total=greatest(0,total-1),notified=greatest(0,notified-1),
    processed=greatest(0,processed-(old.email_status<>'pending' and old.push_status<>'pending')::integer),
    emailed=greatest(0,emailed-(old.email_status='sent')::integer),
    email_failed=greatest(0,email_failed-(old.email_status in('failed','needs_review'))::integer),
    email_review=greatest(0,email_review-(old.email_status='needs_review')::integer),
    email_skipped=greatest(0,email_skipped-(old.email_status='skipped')::integer),
    push_failed=greatest(0,push_failed-(old.push_status='failed')::integer),updated_at=clock_timestamp()
    where id=old.job_id and prepared_at is not null;
  return null;
end $$;
create trigger announcement_recipient_remove after delete on public.announcement_delivery_recipients
  for each row execute function public.announcement_recipient_removed();
revoke all on function public.announcement_pending_page(bigint,uuid,integer),public.begin_announcement_email(bigint,uuid,bigint),
  public.announcement_recipient_removed() from public,anon,authenticated;
grant execute on function public.announcement_pending_page(bigint,uuid,integer),public.begin_announcement_email(bigint,uuid,bigint) to service_role;

create or replace function public.heartbeat_announcement_delivery(p_job_id bigint,p_lock uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  update public.announcement_delivery_jobs set lease_until=clock_timestamp()+interval '2 minutes'
    where id=p_job_id and lock_token=p_lock and status='processing' and lease_until>clock_timestamp();
  if not found then raise exception 'delivery_lease_lost'; end if;
end $$;
revoke all on function public.heartbeat_announcement_delivery(bigint,uuid) from public,anon,authenticated;
grant execute on function public.heartbeat_announcement_delivery(bigint,uuid) to service_role;
create index announcement_recipients_pending on public.announcement_delivery_recipients(job_id,user_id) where email_status='pending' or push_status='pending';

-- Operator-only recovery after checking provider records. There is deliberately
-- no browser endpoint that can assert an ambiguous email was never sent.
create or replace function public.resolve_announcement_email_review(p_job_id bigint,p_user_id bigint,p_outcome text,p_evidence text,p_email_id text default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j public.announcement_delivery_jobs%rowtype; r public.announcement_delivery_recipients%rowtype; next_status text;
begin
  if p_outcome is null or p_outcome not in('confirmed_sent','confirmed_not_sent') or nullif(trim(p_evidence),'') is null or length(p_evidence)>1000
    or length(p_email_id)>150 or (p_outcome='confirmed_sent' and nullif(trim(p_email_id),'') is null)
    or (p_outcome='confirmed_not_sent' and p_email_id is not null) then raise exception 'delivery_review_invalid' using errcode='22023'; end if;
  select * into j from public.announcement_delivery_jobs where id=p_job_id for update;
  if not found then raise exception 'delivery_job_missing'; end if;
  if j.status='processing' and j.lease_until>clock_timestamp() then raise exception 'delivery_job_busy'; end if;
  select * into r from public.announcement_delivery_recipients where job_id=j.id and user_id=p_user_id for update;
  if not found or r.email_status<>'needs_review' then raise exception 'delivery_review_not_pending'; end if;
  next_status:=case when p_outcome='confirmed_sent' then 'sent' else 'pending' end;
  update public.announcement_delivery_recipients set email_status=next_status,email_id=case when next_status='sent' then p_email_id else null end,
    email_first_attempt_at=case when next_status='pending' then null else email_first_attempt_at end,
    email_key_suffix=case when next_status='pending' then gen_random_uuid() else email_key_suffix end,last_error=null
    where job_id=j.id and user_id=p_user_id;
  if next_status='sent' then
    insert into public.notification_deliveries(notification_id,channel_id,destination,status,provider,external_ref,sent_at)
      values(r.notification_id,(select id from public.catalog_notification_channels where code='EMAIL'),r.email,'sent','resend',p_email_id,clock_timestamp());
  end if;
  update public.announcement_delivery_jobs set email_review=email_review-1,email_failed=email_failed-1,
    emailed=emailed+(next_status='sent')::integer,
    processed=processed-case when next_status='pending' and r.push_status<>'pending' then 1 else 0 end,
    status='queued',phase='email',attempts=0,run_number=run_number+1,next_attempt_at=clock_timestamp(),updated_at=clock_timestamp(),
    completed_at=null,lock_token=null,lease_until=null,last_error=null where id=j.id returning * into j;
  insert into public.audit_log(institution_id,table_name,record_id,action,data_before,data_after)
    values(j.institution_id,'announcement_delivery_recipients',j.id::text,'RECONCILE_EMAIL',jsonb_build_object('userId',p_user_id,'emailStatus',r.email_status),
      jsonb_build_object('emailStatus',next_status,'providerId',p_email_id,'evidence',p_evidence));
  return to_jsonb(j);
end $$;
revoke all on function public.resolve_announcement_email_review(bigint,bigint,text,text,text) from public,anon,authenticated;
grant execute on function public.resolve_announcement_email_review(bigint,bigint,text,text,text) to service_role;

create or replace function public.announcement_job_stamp() returns trigger
language plpgsql set search_path=public as $$
begin
  new.updated_at:=greatest(clock_timestamp(),old.updated_at+interval '1 microsecond');
  return new;
end $$;
create trigger announcement_job_updated before update on public.announcement_delivery_jobs
  for each row execute function public.announcement_job_stamp();
revoke all on function public.announcement_job_stamp() from public,anon,authenticated;
notify pgrst,'reload schema';

create index announcement_recipients_email_priority on public.announcement_delivery_recipients(job_id,(email_status='pending') desc,user_id) where email_status='pending' or push_status='pending';
-- END 0045_announcement_delivery_scaling.sql


-- BEGIN 0046_announcement_feed.sql
-- SHA256 69b67c9406da53300fed5d64606682d2e3cff602e62e79d9794facaa748532ba
create or replace function public.current_user_id() returns bigint
language sql stable security definer set search_path=public as $$
  select id from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id()
$$;
create or replace function public.announcement_group_ids() returns bigint[]
language sql stable security definer set search_path=public as $$
  with actor as materialized(select u.*,public.current_roles() codes from public.users u where u.id=public.current_user_id()),
  visible_groups as (
    select e.group_id from actor u join public.students s on s.person_id=u.person_id and s.institution_id=u.institution_id
      join public.enrollments e on e.student_id=s.id and e.institution_id=u.institution_id where 'student'=any(u.codes)
    union
    select e.group_id from actor u join public.parents p on p.person_id=u.person_id and p.institution_id=u.institution_id
      join public.parent_students ps on ps.parent_id=p.id join public.enrollments e on e.student_id=ps.student_id and e.institution_id=u.institution_id where 'parent'=any(u.codes)
    union
    select c.group_id from actor u join public.teachers t on t.person_id=u.person_id and t.institution_id=u.institution_id and t.active
      join public.classes c on c.institution_id=u.institution_id and c.active and c.teacher_id=t.id where 'teacher'=any(u.codes)
    union
    select c.group_id from actor u join public.class_collaborators cc on cc.teacher_user_id=u.id and cc.institution_id=u.institution_id and cc.status='active'
      join public.classes c on c.id=cc.class_id and c.active where 'teacher'=any(u.codes) and 'class.view'=any(cc.permissions)
  ) select coalesce(array_agg(distinct group_id) filter(where group_id is not null),array[]::bigint[]) from visible_groups
$$;
revoke all on function public.current_user_id(),public.announcement_group_ids() from public,anon;
grant execute on function public.current_user_id(),public.announcement_group_ids() to authenticated;
create policy announcement_audience_read on public.announcements as restrictive for select to authenticated using(
  (select public.class_admin_actor()) or created_by=(select public.current_user_id()) or
  published and (group_id is null or group_id in(select unnest(public.announcement_group_ids()))) and (
    audience='all' or audience in('student','students') and (select public.has_role('student'))
    or audience in('parent','parents') and (select public.has_role('parent'))
    or audience in('teacher','teachers') and (select public.has_role('teacher'))
    or group_id is not null and audience in('group','groups')));
create policy calendar_announcement_audience on public.calendar_events as restrictive for select to authenticated using(
  type is distinct from 'announcement' or (select public.class_admin_actor()) or created_by=(select public.current_user_id())
    or exists(select 1 from public.announcements a where a.event_id=calendar_events.id));
-- Publication must include its durable outbox transaction; the Data API cannot
-- create/alter only one half of a publication. The checked RPC runs as owner.
revoke insert,update,delete on public.announcements from authenticated,anon;
create policy calendar_staff_insert on public.calendar_events as restrictive for insert to authenticated with check(
  type is distinct from 'announcement' and created_by=(select public.current_user_id()) and (select public.portal_staff(public.current_user_id())));
create policy calendar_staff_update on public.calendar_events as restrictive for update to authenticated
  using(type is distinct from 'announcement' and ((select public.class_admin_actor()) or created_by=(select public.current_user_id()) and (select public.portal_staff(public.current_user_id()))))
  with check(type is distinct from 'announcement' and ((select public.class_admin_actor()) or created_by=(select public.current_user_id()) and (select public.portal_staff(public.current_user_id()))));
create policy calendar_staff_delete on public.calendar_events as restrictive for delete to authenticated
  using(type is distinct from 'announcement' and ((select public.class_admin_actor()) or created_by=(select public.current_user_id()) and (select public.portal_staff(public.current_user_id()))));
create index announcements_published_page on public.announcements(institution_id,id desc) where published;

create or replace function public.announcement_feed(p_before_id bigint default null,p_limit integer default 50) returns jsonb
language plpgsql stable set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if not public.portal_can('announcements.view') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if p_limit is null or p_limit<1 or p_limit>100 or p_before_id<1 then raise exception 'Paginación inválida.' using errcode='22023'; end if;
  with candidates as materialized(select a.* from public.announcements a where a.institution_id=(select public.current_institution_id())
      and a.published and (p_before_id is null or a.id<p_before_id) order by a.id desc limit p_limit+1),
    page as materialized(select * from candidates order by id desc limit p_limit)
  select jsonb_build_object('announcements',coalesce((select jsonb_agg(jsonb_build_object(
    'id',a.id::text,'title',a.title,'content',a.content,'audience',a.audience,'group_id',a.group_id::text,'published_at',a.published_at,
    'created_at',a.created_at,'created_by',a.created_by::text,'publication_key',a.publication_key,
    'calendar_events',case when event.id is null then null else jsonb_build_object('start_at',event.start_at) end,
    'announcement_delivery_jobs',case when job.id is null then null else jsonb_build_object('status',job.status,'phase',job.phase,'total',job.total,
      'processed',job.processed,'notified',job.notified,'emailed',job.emailed,'email_failed',job.email_failed,'email_review',job.email_review,
      'email_skipped',job.email_skipped,'push_failed',job.push_failed,'last_error',job.last_error,'completed_at',job.completed_at,'updated_at',job.updated_at) end) order by a.id desc)
      from page a left join public.calendar_events event on event.id=a.event_id left join public.announcement_delivery_jobs job on job.announcement_id=a.id),'[]'::jsonb),
    'hasMore',(select count(*) from candidates)>p_limit,
    'nextBeforeId',case when (select count(*) from candidates)>p_limit then (select min(id)::text from page) else null end) into result;
  return result;
end $$;
create or replace function public.announcement_delivery_state(p_ids bigint[]) returns jsonb
language plpgsql stable set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if not public.portal_can('announcements.view') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if p_ids is null or cardinality(p_ids)>100 or exists(select 1 from unnest(p_ids) id where id is null or id<1) then raise exception 'IDs inválidos.' using errcode='22023'; end if;
  select jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_object('announcementId',job.announcement_id::text,'delivery',jsonb_build_object(
    'status',job.status,'phase',job.phase,'total',job.total,'processed',job.processed,'notified',job.notified,'emailed',job.emailed,'email_failed',job.email_failed,
    'email_review',job.email_review,'email_skipped',job.email_skipped,'push_failed',job.push_failed,'last_error',job.last_error,'completed_at',job.completed_at,'updated_at',job.updated_at))),'[]'::jsonb)) into result
    from public.announcement_delivery_jobs job where job.institution_id=(select public.current_institution_id()) and job.announcement_id=any(p_ids);
  return result;
end $$;
revoke all on function public.announcement_feed(bigint,integer),public.announcement_delivery_state(bigint[]) from public,anon;
grant execute on function public.announcement_feed(bigint,integer),public.announcement_delivery_state(bigint[]) to authenticated;
do $$ declare tbl text; begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach tbl in array array['announcements','announcement_delivery_jobs'] loop
      if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=tbl) then
        execute format('alter publication supabase_realtime add table public.%I',tbl);
      end if;
    end loop;
  end if;
end $$;
notify pgrst,'reload schema';
-- END 0046_announcement_feed.sql


-- BEGIN 0047_attendance_sync.sql
-- SHA256 0f90158174b16ebceb34299ee58eb4960b81d966272552cbd356321c36590cc3
-- Versioned attendance writes, durable idempotency and a committed change cursor.
alter table public.attendances add column version integer not null default 1;
alter table public.attendances add column class_id bigint;
update public.attendances a set class_id=s.class_id from public.class_sessions s where s.id=a.class_session_id;
alter table public.change_log add column class_id bigint;
alter table public.change_log add column row_data jsonb;
create index attendance_changes_cursor on public.change_log(institution_id,updated_at,id) where table_name='attendances';
create table public.attendance_sync_receipts(
  institution_id bigint not null references public.institutions(id) on delete cascade,
  user_id bigint not null references public.users(id) on delete cascade,
  operation_id uuid not null,
  request jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(institution_id,user_id,operation_id)
);
create index attendance_sync_receipts_created on public.attendance_sync_receipts(created_at);
alter table public.attendance_sync_receipts enable row level security;
revoke all on public.attendance_sync_receipts from public,anon,authenticated;

-- The tenant lock is acquired before timestamps are allocated. Pull takes the
-- same lock: a late commit cannot appear behind an already returned cursor.
create function public.attendance_stamp() returns trigger language plpgsql security definer set search_path=public as $$
declare session public.class_sessions%rowtype; inst bigint;
begin
  inst:=case when tg_op='DELETE' then old.institution_id else new.institution_id end;
  perform pg_advisory_xact_lock(hashtextextended('attendance-sync/'||inst,0));
  if tg_op='DELETE' then return old; end if;
  select * into session from public.class_sessions where id=new.class_session_id;
  if session.id is null or session.institution_id is distinct from new.institution_id then
    raise exception 'Sesión inválida.' using errcode='22023'; end if;
  new.class_id:=session.class_id;
  new.version:=case when tg_op='INSERT' then 1 else old.version+1 end;
  new.updated_at:=clock_timestamp();
  return new;
end $$;
create trigger attendance_stamp before insert or update or delete on public.attendances for each row execute function public.attendance_stamp();
create function public.attendance_log() returns trigger language plpgsql security definer set search_path=public as $$
declare row_value public.attendances%rowtype;
begin
  if tg_op='DELETE' then row_value:=old; else row_value:=new; end if;
  if not exists(select 1 from public.institutions where id=row_value.institution_id) then return null; end if;
  insert into public.change_log(institution_id,table_name,record_id,record_uuid,version,operation,updated_at,class_id,row_data)
  values(row_value.institution_id,'attendances',row_value.id,row_value.uuid,row_value.version,lower(tg_op),greatest(clock_timestamp(),coalesce((select max(updated_at)+interval '1 microsecond' from public.change_log where institution_id=row_value.institution_id and table_name='attendances'),clock_timestamp())),row_value.class_id,
    case when tg_op='DELETE' then null else jsonb_build_object('id',row_value.id::text,'uuid',row_value.uuid,'classId',row_value.class_id::text,
      'classSessionId',row_value.class_session_id::text,'studentId',row_value.student_id::text,'statusId',row_value.attendance_status_id,
      'notes',row_value.notes,'recordedAt',row_value.recorded_at,'version',row_value.version) end);
  return null;
end $$;
create trigger attendance_log after insert or update or delete on public.attendances for each row execute function public.attendance_log();
revoke all on function public.attendance_stamp(),public.attendance_log() from public,anon,authenticated;
revoke insert,update,delete on public.attendances from anon,authenticated;

create function public.sync_attendance_batch(p_sessions jsonb default '[]',p_marks jsonb default '[]') returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); item jsonb; cls public.classes%rowtype;
  session_id bigint; session_date date; current_row public.attendances%rowtype; receipt public.attendance_sync_receipts%rowtype;
  operation uuid; student bigint; status integer; expected integer; stamp timestamptz; note text;
  result jsonb; records jsonb:='[]'; sessions jsonb:='[]'; request_value jsonb;
begin
  if not public.has_role('teacher') or not exists(select 1 from public.teachers t join public.users u on u.person_id=t.person_id and u.institution_id=t.institution_id
    where u.id=actor and t.active) then raise exception 'Solo docentes pueden sincronizar asistencia.' using errcode='42501'; end if;
  if p_sessions is null or p_marks is null or jsonb_typeof(p_sessions)<>'array' or jsonb_typeof(p_marks)<>'array'
    or jsonb_array_length(p_sessions)>100 or jsonb_array_length(p_marks)>100 then raise exception 'Lote inválido (máximo 100 sesiones y 100 marcas).' using errcode='22023'; end if;
  if (select count(*)<>count(distinct value->>'operationId') from jsonb_array_elements(p_marks)) or exists(
    select 1 from jsonb_array_elements(p_marks) group by value->>'classId',value->>'date',value->>'studentId' having count(*)>1) then
    raise exception 'El lote contiene marcas duplicadas.' using errcode='22023'; end if;
  -- Serialize before session and row locks, including trigger-generated changes.
  perform pg_advisory_xact_lock(hashtextextended('attendance-sync/'||inst,0));
  for item in select jsonb_build_object('classId',value->>'classId','date',value->>'date') from (
    select value from jsonb_array_elements(p_sessions) union all select value from jsonb_array_elements(p_marks)) inputs
    group by value->>'classId',value->>'date' order by (value->>'classId')::bigint,value->>'date'
  loop
    if coalesce(item->>'date','')!~'^\d{4}-\d{2}-\d{2}$' then raise exception 'Fecha de clase inválida.' using errcode='22023'; end if;
    session_date:=(item->>'date')::date;
    if session_date>(clock_timestamp() at time zone coalesce((select timezone from public.institutions where id=inst),'America/Managua'))::date+1 then
      raise exception 'Fecha de clase futura.' using errcode='22023'; end if;
    session_id:=public.ensure_collaborative_class_session((item->>'classId')::bigint,session_date);
    sessions:=sessions||jsonb_build_array(jsonb_build_object('classId',item->>'classId','date',session_date,'id',session_id::text));
  end loop;
  for item in select value from jsonb_array_elements(p_marks) order by (value->>'classId')::bigint,value->>'date',(value->>'studentId')::bigint
  loop
    operation:=(item->>'operationId')::uuid;
    if operation is null or (item->>'uuid')::uuid is null then raise exception 'Clave de operación requerida.' using errcode='22023'; end if;
    select * into receipt from public.attendance_sync_receipts where institution_id=inst and user_id=actor and operation_id=operation;
    if found then
      if receipt.request<>item then raise exception 'La clave de operación ya tiene otro contenido.' using errcode='23505'; end if;
      records:=records||jsonb_build_array(receipt.result); continue;
    end if;
    select * into cls from public.classes where id=(item->>'classId')::bigint and institution_id=inst;
    if cls.id is null or not public.class_permission(cls.id,'attendance.write') then raise exception 'Clase no autorizada.' using errcode='42501'; end if;
    student:=(item->>'studentId')::bigint; status:=(item->>'statusId')::integer;
    expected:=(item->>'expectedVersion')::integer; stamp:=(item->>'recordedAt')::timestamptz; note:=nullif(item->>'notes','');
    if expected is null or expected<0 or stamp is null or not isfinite(stamp) or length(coalesce(note,''))>500 or not exists(select 1 from public.catalog_attendance_statuses where id=status and active) then
      raise exception 'Marcación inválida.' using errcode='22023'; end if;
    if not exists(select 1 from public.enrollments e join public.students s on s.id=e.student_id and s.institution_id=inst and s.active
      join public.catalog_enrollment_statuses es on es.id=e.enrollment_status_id and es.code='ACT'
      where e.institution_id=inst and e.student_id=student and e.group_id=cls.group_id and e.academic_year_id=cls.academic_year_id) then
      raise exception 'El estudiante no pertenece a la clase.' using errcode='42501'; end if;
    select id into session_id from public.class_sessions where class_id=cls.id and institution_id=inst and date=(item->>'date')::date order by id limit 1;
    select * into current_row from public.attendances where class_session_id=session_id and student_id=student for update;
    if coalesce(current_row.version,0)<>expected then
      result:=jsonb_build_object('operationId',operation,'uuid',item->>'uuid','status','conflict','id',current_row.id::text,'version',coalesce(current_row.version,0),
        'statusId',current_row.attendance_status_id,'notes',current_row.notes,'classSessionId',session_id::text);
    else
      if current_row.id is null then
        insert into public.attendances(uuid,institution_id,class_session_id,student_id,attendance_status_id,recorded_at,notes,recorded_by,source)
          values((item->>'uuid')::uuid,inst,session_id,student,status,stamp,note,actor,'sync') returning * into current_row;
      else
        update public.attendances set attendance_status_id=status,recorded_at=stamp,notes=note,recorded_by=actor,source='sync'
          where id=current_row.id returning * into current_row;
      end if;
      result:=jsonb_build_object('operationId',operation,'uuid',item->>'uuid','status','applied','id',current_row.id::text,'version',current_row.version,'classSessionId',session_id::text);
    end if;
    insert into public.attendance_sync_receipts(institution_id,user_id,operation_id,request,result) values(inst,actor,operation,item,result);
    records:=records||jsonb_build_array(result);
  end loop;
  return jsonb_build_object('sessions',sessions,'records',records);
exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format or numeric_value_out_of_range then
  raise exception 'Datos de sincronización inválidos.' using errcode='22023';
end $$;
revoke all on function public.sync_attendance_batch(jsonb,jsonb) from public,anon;
grant execute on function public.sync_attendance_batch(jsonb,jsonb) to authenticated;

create function public.attendance_changes(p_after_at timestamptz default '1970-01-01',p_after_id bigint default 0,p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); result jsonb;
begin
  if not public.has_role('teacher') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  if p_limit is null or p_limit<1 or p_limit>500 or p_after_at is null or not isfinite(p_after_at) or p_after_id is null or p_after_id<0 then
    raise exception 'Cursor inválido.' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('attendance-sync/'||inst,0));
  with allowed as materialized(select id from public.classes where institution_id=inst and public.class_permission(id,'attendance.write')),
  candidates as materialized(select l.* from public.change_log l where l.institution_id=inst and l.table_name='attendances'
    and l.class_id in(select id from allowed) and (l.updated_at,l.id)>(p_after_at,p_after_id) order by l.updated_at,l.id limit p_limit+1),
  page as materialized(select * from candidates order by updated_at,id limit p_limit)
  select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',id::text,'tableName',table_name,'recordId',record_id::text,
      'recordUuid',record_uuid,'version',version,'operation',operation,'updatedAt',updated_at,'data',row_data) order by updated_at,id) from page),'[]'::jsonb),
    'hasMore',(select count(*) from candidates)>p_limit,
    'cursor',coalesce((select jsonb_build_object('updatedAt',updated_at,'id',id::text) from page order by updated_at desc,id desc limit 1),
      jsonb_build_object('updatedAt',p_after_at,'id',p_after_id::text))) into result;
  return result;
end $$;
revoke all on function public.attendance_changes(timestamptz,bigint,integer) from public,anon;
grant execute on function public.attendance_changes(timestamptz,bigint,integer) to authenticated;
notify pgrst,'reload schema';
-- END 0047_attendance_sync.sql


-- BEGIN 0048_atomic_admin_writes.sql
-- SHA256 f6ff5faed987ac3e71e240c3db01414c4b23b60dcd5293685ac3e9f292cc1d62
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
      values(p_inst,p_id,group_id,year_id,(select id from public.catalog_enrollment_statuses where code='ACT' and active order by id limit 1),current_date)
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
-- END 0048_atomic_admin_writes.sql


-- BEGIN 0049_atomic_documents_and_charges.sql
-- SHA256 328ce6086d9d1cbfc830de2d9ab3e16b4269d41297be435cd8378215c62b912d
create table public.api_write_receipts(
 institution_id bigint not null references public.institutions(id) on delete cascade,
 user_id bigint not null references public.users(id) on delete cascade,
 idempotency_key uuid not null, operation text not null, request_hash bytea not null,
 response jsonb, created_at timestamptz not null default clock_timestamp(),
 primary key(institution_id,user_id,idempotency_key)
);
alter table public.api_write_receipts enable row level security;
revoke all on public.api_write_receipts from public,anon,authenticated;
create function public.write_receipt_begin(p_inst bigint,p_actor bigint,p_key uuid,p_operation text,p_request jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare receipt public.api_write_receipts%rowtype; fingerprint bytea:=sha256(convert_to(p_request::text,'UTF8'));
begin
 if p_key is null then raise exception 'Clave requerida.' using errcode='22023'; end if;
 insert into public.api_write_receipts(institution_id,user_id,idempotency_key,operation,request_hash)
 values(p_inst,p_actor,p_key,p_operation,fingerprint) on conflict do nothing;
 select * into receipt from public.api_write_receipts where institution_id=p_inst and user_id=p_actor and idempotency_key=p_key for update;
 if receipt.operation<>p_operation or receipt.request_hash<>fingerprint then raise exception 'La clave ya tiene otro contenido.' using errcode='23505'; end if;
 return receipt.response;
end $$;
create function public.write_receipt_finish(p_inst bigint,p_actor bigint,p_key uuid,p_response jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
 update public.api_write_receipts set response=p_response where institution_id=p_inst and user_id=p_actor and idempotency_key=p_key;
 return p_response;
end $$;
revoke all on function public.write_receipt_begin(bigint,bigint,uuid,text,jsonb),public.write_receipt_finish(bigint,bigint,uuid,jsonb) from public,anon,authenticated;

create function public.grading_scale_write(p_id bigint,p_header jsonb,p_ranges jsonb,p_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); header public.grading_scales%rowtype;
 result jsonb; row_range public.grading_scale_ranges%rowtype; value jsonb;
begin
 if not public.administrative_permission(inst,'settings.edit') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
 if jsonb_typeof(p_header) is distinct from 'object' or jsonb_typeof(p_ranges) is distinct from 'array' or jsonb_array_length(p_ranges)>100 then raise exception 'Escala inválida.' using errcode='22023'; end if;
 header:=jsonb_populate_record(null::public.grading_scales,p_header);
 if nullif(trim(header.name),'') is null or header.scale_type not in('numeric','qualitative','letters') or header.scale_type is null
  or header.min_value is null or header.max_value is null or header.pass_value is null or header.decimals is null
  or header.min_value::text in('NaN','Infinity','-Infinity') or header.max_value::text in('NaN','Infinity','-Infinity') or header.pass_value::text in('NaN','Infinity','-Infinity')
  or header.min_value>=header.max_value or header.pass_value<header.min_value or header.pass_value>header.max_value or header.decimals not between 0 and 4 then raise exception 'Escala inválida.' using errcode='22023'; end if;
 for value in select * from jsonb_array_elements(p_ranges) loop
  row_range:=jsonb_populate_record(null::public.grading_scale_ranges,value);
  if nullif(trim(row_range.label),'') is null or row_range.range_min is null or row_range.range_max is null
   or row_range.range_min::text in('NaN','Infinity','-Infinity') or row_range.range_max::text in('NaN','Infinity','-Infinity')
   or row_range.range_min>row_range.range_max or row_range.range_min<header.min_value or row_range.range_max>header.max_value
   or row_range.color is not null and row_range.color!~'^#[0-9A-Fa-f]{6}$' then raise exception 'Rango de escala inválido.' using errcode='22023'; end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_ranges) with ordinality x(value,n)
  join jsonb_array_elements(p_ranges) with ordinality y(value,n) on y.n>x.n
  where numrange((x.value->>'range_min')::numeric,(x.value->>'range_max')::numeric,'[]') && numrange((y.value->>'range_min')::numeric,(y.value->>'range_max')::numeric,'[]')) then
  raise exception 'Los rangos no pueden superponerse.' using errcode='22023'; end if;
 result:=public.write_receipt_begin(inst,actor,p_key,'grading_scale_write',jsonb_build_object('id',p_id,'header',p_header,'ranges',p_ranges));
 if result is not null then return result; end if;
 if p_id is null then
  insert into public.grading_scales(institution_id,name,scale_type,min_value,max_value,pass_value,decimals,active)
   values(inst,header.name,header.scale_type,header.min_value,header.max_value,header.pass_value,header.decimals,true) returning * into header;
 else
  update public.grading_scales set name=header.name,scale_type=header.scale_type,min_value=header.min_value,max_value=header.max_value,pass_value=header.pass_value,decimals=header.decimals,active=true
   where id=p_id and institution_id=inst returning * into header;
  if not found then raise exception 'Escala no encontrada.' using errcode='P0002'; end if;
 end if;
 delete from public.grading_scale_ranges where scale_id=header.id;
 insert into public.grading_scale_ranges(scale_id,label,range_min,range_max,description,passed,color)
  select header.id,r.label,r.range_min,r.range_max,r.description,coalesce(r.passed,true),r.color from jsonb_populate_recordset(null::public.grading_scale_ranges,p_ranges) r;
 result:=to_jsonb(header)||jsonb_build_object('grading_scale_ranges',coalesce((select jsonb_agg(to_jsonb(r.*) order by r.range_min,r.id) from public.grading_scale_ranges r where r.scale_id=header.id),'[]'::jsonb));
 return public.write_receipt_finish(inst,actor,p_key,result);
end $$;
revoke all on function public.grading_scale_write(bigint,jsonb,jsonb,uuid) from public,anon;
grant execute on function public.grading_scale_write(bigint,jsonb,jsonb,uuid) to authenticated;

create function public.report_card_generate(p_student bigint,p_period bigint,p_notes text,p_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); year_id bigint; enrollment bigint;
 wide boolean; grade_rows jsonb; average numeric; card public.report_cards%rowtype; result jsonb;
begin
 select academic_year_id into year_id from public.academic_periods where id=p_period and institution_id=inst;
 if year_id is null or length(coalesce(p_notes,''))>2000 then raise exception 'Periodo o notas inválidos.' using errcode='22023'; end if;
 select id into enrollment from public.enrollments where student_id=p_student and institution_id=inst and academic_year_id=year_id order by id desc limit 1;
 if not exists(select 1 from public.students where id=p_student and institution_id=inst) then raise exception 'Estudiante fuera de la institución.' using errcode='42501'; end if;
 if enrollment is null then raise exception 'El estudiante no tiene matrícula en ese año.' using errcode='22023'; end if;
 wide:=public.administrative_permission(inst,'reports.generate') and public.administrative_permission(inst,'reports.view');
 if not wide and not exists(select 1 from public.enrollments e join public.classes c on c.group_id=e.group_id and c.academic_year_id=e.academic_year_id and c.institution_id=e.institution_id
   where e.id=enrollment and public.teacher_class_permission(c.id,'students.view')) then raise exception 'No puedes generar ese boletín.' using errcode='42501'; end if;
 if not public.portal_can('reports.view') or not public.portal_can_view_grades(p_student,p_period) then raise exception 'Boletín restringido.' using errcode='42501'; end if;
 result:=public.write_receipt_begin(inst,actor,p_key,'report_card_generate',jsonb_build_object('student',p_student,'period',p_period,'notes',p_notes));
 if result is not null then return result; end if;
 -- Snapshot the authorized grade rows once: header and lines cannot disagree
 -- if another teacher saves grades while this transaction is running.
 select coalesce(jsonb_agg(jsonb_build_object('subject_id',coalesce(g.subject_id,c.subject_id),'final_score',g.final_score,
  'qualitative_label',g.qualitative_label,'passed',g.passed,'notes',g.notes,'teacher_id',c.teacher_id) order by g.subject_id,g.id),'[]'::jsonb)
 into grade_rows from public.period_grades g left join public.classes c on c.id=g.class_id and c.institution_id=inst
 where g.institution_id=inst and g.student_id=p_student and g.academic_period_id=p_period and (wide or public.teacher_class_permission(g.class_id,'class.view'));
 select round(avg((value->>'final_score')::numeric),2) into average from jsonb_array_elements(grade_rows);
 insert into public.report_cards(institution_id,student_id,enrollment_id,academic_year_id,academic_period_id,overall_average,general_notes,status,generated_at)
  values(inst,p_student,enrollment,year_id,p_period,average,p_notes,'generated',clock_timestamp()) returning * into card;
 insert into public.report_card_lines(report_card_id,subject_id,final_score,qualitative_label,passed,notes,teacher_id)
  select card.id,r.subject_id,r.final_score,r.qualitative_label,r.passed,r.notes,r.teacher_id from jsonb_populate_recordset(null::public.report_card_lines,grade_rows) r;
 result:=to_jsonb(card)||jsonb_build_object('lines',coalesce((select jsonb_agg(to_jsonb(l.*) order by l.id) from public.report_card_lines l where l.report_card_id=card.id),'[]'::jsonb));
 return public.write_receipt_finish(inst,actor,p_key,result);
end $$;
revoke all on function public.report_card_generate(bigint,bigint,text,uuid) from public,anon;
grant execute on function public.report_card_generate(bigint,bigint,text,uuid) to authenticated;
-- Official persisted documents must be generated from database grades.
revoke insert,update,delete on public.report_cards,public.report_card_lines from anon,authenticated;

create function public.charges_create_batch(p_rows jsonb,p_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); result jsonb;
begin
 if not public.administrative_permission(inst,'payments.create') then raise exception 'Acceso denegado.' using errcode='42501'; end if;
 if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>10000 then raise exception 'Lote de cargos inválido.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.charges,p_rows) r where r.institution_id is distinct from inst
  or r.amount is null or r.amount<0 or r.amount::text in('NaN','Infinity','-Infinity') or r.discount is null or r.discount<0 or r.discount>r.amount
  or coalesce(r.late_fee,0)<>0 or r.due_at is null or not isfinite(r.due_at)
  or not exists(select 1 from public.students s where s.id=r.student_id and s.institution_id=inst and s.active)
  or not exists(select 1 from public.payment_concepts c where c.id=r.concept_id and c.institution_id=inst and c.active)
  or r.academic_year_id is not null and not exists(select 1 from public.academic_years y where y.id=r.academic_year_id and y.institution_id=inst)) then raise exception 'Cargo inválido o fuera de la institución.' using errcode='22023'; end if;
 if exists(select 1 from jsonb_populate_recordset(null::public.charges,p_rows) r group by r.student_id,r.concept_id,r.due_at having count(*)>1) then raise exception 'El lote contiene cargos duplicados.' using errcode='22023'; end if;
 result:=public.write_receipt_begin(inst,actor,p_key,'charges_create_batch',p_rows);
 if result is not null then return result; end if;
 with inserted as(insert into public.charges(institution_id,student_id,concept_id,academic_year_id,description,amount,discount,late_fee,total_amount,due_at,status)
  select inst,r.student_id,r.concept_id,r.academic_year_id,r.description,r.amount,r.discount,0,r.amount-r.discount,r.due_at,'pending'
   from jsonb_populate_recordset(null::public.charges,p_rows) r returning id)
 select coalesce(jsonb_agg(id::text order by id),'[]'::jsonb) into result from inserted;
 return public.write_receipt_finish(inst,actor,p_key,result);
end $$;
revoke all on function public.charges_create_batch(jsonb,uuid) from public,anon;
grant execute on function public.charges_create_batch(jsonb,uuid) to authenticated;
notify pgrst,'reload schema';
-- END 0049_atomic_documents_and_charges.sql


-- BEGIN 0050_durable_account_provisioning.sql
-- SHA256 770c8b8dbaeff3b737cc9e07681e4e2900a01126b437997e9e0a4e88074a696b
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
-- END 0050_durable_account_provisioning.sql


-- BEGIN 0051_identity_archive_and_role_guards.sql
-- SHA256 93323af616c66532818f79388bf78ec58a296f09b2cf9c29b6374283a80c81b8
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
-- END 0051_identity_archive_and_role_guards.sql


-- BEGIN 0052_atomic_chat_and_push_outbox.sql
-- SHA256 267c17ecb621e60f25b4e9b0294937bbbca35adacd0eb0d7fb8d205c65e204f5
-- Coordinated deployment: stop old chat writers, apply this migration, deploy
-- backend and Flutter UUID contract. Push requires backend VAPID configuration.
create table public.notification_push_outbox (
 id bigserial primary key,
 institution_id bigint not null references public.institutions(id) on delete cascade,
 notification_id bigint not null references public.notifications(id) on delete cascade,
 device_id bigint not null references public.devices(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','sending','sent','failed','skipped')),
 attempts integer not null default 0,
 available_at timestamptz not null default now(),
 lease_until timestamptz,
 lease_token uuid,
 subscription_hash bytea,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(notification_id,device_id)
);
alter table public.notification_push_outbox enable row level security;
revoke all on public.notification_push_outbox from public,anon,authenticated;
create index notification_push_pending on public.notification_push_outbox(available_at,id) where status in ('pending','sending');
create index notification_push_leases on public.notification_push_outbox(institution_id,lease_until) where status='sending';
create index if not exists idx_devices_chat_push on public.devices(user_id,id) where active and platform='web';
create table public.notification_push_dispatch (
 institution_id bigint primary key references public.institutions(id) on delete cascade,
 last_claimed_at timestamptz not null default '-infinity'
);
alter table public.notification_push_dispatch enable row level security;
revoke all on public.notification_push_dispatch from public,anon,authenticated;

create table public.notification_push_batches(
 notification_id bigint primary key references public.notifications(id) on delete cascade,
 institution_id bigint not null references public.institutions(id) on delete cascade,
 created_at timestamptz not null default clock_timestamp()
);
alter table public.notification_push_batches enable row level security;
revoke all on public.notification_push_batches from public,anon,authenticated;

create function public.notification_push_allowed(p_notification_id bigint) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.notifications n join public.users u on u.id=n.user_id
  join public.institutions inst on inst.id=n.institution_id
  where n.id=p_notification_id and u.institution_id=n.institution_id and u.active and u.deleted_at is null and inst.active and inst.deleted_at is null
  and case n.data->>'module'
   when 'chat' then public.portal_permission_for_user(u.id,'messages.send') and exists(select 1 from public.messages m
    join public.conversation_participants cp on cp.conversation_id=m.conversation_id where m.id=(n.data->>'messageId')::bigint and m.deleted_at is null and cp.user_id=u.id)
   when 'announcements' then exists(select 1 from public.announcements a where a.id=(n.data->>'announcementId')::bigint and a.institution_id=n.institution_id and a.published
    and public.announcement_recipient_allowed(n.institution_id,a.audience,u.id) and (a.group_id is null
     or public.user_has_role(u.id,'admin') or public.user_has_role(u.id,'coordinator') or public.user_has_role(u.id,'director')
     or public.user_has_role(u.id,'student') and exists(select 1 from public.students st join public.enrollments e on e.student_id=st.id and e.institution_id=u.institution_id where st.person_id=u.person_id and st.institution_id=u.institution_id and e.group_id=a.group_id)
     or public.user_has_role(u.id,'parent') and exists(select 1 from public.parents pa join public.parent_students ps on ps.parent_id=pa.id join public.enrollments e on e.student_id=ps.student_id and e.institution_id=u.institution_id where pa.person_id=u.person_id and pa.institution_id=u.institution_id and e.group_id=a.group_id)
     or public.user_has_role(u.id,'teacher') and (exists(select 1 from public.teachers t join public.classes c on c.teacher_id=t.id and c.institution_id=u.institution_id where t.person_id=u.person_id and t.institution_id=u.institution_id and t.active and c.active and c.group_id=a.group_id)
      or exists(select 1 from public.class_collaborators cc join public.classes c on c.id=cc.class_id and c.institution_id=u.institution_id where cc.teacher_user_id=u.id and cc.institution_id=u.institution_id and cc.status='active' and 'class.view'=any(cc.permissions) and c.active and c.group_id=a.group_id))))
   else false end)
$$;
revoke all on function public.notification_push_allowed(bigint) from public,anon,authenticated;

create function public.notification_push_enqueue(p_notification_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare n public.notifications; counts record;
begin
 select * into n from public.notifications where id=p_notification_id for key share;
 if not found then raise exception 'Notificación no encontrada.' using errcode='P0002'; end if;
 insert into public.notification_push_batches(notification_id,institution_id) values(n.id,n.institution_id) on conflict do nothing;
 if found then
  insert into public.notification_push_outbox(institution_id,notification_id,device_id)
   select n.institution_id,n.id,d.id from public.devices d where d.user_id=n.user_id and d.active and d.platform='web' and nullif(d.push_token,'') is not null;
  insert into public.notification_push_dispatch(institution_id) values(n.institution_id) on conflict do nothing;
 end if;
 -- Expire undelivered work even if VAPID is misconfigured and no worker claims.
 update public.notification_push_outbox set status='skipped',lease_token=null,lease_until=null,updated_at=clock_timestamp()
  where notification_id=n.id and created_at<clock_timestamp()-interval '24 hours' and (status='pending' or status='sending' and lease_until<=clock_timestamp());
 select count(*) filter(where status in('pending','sending')) pending,count(*) filter(where status='failed') failed,
  count(*) filter(where status='sent') sent into counts from public.notification_push_outbox where notification_id=n.id;
 return jsonb_build_object('status',case when counts.pending>0 then 'pending' when counts.failed>0 then 'failed' when counts.sent>0 then 'sent' else 'skipped' end);
end $$;
revoke all on function public.notification_push_enqueue(bigint) from public,anon,authenticated;
grant execute on function public.notification_push_enqueue(bigint) to service_role;

create or replace function public.chat_send_message(p_conversation_id bigint,p_uuid uuid,p_content text default null,p_file_id bigint default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id(); m public.messages; f public.files; msg_type integer; preview text;
begin
 if p_uuid is null or length(p_content)>4000 or (nullif(btrim(p_content),'') is null and p_file_id is null) then
  raise exception 'Mensaje inválido.' using errcode='22023';
 end if;
 if not public.portal_can('messages.send') or not exists(select 1 from public.conversations c join public.conversation_participants cp on cp.conversation_id=c.id
  where c.id=p_conversation_id and c.institution_id=inst and cp.user_id=actor) then
  raise exception 'Acceso denegado.' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('chat-send/'||p_uuid,0));
 select * into m from public.messages where uuid=p_uuid;
 if found then
  if m.sender_id<>actor or m.conversation_id<>p_conversation_id or m.content is distinct from p_content or m.file_id is distinct from p_file_id or m.deleted_at is not null then
   raise exception 'UUID ya utilizado para otro mensaje.' using errcode='23505';
  end if;
 else
  if p_file_id is not null and not exists(select 1 from public.files where id=p_file_id and institution_id=inst and deleted_at is null and public.portal_file_read(id)) then
   raise exception 'Adjunto no autorizado.' using errcode='42501';
  end if;
  insert into public.messages(uuid,conversation_id,sender_id,content,file_id) values(p_uuid,p_conversation_id,actor,p_content,p_file_id) returning * into m;
  select id into strict msg_type from public.catalog_notification_types where code='MSG';
  preview:=case when nullif(btrim(p_content),'') is null then 'Te envió un adjunto' when length(btrim(p_content))>140 then left(btrim(p_content),137)||'...' else btrim(p_content) end;
  with inserted_notifications as (insert into public.notifications(institution_id,user_id,notification_type_id,title,message,data,delivery_key)
   select inst,u.id,msg_type,left(coalesce(nullif(sender.full_name,''),'Nuevo mensaje'),200),preview,
    jsonb_build_object('module','chat','conversationId',p_conversation_id::text,'messageId',m.id::text,'deepLink','/chat/'||p_conversation_id),
    'chat/'||m.id||'/recipient/'||u.id
   from public.conversation_participants cp join public.users u on u.id=cp.user_id join public.users sender on sender.id=actor
   where cp.conversation_id=p_conversation_id and u.id<>actor and u.institution_id=inst and u.active and u.deleted_at is null
    and public.portal_permission_for_user(u.id,'messages.send') returning id,user_id),
  batches as(insert into public.notification_push_batches(institution_id,notification_id) select inst,id from inserted_notifications returning notification_id)
  insert into public.notification_push_outbox(institution_id,notification_id,device_id)
   select inst,n.id,d.id from inserted_notifications n join batches b on b.notification_id=n.id join public.devices d on d.user_id=n.user_id
   where d.active and d.platform='web' and nullif(d.push_token,'') is not null;
  insert into public.notification_push_dispatch(institution_id) values(inst) on conflict do nothing;
 end if;
 select * into f from public.files where id=m.file_id;
 return jsonb_build_object('id',m.id::text,'uuid',m.uuid,'conversationId',m.conversation_id::text,'senderId',m.sender_id::text,
  'senderName',(select full_name from public.users where id=actor),'sentAt',m.created_at,'content',m.content,
  'attachment',case when f.id is null then null else jsonb_build_object('id',f.id::text,'name',f.original_name,'url',f.url,'sizeBytes',f.size_bytes,'mimeType',f.mime_type) end);
end $$;
revoke all on function public.chat_send_message(bigint,uuid,text,bigint) from public,anon;
grant execute on function public.chat_send_message(bigint,uuid,text,bigint) to authenticated;
revoke insert on public.messages from authenticated;

-- One device per lease: confirmed devices never repeat after another device fails.
-- Four global leases and one per institution, enforced across backend replicas.
create or replace function public.notification_push_claim() returns jsonb
language plpgsql security definer set search_path=public as $$
declare job public.notification_push_outbox; n public.notifications; d public.devices; i integer;
begin
 perform pg_advisory_xact_lock(hashtextextended('chat-push-admission',0));
 if (select count(*) from public.notification_push_outbox where status='sending' and lease_until>clock_timestamp())>=4 then return null; end if;
 for i in 1..20 loop
  select q.* into job from public.notification_push_outbox q join public.notification_push_dispatch dispatch on dispatch.institution_id=q.institution_id
   where q.status in ('pending','sending') and q.available_at<=clock_timestamp() and (q.lease_until is null or q.lease_until<=clock_timestamp())
    and not exists(select 1 from public.notification_push_outbox active_job where active_job.institution_id=q.institution_id and active_job.status='sending' and active_job.lease_until>clock_timestamp())
   order by dispatch.last_claimed_at,q.available_at,q.id limit 1 for update of q skip locked;
  if not found then return null; end if;
  select * into n from public.notifications where id=job.notification_id;
  select * into d from public.devices where id=job.device_id;
  if job.attempts>=3 or job.created_at<clock_timestamp()-interval '24 hours' or not d.active or d.platform<>'web' or d.user_id<>n.user_id
   or not public.notification_push_allowed(n.id) then
   update public.notification_push_outbox set status=case when attempts>=3 then 'failed' else 'skipped' end,lease_token=null,lease_until=null,updated_at=clock_timestamp() where id=job.id;
   continue;
  end if;
  update public.notification_push_outbox set status='sending',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '60 seconds',subscription_hash=sha256(convert_to(d.push_token,'UTF8')),updated_at=clock_timestamp()
   where id=job.id returning * into job;
  update public.notification_push_dispatch set last_claimed_at=clock_timestamp() where institution_id=job.institution_id;
  return jsonb_build_object('id',job.id::text,'token',job.lease_token,'notificationId',n.id::text,'deviceId',d.id::text,'subscription',d.push_token,
   'title',n.title,'body',n.message,'deepLink',n.data->>'deepLink','tag',case when n.data->>'module'='chat' then 'chat-'||(n.data->>'conversationId') else 'notification-'||n.id end);
 end loop;
 return null;
end $$;
create or replace function public.notification_push_finish(p_id bigint,p_token uuid,p_outcome text,p_retry_after integer default 0) returns boolean
language plpgsql security definer set search_path=public as $$
declare job public.notification_push_outbox;
begin
 if p_outcome not in ('sent','retry','failed','gone') or p_retry_after is null or p_retry_after<0 or p_retry_after>3600 then raise exception 'Resultado inválido.' using errcode='22023'; end if;
 -- Parent-before-child locks match FK cascades and subscription replacement.
 perform n.id from public.notifications n join public.notification_push_outbox q on q.notification_id=n.id where q.id=p_id for key share of n;
 perform d.id from public.devices d join public.notification_push_outbox q on q.device_id=d.id where q.id=p_id for update of d;
 select * into job from public.notification_push_outbox where id=p_id for update;
 if not found or job.status<>'sending' or job.lease_token is distinct from p_token or job.lease_until<=clock_timestamp() then return false; end if;
 update public.notification_push_outbox set status=case when p_outcome='sent' then 'sent' when p_outcome='retry' and attempts<3 then 'pending' else 'failed' end,
  available_at=clock_timestamp()+make_interval(secs=>greatest(p_retry_after,5*attempts)),lease_token=null,lease_until=null,updated_at=clock_timestamp() where id=job.id;
 if p_outcome='gone' then update public.devices set active=false where id=job.device_id and sha256(convert_to(push_token,'UTF8'))=job.subscription_hash; end if;
 insert into public.notification_deliveries(notification_id,channel_id,destination,status,provider,error,sent_at)
  select job.notification_id,id,job.device_id::text,case when p_outcome='sent' then 'sent' else 'failed' end,'webpush',case when p_outcome='sent' then null else p_outcome end,
   case when p_outcome='sent' then clock_timestamp() else null end from public.catalog_notification_channels where code='PUSH';
 return true;
end $$;
revoke all on function public.notification_push_claim(),public.notification_push_finish(bigint,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.notification_push_claim(),public.notification_push_finish(bigint,uuid,text,integer) to service_role;

-- Explicit announcement retries reset only failed devices within their TTL.
-- The recipient/job transition and device reset share a transaction.
alter function public.retry_announcement_delivery(bigint) rename to announcement_retry_before_push_queue;
revoke all on function public.announcement_retry_before_push_queue(bigint) from public,anon,authenticated,service_role;
create function public.retry_announcement_delivery(p_job_id bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 result:=public.announcement_retry_before_push_queue(p_job_id);
 if result->>'status'='queued' then
  update public.notification_push_outbox q set status='pending',attempts=0,available_at=clock_timestamp(),lease_token=null,lease_until=null,updated_at=clock_timestamp()
   from public.announcement_delivery_recipients r where r.job_id=p_job_id and r.notification_id=q.notification_id and r.push_status='pending' and q.status='failed' and q.created_at>clock_timestamp()-interval '24 hours';
 end if;
 return result;
end $$;
revoke all on function public.retry_announcement_delivery(bigint) from public,anon,authenticated;
grant execute on function public.retry_announcement_delivery(bigint) to service_role;

-- Device registration is one actor-scoped write, not find-then-insert. Existing
-- duplicate registrations are retired only when that user refreshes the device.
create index if not exists devices_user_uuid_lookup on public.devices(user_id,device_uuid);
create function public.notification_device_save(p_subscription jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); device_key text; device bigint;
begin
 if cardinality(public.current_roles())=0 then raise exception 'Acceso denegado.' using errcode='42501'; end if;
 if jsonb_typeof(p_subscription) is distinct from 'object' or jsonb_typeof(p_subscription->'endpoint') is distinct from 'string'
  or jsonb_typeof(p_subscription->'keys') is distinct from 'object' or length(p_subscription::text)>5000 or nullif(p_subscription->>'endpoint','') is null then raise exception 'Suscripción inválida.' using errcode='22023'; end if;
 device_key:=encode(sha256(convert_to(p_subscription->>'endpoint','UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended('push-device/'||actor||'/'||device_key,0));
 select id into device from public.devices where user_id=actor and platform='web' and device_uuid=device_key
  order by active desc,last_synced_at desc nulls last,id desc limit 1 for update;
 if device is null then
  insert into public.devices(user_id,device_uuid,platform,push_token,active,last_synced_at)
   values(actor,device_key,'web',p_subscription::text,true,clock_timestamp()) returning id into device;
 else
  update public.devices set push_token=p_subscription::text,active=true,last_synced_at=clock_timestamp() where id=device;
 end if;
 update public.devices set active=false where user_id=actor and platform='web' and device_uuid=device_key and id<>device and active;
 return jsonb_build_object('id',device::text);
end $$;
revoke all on function public.notification_device_save(jsonb) from public,anon;
grant execute on function public.notification_device_save(jsonb) to authenticated;
revoke insert,update on public.devices from authenticated;
-- END 0052_atomic_chat_and_push_outbox.sql


-- BEGIN 0053_backend_readiness.sql
-- SHA256 7be4a3d68134d012bef87ffcb173ab8060b843835ab5e2bbf220931e87d1f5e5
-- Lightweight anonymous probe exposes only the installed API contract version.
create function public.backend_readiness_v1() returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('schemaVersion',53)
$$;
revoke all on function public.backend_readiness_v1() from public;
grant execute on function public.backend_readiness_v1() to anon,authenticated,service_role;
-- END 0053_backend_readiness.sql


DO $verify$
BEGIN
  IF (public.backend_readiness_v1()->>'schemaVersion')::integer IS DISTINCT FROM 53 THEN
    RAISE EXCEPTION 'La verificación final del contrato SQL falló.';
  END IF;
END
$verify$;
NOTIFY pgrst, 'reload schema';
COMMIT;
SELECT 53 AS schema_version, 'Actualización SQL completada. Verificar /ready y clientes compatibles.' AS resultado;
