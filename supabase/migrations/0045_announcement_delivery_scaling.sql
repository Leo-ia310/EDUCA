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
