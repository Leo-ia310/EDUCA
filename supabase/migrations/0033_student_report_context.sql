-- A report must not invent first place or 100% attendance when no records
-- exist. This scoped read returns missing metrics as NULL and counts the
-- requested academic period, rather than all historical attendance.
create or replace function public.student_report_context(p_student_id bigint,p_period_id bigint default null)
returns jsonb language plpgsql stable set search_path=public as $$
declare year_key bigint; starts date; ends date; attendance numeric; result jsonb;
begin
  if not public.portal_student_scope(p_student_id) or not public.portal_can('reports.view')
      or not public.admin_can('reports.view') or not public.portal_can_view_grades(p_student_id,p_period_id) then
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
revoke all on function public.student_report_context(bigint,bigint) from public,anon;
grant execute on function public.student_report_context(bigint,bigint) to authenticated;
