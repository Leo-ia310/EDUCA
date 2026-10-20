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
