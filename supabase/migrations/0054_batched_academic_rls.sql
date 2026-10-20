-- Calculate resource grants in statement InitPlans instead of repeating the
-- actor/roles/collaboration joins for every row of an academic feed. No grant is
-- cached across statements, sessions, users or institutions. RLS stays enabled.
create function public.class_permission_ids(p_permission text) returns bigint[]
language plpgsql stable security definer set search_path=public as $$
declare actor public.users%rowtype; inst bigint:=public.current_institution_id();
  codes text[]; result bigint[]; admin_codes text[];
begin
 select * into actor from public.users where auth_user_id=auth.uid()
   and institution_id=inst and active and deleted_at is null;
 if actor.id is null then return array[]::bigint[]; end if;
 select array_agg(distinct r.code) into codes from public.user_roles ur join public.roles r on r.id=ur.role_id
 where ur.user_id=actor.id and r.active and (ur.institution_id is null or ur.institution_id=inst)
   and (r.institution_id is null or r.institution_id=inst);
 admin_codes:=case p_permission
   when 'class.view' then array['classes.view','reports.view','schedules.view','dashboard.view']
   when 'students.view' then array['students.view','classes.view','reports.view']
   when 'assignments.review' then array['classes.view','reports.view']
   when 'assignments.grade' then array['reports.generate'] when 'grades.write' then array['reports.generate']
   when 'assignments.create' then array['classes.edit'] when 'attendance.write' then array['classes.edit']
   when 'collaborators.manage' then array['classes.edit'] else array[]::text[] end;
 if codes && array['admin','coordinator','director','super_admin']::text[] and cardinality(admin_codes)>0
   and (actor.admin_permissions is null or actor.admin_permissions && admin_codes) then
   select array_agg(c.id) into result from public.classes c where c.institution_id=inst and c.active;
 elsif 'teacher'=any(codes) then
   select array_agg(distinct c.id) into result from public.classes c
   join public.teachers t on t.person_id=actor.person_id and t.institution_id=inst and t.active
   where c.institution_id=inst and c.active and (c.teacher_id=t.id
     or p_permission<>'collaborators.manage' and exists(select 1 from public.class_collaborators cc
       where cc.class_id=c.id and cc.institution_id=inst and cc.teacher_id=t.id
         and cc.teacher_user_id=actor.id and cc.status='active' and p_permission=any(cc.permissions)));
 end if;
 return coalesce(result,array[]::bigint[]);
end $$;

create function public.teacher_group_ids() returns bigint[]
language sql stable security definer set search_path=public as $$
 select coalesce(array_agg(distinct c.group_id),array[]::bigint[]) from public.classes c
 where c.institution_id=(select public.current_institution_id())
   and c.id=any((select public.class_permission_ids('students.view'))::bigint[])
$$;
create function public.teacher_student_ids() returns bigint[]
language sql stable security definer set search_path=public as $$
 select coalesce(array_agg(distinct e.student_id),array[]::bigint[]) from public.enrollments e
 where e.institution_id=(select public.current_institution_id())
   and e.group_id=any((select public.teacher_group_ids())::bigint[])
$$;

create function public.portal_staff_actor() returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.users u where u.auth_user_id=(select auth.uid())
   and u.institution_id=(select public.current_institution_id()) and u.active and u.deleted_at is null
   and public.portal_staff(u.id))
$$;
create function public.portal_family_student_ids() returns bigint[]
language sql stable security definer set search_path=public as $$
 with actor as materialized (
   select u.id,u.person_id,u.institution_id from public.users u where u.auth_user_id=(select auth.uid())
     and u.institution_id=(select public.current_institution_id()) and u.active and u.deleted_at is null
 ) select coalesce(array_agg(s.id),array[]::bigint[]) from public.students s join actor a on a.institution_id=s.institution_id
 where s.person_id=a.person_id or exists(select 1 from public.parents p join public.parent_students ps on ps.parent_id=p.id
   where p.person_id=a.person_id and p.institution_id=a.institution_id and ps.student_id=s.id)
$$;
create function public.portal_family_class_ids() returns bigint[]
language sql stable security definer set search_path=public as $$
 select coalesce(array_agg(distinct c.id),array[]::bigint[]) from public.classes c
 join public.enrollments e on e.group_id=c.group_id and e.institution_id=c.institution_id
 where c.institution_id=(select public.current_institution_id())
   and e.student_id=any((select public.portal_family_student_ids())::bigint[])
$$;
revoke all on function public.class_permission_ids(text),public.teacher_group_ids(),public.teacher_student_ids(),
 public.portal_staff_actor(),public.portal_family_student_ids(),public.portal_family_class_ids() from public,anon;
grant execute on function public.class_permission_ids(text),public.teacher_group_ids(),public.teacher_student_ids(),
 public.portal_staff_actor(),public.portal_family_student_ids(),public.portal_family_class_ids() to authenticated;

do $$ declare tbl text; expr text; permission text; begin
 for tbl,expr,permission in values
   ('classes','id','class.view'),('assignments','class_id','class.view'),
   ('evaluations','class_id','students.view'),
   ('submissions','(select class_id from public.assignments where id=assignment_id)','assignments.review'),
   ('grades','(select class_id from public.evaluations where id=evaluation_id)','students.view'),
   ('class_sessions','class_id','students.view'),
   ('attendances','(select class_id from public.class_sessions where id=class_session_id)','students.view')
 loop
   execute format('alter policy class_scope_read on public.%I using (
     not (select public.is_teacher_actor()) or %s=any((select public.class_permission_ids(%L))::bigint[]))',tbl,expr,permission);
 end loop;
end $$;
alter policy class_scope_roster on public.enrollments using (
 not (select public.is_teacher_actor()) or group_id=any((select public.teacher_group_ids())::bigint[]));
alter policy class_scope_students on public.students using (
 not (select public.is_teacher_actor()) or id=any((select public.teacher_student_ids())::bigint[]));
alter policy portal_module_read on public.assignments using (
 (select public.portal_can('assignments.view')) and
 ((select public.portal_staff_actor()) or class_id=any((select public.portal_family_class_ids())::bigint[])));
alter policy portal_module_read on public.submissions using (
 (select public.portal_can('assignments.view')) and
 ((select public.portal_staff_actor()) or student_id=any((select public.portal_family_student_ids())::bigint[])));
