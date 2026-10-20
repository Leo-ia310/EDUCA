alter table public.assignments add column kind text not null default 'homework'
  check(kind in ('homework','exam','project','quiz','presentation'));
update public.assignments a set kind=case typed.code when 'EXM' then 'exam' when 'PRO' then 'project'
  when 'QZ' then 'quiz' when 'EXP' then 'presentation' else 'homework' end
from (select distinct on(e.assignment_id) e.assignment_id,t.code from public.evaluations e
  join public.catalog_evaluation_types t on t.id=e.evaluation_type_id where e.assignment_id is not null order by e.assignment_id,e.id) typed
where typed.assignment_id=a.id;

-- One bounded query per feed page. It retains table RLS, class collaboration
-- grants, student scope, visibility rules and MFA. The cursor uses due_at + id;
-- equal timestamps and NULL due dates cannot silently skip assignments.
create or replace function public.assignment_feed(
  p_student_id bigint default null,p_class_id bigint default null,p_search text default null,
  p_only_open boolean default false,p_kinds text[] default null,p_subject text default null,
  p_after_due_at timestamptz default null,p_after_id bigint default null,p_limit integer default 50
) returns jsonb language plpgsql stable set search_path=public as $$
declare actor bigint; result jsonb;
begin
  select id into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id()
    and active and deleted_at is null;
  if actor is null then raise exception 'Sesión requerida.' using errcode='42501'; end if;
  if p_student_id is null then
    if not public.portal_staff(actor) then raise exception 'Acceso denegado.' using errcode='42501'; end if;
  elsif not public.portal_can('assignments.view') or not public.portal_student_scope(p_student_id) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  if p_limit is null or p_limit not between 1 and 100 or length(p_search)>150 or length(p_subject)>100
      or (p_kinds is not null and not p_kinds<@array['homework','exam','project','quiz','presentation']::text[])
      or (p_after_id is null and p_after_due_at is not null) then
    raise exception 'Filtros o cursor inválidos.' using errcode='22023';
  end if;
  with base as materialized (
    select a.*,c.group_id,c.academic_year_id,coalesce(subject.name,'Materia') subject_name,
      coalesce(g.name,'Grupo') group_name,trim(person.first_name||' '||person.last_name) teacher_name
    from public.assignments a join public.classes c on c.id=a.class_id
    join public.academic_years y on y.id=c.academic_year_id and y.is_current
    left join public.subjects subject on subject.id=c.subject_id left join public.groups g on g.id=c.group_id
    left join public.teachers teacher on teacher.id=c.teacher_id left join public.persons person on person.id=teacher.person_id
    where a.institution_id=public.current_institution_id() and a.deleted_at is null and c.active
      and (p_class_id is null or a.class_id=p_class_id) and (p_kinds is null or a.kind=any(p_kinds))
      and (p_subject is null or strpos(lower(trim(subject.name)),lower(trim(p_subject)))>0 or strpos(lower(trim(p_subject)),lower(trim(subject.name)))>0)
      and (nullif(trim(p_search),'') is null or strpos(lower(a.title||' '||coalesce(subject.name,'')),lower(trim(p_search)))>0)
      and (not p_only_open or (a.published and (a.due_at is null or a.due_at>=now())))
      and (p_student_id is null or (a.published and exists(select 1 from public.enrollments e
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
        where e.student_id=p_student_id and e.institution_id=a.institution_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id)))
      and (p_after_id is null or
        (p_after_due_at is null and a.due_at is null and a.id>p_after_id) or
        (p_after_due_at is not null and (a.due_at is null or (a.due_at,a.id)>(p_after_due_at,p_after_id))))
    order by a.due_at nulls last,a.id
    limit case when p_only_open then null else p_limit+1 end
  ), group_scope as (select distinct group_id,academic_year_id from base), enrolled as materialized (
    select e.group_id,e.academic_year_id,e.student_id
    from public.enrollments e join group_scope scope on scope.group_id=e.group_id and scope.academic_year_id=e.academic_year_id
    join public.students student on student.id=e.student_id and student.active
    join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
    where e.institution_id=public.current_institution_id() and (p_student_id is null or e.student_id=p_student_id)
  ), roster as (
    select group_id,academic_year_id,count(distinct student_id) total from enrolled group by group_id,academic_year_id
  ), submissions as (
    select s.assignment_id,count(*) filter(where status.code in ('ENTR','CALI','REV')) submitted,
      count(*) filter(where status.code='CALI') graded
    from public.submissions s join base a on a.id=s.assignment_id join public.catalog_task_statuses status on status.id=s.task_status_id
    join enrolled on enrolled.student_id=s.student_id and enrolled.group_id=a.group_id and enrolled.academic_year_id=a.academic_year_id
    where s.institution_id=public.current_institution_id() and (p_student_id is null or s.student_id=p_student_id)
    group by s.assignment_id
  ), counted as (
    select a.*,coalesce(roster.total,0) total_students,coalesce(s.submitted,0) submitted_count,coalesce(s.graded,0) graded_count
    from base a left join roster on roster.group_id=a.group_id and roster.academic_year_id=a.academic_year_id
    left join submissions s on s.assignment_id=a.id
  ), page as materialized (
    select a.*,row_number() over(order by a.due_at nulls last,a.id) position from counted a
    where not p_only_open or a.total_students=0 or a.graded_count<a.total_students
    order by a.due_at nulls last,a.id limit p_limit+1
  ), files as (
    select link.assignment_id,jsonb_agg(jsonb_build_object('id',f.id::text,'name',coalesce(f.original_name,'archivo'),'url',coalesce(f.url,''),
      'sizeBytes',f.size_bytes,'mimeType',f.mime_type) order by link.id) attachments
    from public.assignment_files link join page a on a.id=link.assignment_id
    join public.files f on f.id=link.file_id and f.deleted_at is null group by link.assignment_id
  ), items as (
    select a.position,jsonb_build_object('id',a.id::text,'classId',a.class_id::text,'subjectName',a.subject_name,'groupName',a.group_name,
      'teacherName',a.teacher_name,'title',a.title,'description',a.description,'instructions',a.instructions,
      'assignedAt',coalesce(a.assigned_at::text,a.created_at::text,''),'dueAt',a.due_at,'kind',a.kind,'maxScore',coalesce(a.max_score,100),
      'allowLate',coalesce(a.allow_late,false),'published',coalesce(a.published,true),'attachments',coalesce(files.attachments,'[]'),
      'totalStudents',a.total_students,'submittedCount',a.submitted_count,'gradedCount',a.graded_count,
      'progress',case when p_student_id is null then null else jsonb_build_object(
        'status',(select case when status.code='CALI' then 'graded' when s.is_late then 'late' else 'submitted' end
          from public.submissions s join public.catalog_task_statuses status on status.id=s.task_status_id
          where s.assignment_id=a.id and s.student_id=p_student_id and status.code in ('ENTR','CALI','REV') limit 1),
        'score',(select g.score from public.grades g join public.evaluations e on e.id=g.evaluation_id
          where e.assignment_id=a.id and g.student_id=p_student_id order by e.id desc,g.id desc limit 1)) end) payload
    from page a left join files on files.assignment_id=a.id where a.position<=p_limit
  ) select jsonb_build_object('assignments',coalesce((select jsonb_agg(payload order by position) from items),'[]'),
      'nextCursor',case when exists(select 1 from page where position>p_limit)
        then (select jsonb_build_object('id',id::text,'dueAt',due_at) from page where position=p_limit) else null end) into result;
  return result;
end $$;

revoke all on function public.assignment_feed(bigint,bigint,text,boolean,text[],text,timestamptz,bigint,integer) from public,anon;
grant execute on function public.assignment_feed(bigint,bigint,text,boolean,text[],text,timestamptz,bigint,integer) to authenticated;
create index if not exists assignments_feed_due_id on public.assignments(institution_id,due_at,id) where deleted_at is null;

create or replace function public.assignment_counters(p_student_id bigint default null) returns jsonb
language plpgsql stable set search_path=public as $$
declare actor bigint; result jsonb;
begin
  select id into actor from public.users where auth_user_id=auth.uid() and institution_id=public.current_institution_id() and active and deleted_at is null;
  if actor is null or (p_student_id is null and not public.portal_staff(actor)) or
      (p_student_id is not null and (not public.portal_can('assignments.view') or not public.portal_student_scope(p_student_id))) then
    raise exception 'Acceso denegado.' using errcode='42501';
  end if;
  with tasks as materialized (
    select a.id,a.published,a.due_at,c.group_id,c.academic_year_id from public.assignments a
      join public.classes c on c.id=a.class_id join public.academic_years y on y.id=c.academic_year_id and y.is_current
    where a.institution_id=public.current_institution_id() and a.deleted_at is null and c.active and
      (p_student_id is null or (a.published and exists(select 1 from public.enrollments e
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
        where e.student_id=p_student_id and e.group_id=c.group_id and e.academic_year_id=c.academic_year_id)))
  ), scope as (select distinct group_id,academic_year_id from tasks), enrolled as materialized (
    select e.group_id,e.academic_year_id,e.student_id from public.enrollments e
      join scope on scope.group_id=e.group_id and scope.academic_year_id=e.academic_year_id
      join public.students student on student.id=e.student_id and student.active
      join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id and status.code='ACT'
    where e.institution_id=public.current_institution_id() and (p_student_id is null or e.student_id=p_student_id)
  ), roster as (
    select group_id,academic_year_id,count(distinct student_id) total from enrolled group by group_id,academic_year_id
  ), counts as (
    select s.assignment_id,count(*) filter(where status.code in ('ENTR','CALI','REV')) submitted,
      count(*) filter(where status.code='CALI') graded from public.submissions s
      join tasks a on a.id=s.assignment_id join public.catalog_task_statuses status on status.id=s.task_status_id
      join enrolled on enrolled.student_id=s.student_id and enrolled.group_id=a.group_id and enrolled.academic_year_id=a.academic_year_id
    where s.institution_id=public.current_institution_id() and (p_student_id is null or s.student_id=p_student_id)
    group by s.assignment_id
  ) select jsonb_build_object('pending',count(*) filter(where
      case when p_student_id is not null then coalesce(counts.submitted,0)=0
      else a.published and (a.due_at is null or a.due_at>=now()) and (coalesce(roster.total,0)=0 or coalesce(counts.graded,0)<roster.total) end),
    'submitted',coalesce(sum(counts.submitted),0),'graded',coalesce(sum(counts.graded),0),
    'toGrade',coalesce(sum(counts.submitted-counts.graded),0)) into result
    from tasks a left join counts on counts.assignment_id=a.id left join roster on roster.group_id=a.group_id and roster.academic_year_id=a.academic_year_id;
  return result;
end $$;
revoke all on function public.assignment_counters(bigint) from public,anon;
grant execute on function public.assignment_counters(bigint) to authenticated;

-- Grading an exam must not silently create a homework evaluation. Existing
-- grading RPCs insert evaluations before grades; preserve their transaction.
create or replace function public.set_assignment_evaluation_kind() returns trigger
language plpgsql set search_path=public as $$
declare task public.assignments%rowtype; type_code text;
begin
  if new.assignment_id is null then return new; end if;
  select * into task from public.assignments where id=new.assignment_id;
  if not found or task.institution_id is distinct from new.institution_id then
    raise exception 'La evaluación no corresponde a la tarea.' using errcode='42501';
  end if;
  type_code:=case task.kind when 'exam' then 'EXM' when 'project' then 'PRO' when 'quiz' then 'QZ' when 'presentation' then 'EXP' else 'TAR' end;
  select id into new.evaluation_type_id from public.catalog_evaluation_types where code=type_code order by id limit 1;
  if new.evaluation_type_id is null then raise exception 'Tipo de evaluación no configurado.' using errcode='22023'; end if;
  return new;
end $$;
create trigger assignment_evaluation_kind before insert or update of assignment_id on public.evaluations
  for each row execute function public.set_assignment_evaluation_kind();

create or replace function public.sync_assignment_evaluation_kind() returns trigger
language plpgsql security definer set search_path=public as $$
declare type_key integer;
begin
  if new.kind is not distinct from old.kind then return null; end if;
  select id into type_key from public.catalog_evaluation_types where code=case new.kind
    when 'exam' then 'EXM' when 'project' then 'PRO' when 'quiz' then 'QZ' when 'presentation' then 'EXP' else 'TAR' end order by id limit 1;
  if type_key is null then raise exception 'Tipo de evaluación no configurado.' using errcode='22023'; end if;
  update public.evaluations set evaluation_type_id=type_key where assignment_id=new.id and institution_id=new.institution_id;
  return null;
end $$;
create trigger sync_assignment_kind after update of kind on public.assignments
  for each row execute function public.sync_assignment_evaluation_kind();
revoke all on function public.set_assignment_evaluation_kind(),public.sync_assignment_evaluation_kind() from public,anon,authenticated;

create or replace function public.class_enrollment_counts(p_class_ids bigint[])
returns table(class_id bigint,total bigint) language sql stable set search_path=public as $$
  select c.id,count(distinct e.student_id) filter(where student.active and status.code='ACT')
  from public.classes c
  left join public.enrollments e on e.group_id=c.group_id and e.academic_year_id=c.academic_year_id and e.institution_id=c.institution_id
  left join public.students student on student.id=e.student_id
  left join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id
  where c.institution_id=public.current_institution_id() and c.id=any(p_class_ids) group by c.id;
$$;
revoke all on function public.class_enrollment_counts(bigint[]) from public,anon;
grant execute on function public.class_enrollment_counts(bigint[]) to authenticated;
