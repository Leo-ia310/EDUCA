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
