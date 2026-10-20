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
