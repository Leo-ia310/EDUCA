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
