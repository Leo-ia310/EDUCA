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
