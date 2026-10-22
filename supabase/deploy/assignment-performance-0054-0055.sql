-- Generated from the two named migrations; apply only after backing up contract 53.
-- Compatible with the currently deployed backend. This does not activate 2FA.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $preflight$ BEGIN
 IF (public.backend_readiness_v1()->>'schemaVersion')::int<>53 THEN
  RAISE EXCEPTION 'Expected base contract 53 before the assignment update.';
 END IF;
 IF to_regprocedure('public.class_permission_ids(text)') IS NOT NULL
  OR to_regprocedure('public.assignment_write(bigint,jsonb,bigint[],uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'Assignment migration already present; review tracking before reapplying.';
 END IF;
END $preflight$;

-- BEGIN 0054_batched_academic_rls.sql SHA256 d56ae042fb43dd2586d7c1e9eefe2b1d1a9890a9329f444d436b05c053d32b3b
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

-- END 0054_batched_academic_rls.sql

-- BEGIN 0055_atomic_assignment_write.sql SHA256 865c1b962a7fa4b21b866c90491bbf55f49804a4aee298a1d53ef6e74b7dd21f
-- A failed response must not leave a partially saved task/attachment list.
-- Every retry with the same operation key returns the committed document.
create function public.assignment_write(p_id bigint,p_data jsonb,p_file_ids bigint[],p_key uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare actor bigint:=public.chat_actor(); inst bigint:=public.current_institution_id();
 task public.assignments%rowtype; old_task public.assignments%rowtype; cls public.classes%rowtype;
 teacher bigint; period bigint; doc jsonb; replay jsonb; attachment_id bigint; total bigint:=0; can_review boolean;
 delivered bigint:=0; graded bigint:=0; target_class bigint; title_text text; score numeric; due timestamptz;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or p_key is null or
   exists(select 1 from jsonb_object_keys(p_data) k where k not in
     ('class_id','title','description','instructions','kind','due_at','max_score','allow_late','published')) then
   raise exception 'Datos de tarea inválidos.' using errcode='22023';
 end if;
 target_class:=(p_data->>'class_id')::bigint; title_text:=trim(p_data->>'title');
 score:=(p_data->>'max_score')::numeric; due:=(p_data->>'due_at')::timestamptz;
 if target_class is null or target_class<1 or jsonb_typeof(p_data->'title') is distinct from 'string'
   or nullif(title_text,'') is null or length(title_text)>200
   or score is null or score::text in ('NaN','Infinity','-Infinity') or score<=0 or score>9999.99
   or due is null or not isfinite(due)
   or p_data?'kind' and (p_data->>'kind' is null or p_data->>'kind' not in ('homework','exam','project','quiz','presentation'))
   or p_data?'allow_late' and jsonb_typeof(p_data->'allow_late')<>'boolean'
   or p_data?'published' and jsonb_typeof(p_data->'published')<>'boolean'
   or cardinality(p_file_ids)>100 or array_position(p_file_ids,null) is not null then
   raise exception 'Datos de tarea inválidos.' using errcode='22023';
 end if;
 -- Both the destination and the old resource must remain writable. A create
 -- grant without class.view cannot be used to read the returned document.
 select * into cls from public.classes where id=target_class and institution_id=inst and active;
 if cls.id is null or not public.class_permission(cls.id,'assignments.create')
   or not public.class_permission(cls.id,'class.view') then
   raise exception 'No tienes permiso en esta clase.' using errcode='42501';
 end if;
 if p_id is not null then
   select * into old_task from public.assignments where id=p_id and institution_id=inst and deleted_at is null for update;
   if old_task.id is null then raise exception 'Tarea no encontrada.' using errcode='P0002'; end if;
   if not public.class_permission(old_task.class_id,'assignments.create') or not public.class_permission(old_task.class_id,'class.view') then
     raise exception 'No tienes permiso en esta tarea.' using errcode='42501';
   end if;
 end if;
 replay:=public.write_receipt_begin(inst,actor,p_key,'assignment_write',jsonb_build_object('id',p_id,'data',p_data,'fileIds',p_file_ids));
 if replay is not null then
   if not exists(select 1 from public.assignments a where a.id=(replay->>'id')::bigint
     and a.institution_id=inst and a.deleted_at is null and public.class_permission(a.class_id,'class.view')
     and public.class_permission(a.class_id,'assignments.create')) then
     raise exception 'Tarea no disponible.' using errcode='42501';
   end if;
   return replay;
 end if;
 if p_file_ids is not null then
   foreach attachment_id in array p_file_ids loop
     if not exists(select 1 from public.files f where f.id=attachment_id and f.institution_id=inst and f.deleted_at is null)
       or not public.portal_file_read(attachment_id) then
       raise exception 'Adjunto no disponible.' using errcode='42501';
     end if;
   end loop;
 end if;
 select id into teacher from public.teachers where institution_id=inst and active
   and person_id=(select person_id from public.users where id=actor) order by id limit 1;
 select id into period from public.academic_periods where institution_id=inst
   and academic_year_id=cls.academic_year_id and start_date<=due::date and end_date>=due::date order by display_order,id limit 1;
 if p_id is null then
   insert into public.assignments(institution_id,class_id,academic_period_id,title,description,instructions,kind,due_at,max_score,
     allow_late,published,assigned_at,created_by,updated_at)
   values(inst,cls.id,period,title_text,p_data->>'description',p_data->>'instructions',coalesce(p_data->>'kind','homework'),due,score,
     coalesce((p_data->>'allow_late')::boolean,false),coalesce((p_data->>'published')::boolean,true),clock_timestamp(),teacher,clock_timestamp())
   returning * into task;
 else
   update public.assignments set class_id=cls.id,academic_period_id=period,title=title_text,description=p_data->>'description',
     instructions=p_data->>'instructions',kind=coalesce(p_data->>'kind',old_task.kind),due_at=due,max_score=score,
     allow_late=coalesce((p_data->>'allow_late')::boolean,false),published=coalesce((p_data->>'published')::boolean,true),
     assigned_at=clock_timestamp(),updated_at=clock_timestamp() where id=p_id and institution_id=inst returning * into task;
 end if;
 if p_file_ids is not null then
   delete from public.assignment_files where assignment_id=task.id and not(file_id=any(p_file_ids));
   insert into public.assignment_files(assignment_id,file_id) select task.id,id from (select distinct unnest(p_file_ids) id) files
     on conflict(assignment_id,file_id) do nothing;
 end if;
 -- The response obeys the same roster/review grants as the RLS-backed reader.
 if public.class_permission(cls.id,'students.view') then
   can_review:=public.class_permission(cls.id,'assignments.review');
   with enrolled as materialized (
     select distinct e.student_id from public.enrollments e join public.students s on s.id=e.student_id and s.active
     join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
     where e.institution_id=inst and e.group_id=cls.group_id and e.academic_year_id=cls.academic_year_id
   ) select (select count(*) from enrolled),
     count(*) filter(where status.code in ('ENTR','CALI','REV')),count(*) filter(where status.code='CALI')
     into total,delivered,graded from public.submissions s join enrolled e on e.student_id=s.student_id
     join public.catalog_task_statuses status on status.id=s.task_status_id
     where s.assignment_id=task.id and s.institution_id=inst and can_review;
 end if;
 select jsonb_build_object('id',task.id::text,'classId',cls.id,'subjectName',coalesce(subject.name,'Materia'),
   'groupName',coalesce(g.name,'Grupo'),'teacherName',nullif(trim(coalesce(person.first_name,'')||' '||coalesce(person.last_name,'')),''),
   'title',task.title,'description',task.description,'instructions',task.instructions,'kind',task.kind,
   'assignedAt',coalesce(task.assigned_at,task.created_at),'dueAt',task.due_at,'maxScore',coalesce(task.max_score,100),
   'allowLate',coalesce(task.allow_late,false),'published',coalesce(task.published,true),
   'totalStudents',total,'submittedCount',delivered,'gradedCount',graded,
   'attachments',coalesce((select jsonb_agg(jsonb_build_object('id',f.id::text,'name',coalesce(f.original_name,'archivo'),
     'url',coalesce(f.url,''),'sizeBytes',f.size_bytes,'mimeType',f.mime_type) order by link.id)
     from public.assignment_files link join public.files f on f.id=link.file_id and f.institution_id=inst and f.deleted_at is null
     where link.assignment_id=task.id),'[]'::jsonb)) into doc
 from (select 1) seed left join public.subjects subject on subject.id=cls.subject_id
 left join public.groups g on g.id=cls.group_id left join public.teachers t on t.id=cls.teacher_id
 left join public.persons person on person.id=t.person_id;
 return public.write_receipt_finish(inst,actor,p_key,doc);
end $$;
revoke all on function public.assignment_write(bigint,jsonb,bigint[],uuid) from public,anon;
grant execute on function public.assignment_write(bigint,jsonb,bigint[],uuid) to authenticated;

-- Additive capability: the existing deployed backend still expects base
-- contract 53. It remains healthy while the compatible DB change rolls out.
create or replace function public.backend_readiness_v1() returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('schemaVersion',53,'assignmentWriteVersion',1)
$$;

-- END 0055_atomic_assignment_write.sql

DO $tracking$ BEGIN
 IF to_regclass('public._applied_scripts') IS NOT NULL THEN
  INSERT INTO public._applied_scripts(name) VALUES ('0054_batched_academic_rls.sql'),('0055_atomic_assignment_write.sql') ON CONFLICT DO NOTHING;
 END IF;
END $tracking$;
NOTIFY pgrst, 'reload schema';
COMMIT;
SELECT public.backend_readiness_v1() AS installed_contract;
