-- One uncorrelated scope per statement; never cache it across sessions/queries.
create or replace function public.schedule_visible_ids() returns setof bigint
language sql stable security definer set search_path=public as $$
  with actor as materialized(select u.*,public.user_has_role(u.id,'teacher') teacher,public.user_has_role(u.id,'parent') parent,
      public.user_has_role(u.id,'student') student from public.users u where u.auth_user_id=auth.uid() and u.institution_id=(select public.current_institution_id())),
  teacher_classes as materialized (
    select c.id,c.group_id,c.academic_year_id from actor u join public.teachers t on t.institution_id=u.institution_id and t.person_id=u.person_id and t.active
      join public.classes c on c.teacher_id=t.id and c.institution_id=u.institution_id and c.active where u.teacher
    union
    select c.id,c.group_id,c.academic_year_id from actor u join public.teachers t on t.institution_id=u.institution_id and t.person_id=u.person_id and t.active
      join public.class_collaborators cc on cc.teacher_user_id=u.id and cc.teacher_id=t.id and cc.institution_id=u.institution_id and cc.status='active' and 'class.view'=any(cc.permissions)
      join public.classes c on c.id=cc.class_id and c.institution_id=u.institution_id and c.active where u.teacher
  ), family_students as materialized (
    select s.id,s.institution_id from actor u join public.students s on s.person_id=u.person_id and s.institution_id=u.institution_id and s.active where u.student
    union
    select s.id,s.institution_id from actor u join public.parents p on p.person_id=u.person_id and p.institution_id=u.institution_id
      join public.parent_students ps on ps.parent_id=p.id join public.students s on s.id=ps.student_id and s.institution_id=u.institution_id and s.active where u.parent
  ), family_classes as materialized (
    select c.id,c.group_id,c.academic_year_id from family_students student join public.enrollments e on e.student_id=student.id and e.institution_id=student.institution_id
      join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
      join public.classes c on c.group_id=e.group_id and c.academic_year_id=e.academic_year_id and c.institution_id=e.institution_id and c.active
  ), own_classes as materialized (
    select c.id,c.group_id from (select * from teacher_classes union select * from family_classes) c
      join public.academic_years y on y.id=c.academic_year_id and y.is_current and y.active
  ) select s.id from public.schedules s join public.academic_years y on y.id=s.academic_year_id and y.is_current and y.active
    where s.institution_id=(select public.current_institution_id()) and (
      s.class_id in(select id from own_classes) or s.kind='break' and (s.group_id is null or s.group_id in(select group_id from own_classes))
        and exists(select 1 from public.schedules assigned where assigned.class_id in(select id from own_classes)))
$$;
revoke all on function public.schedule_visible_ids() from public,anon;
grant execute on function public.schedule_visible_ids() to authenticated;
create policy schedule_scoped_read on public.schedules as restrictive for select to authenticated
  using ((select public.administrative_permission(public.current_institution_id(),'schedules.view')) or id in(select public.schedule_visible_ids()));
