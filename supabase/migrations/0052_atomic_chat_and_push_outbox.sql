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
