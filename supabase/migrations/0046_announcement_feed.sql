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
