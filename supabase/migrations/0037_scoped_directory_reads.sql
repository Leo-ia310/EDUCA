create or replace function public.chat_contacts(p_search text default null,p_limit integer default 40) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if p_limit is null or p_limit<1 or p_limit>100 or length(p_search)>100 then raise exception 'Filtros inválidos.' using errcode='22023'; end if;
  with matches as (
    select u.id,u.full_name,u.email,u.avatar_url,coalesce(role.code,'student') code from public.users u
    left join lateral (select r.code from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_id=u.id and (ur.institution_id is null or ur.institution_id=u.institution_id) and (r.institution_id is null or r.institution_id=u.institution_id)
      order by case r.code when 'admin' then 0 when 'director' then 1 when 'coordinator' then 2 when 'teacher' then 3 when 'parent' then 4 else 5 end,r.id limit 1) role on true
    where u.institution_id=public.current_institution_id() and u.id<>actor and u.active and u.deleted_at is null
      and (nullif(trim(p_search),'') is null or u.full_name ilike '%'||trim(p_search)||'%' or u.email ilike '%'||trim(p_search)||'%'
        or exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id
          and (ur.institution_id is null or ur.institution_id=u.institution_id) and (r.institution_id is null or r.institution_id=u.institution_id)
          and (r.code ilike '%'||trim(p_search)||'%' or case r.code when 'teacher' then 'Maestro' when 'parent' then 'Padre'
            when 'student' then 'Estudiante' when 'admin' then 'Administrador' when 'coordinator' then 'Coordinador' when 'director' then 'Director' else r.name end ilike '%'||trim(p_search)||'%')))
    order by lower(u.full_name),u.id limit p_limit
  ) select jsonb_build_object('contacts',coalesce(jsonb_agg(jsonb_build_object('userId',id::text,'name',full_name,'email',coalesce(email,''),
    'role',code,'avatarUrl',avatar_url) order by lower(full_name),id),'[]'::jsonb)) into result from matches;
  return result;
end $$;
revoke all on function public.chat_contacts(text,integer) from public,anon;
grant execute on function public.chat_contacts(text,integer) to authenticated;

-- The dashboard only needs current assigned/collaborating classes, not the
-- complete management workspace with every invitation and teacher option.
create or replace function public.teacher_dashboard_classes() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); result jsonb;
begin
  if not public.portal_staff(actor) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  with candidates as materialized (
    select c.*,cc.permissions
      from public.classes c join public.academic_years y on y.id=c.academic_year_id and y.is_current and y.active
      left join public.class_collaborators cc on cc.class_id=c.id and cc.teacher_user_id=actor and cc.status='active'
      where c.institution_id=public.current_institution_id() and c.active
        and (cc.id is not null or exists(select 1 from public.teachers t join public.users u on u.person_id=t.person_id and u.institution_id=t.institution_id
          where t.id=c.teacher_id and t.active and u.id=actor))
  ), visible as materialized (
    select c.*,s.name subject_name,g.name group_name,public.class_permission(c.id,'collaborators.manage') owner from candidates c
      left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      where public.class_permission(c.id,'class.view')
  ) select jsonb_build_object('classes',coalesce(jsonb_agg(jsonb_build_object('classId',id,'groupId',group_id,'academicYearId',academic_year_id,
    'subjectName',coalesce(subject_name,'Materia'),'groupName',coalesce(group_name,'Grupo'),'isOwner',owner,
    'permissions',case when owner then to_jsonb(array['class.view','students.view','assignments.create','assignments.review','assignments.grade','grades.write','attendance.write','collaborators.manage'])
      else to_jsonb(permissions) end) order by subject_name,group_name,id),'[]'::jsonb)) into result from visible;
  return result;
end $$;
revoke all on function public.teacher_dashboard_classes() from public,anon;
grant execute on function public.teacher_dashboard_classes() to authenticated;

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
  ), allowed as materialized (select * from latest where admin_actor or public.portal_can_view_grades(student_id,academic_period_id)),
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
revoke all on function public.latest_report_cards(bigint,bigint,bigint,integer,integer) from public,anon;
grant execute on function public.latest_report_cards(bigint,bigint,bigint,integer,integer) to authenticated;
