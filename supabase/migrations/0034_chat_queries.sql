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
