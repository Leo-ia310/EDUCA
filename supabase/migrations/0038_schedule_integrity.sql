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
