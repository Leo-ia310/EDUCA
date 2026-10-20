-- Service-only directory page. The HTTP layer verifies administrative module
-- grants and derives the target institution; clients cannot invoke this RPC.
create or replace function public.admin_people_page(p_institution_id bigint,p_resource text,
  p_search text default null,p_active boolean default null,p_page integer default 1,p_page_size integer default 50,p_id bigint default null,p_group_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_resource is null or p_resource not in ('students','teachers','parents','all') or p_page is null or p_page<1
    or p_page_size is null or p_page_size<1 or p_page_size>100 or length(p_search)>120 then
    raise exception 'Filtros de directorio inválidos.' using errcode='22023';
  end if;
  with current_year as materialized (select id from public.academic_years where (p_institution_id is null or institution_id=p_institution_id) and is_current and active),
  raw as (
    select s.id,s.person_id,s.institution_id,s.active,s.student_code code,'student' role from public.students s where p_resource in ('students','all') and (p_institution_id is null or s.institution_id=p_institution_id)
    union all select t.id,t.person_id,t.institution_id,t.active,t.teacher_code,'teacher' from public.teachers t where p_resource in ('teachers','all') and (p_institution_id is null or t.institution_id=p_institution_id)
    union all select p.id,p.person_id,p.institution_id,true,null::text,'parent' from public.parents p where p_resource in ('parents','all') and (p_institution_id is null or p.institution_id=p_institution_id)
  ), base as materialized (
    select r.*,lower(p.first_name||' '||p.last_name) sort_name from raw r
      join public.persons p on p.id=r.person_id and p.institution_id=r.institution_id and p.deleted_at is null
    where (p_id is null or r.id=p_id)
      and (p_group_id is null or r.role='student' and exists(select 1 from public.enrollments e
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id
        where e.student_id=r.id and e.institution_id=r.institution_id and e.group_id=p_group_id
          and e.academic_year_id in(select id from current_year) and status.code='ACT')) and (p_active is null or r.active=p_active or p_resource='parents')
      and (nullif(trim(p_search),'') is null or p.first_name||' '||p.last_name ilike '%'||trim(p_search)||'%'
        or p.email ilike '%'||trim(p_search)||'%' or p.document_number ilike '%'||trim(p_search)||'%'
        or coalesce(r.code,'') ilike '%'||trim(p_search)||'%')
  ), page as materialized (select * from base order by sort_name,id,role limit p_page_size offset (p_page::bigint-1)*p_page_size),
  enriched as (
    select p.*,
      case p.role when 'student' then (select to_jsonb(s) from public.students s where s.id=p.id)
        when 'teacher' then (select to_jsonb(t) from public.teachers t where t.id=p.id)
        else (select to_jsonb(parent) from public.parents parent where parent.id=p.id) end payload,
      (select to_jsonb(person) from public.persons person where person.id=p.person_id) person,
      enrollment.group_id,g.name group_name,
      coalesce((select jsonb_agg(jsonb_build_object('id',c.id::text,'groupId',c.group_id::text,'subject',s.name,'groupName',cg.name) order by c.id)
        from public.classes c left join public.subjects s on s.id=c.subject_id left join public.groups cg on cg.id=c.group_id
        where c.institution_id=p.institution_id and c.active and c.academic_year_id in(select id from current_year)
          and ((p.role='student' and c.group_id=enrollment.group_id) or (p.role='teacher' and c.teacher_id=p.id))),'[]'::jsonb) classes,
      coalesce((select jsonb_agg(jsonb_build_object('id',child.id::text,'name',person.first_name||' '||person.last_name) order by child.id)
        from public.parent_students ps join public.students child on child.id=ps.student_id and child.institution_id=p.institution_id
        join public.persons person on person.id=child.person_id and person.deleted_at is null
        where p.role='parent' and ps.parent_id=p.id),'[]'::jsonb) children
    from page p left join lateral (select e.group_id from public.enrollments e join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id
      where p.role='student' and e.student_id=p.id and e.institution_id=p.institution_id and e.academic_year_id in(select id from current_year) and status.code='ACT'
      order by e.id desc limit 1) enrollment on true left join public.groups g on g.id=enrollment.group_id
  ), total as (select count(*) n from base)
  select jsonb_build_object('items',coalesce((select jsonb_agg(payload||jsonb_build_object('persons',person,'role',role,
      'group_id',group_id,'group_name',group_name,'classes',classes,'children',children,
      'class_ids',coalesce((select jsonb_agg(item->>'id') from jsonb_array_elements(classes) item),'[]'::jsonb),
      'child_ids',coalesce((select jsonb_agg(item->>'id') from jsonb_array_elements(children) item),'[]'::jsonb)) order by sort_name,id,role) from enriched),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,
      'totalPages',ceil(total.n::numeric/p_page_size),'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_people_page(bigint,text,text,boolean,integer,integer,bigint,bigint) from public,anon,authenticated;
grant execute on function public.admin_people_page(bigint,text,text,boolean,integer,integer,bigint,bigint) to service_role;

create or replace function public.admin_directory_options(p_institution_id bigint,p_kind text,p_search text default null,
  p_page integer default 1,p_page_size integer default 50,p_include_ids bigint[] default '{}')
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_kind is null or p_kind not in ('students','teachers','parents','groups','classes') or p_institution_id is null
    or p_page is null or p_page<1 or p_page_size is null or p_page_size<1 or p_page_size>100
    or length(p_search)>120 or coalesce(array_length(p_include_ids,1),0)>100 then
    raise exception 'Filtros inválidos.' using errcode='22023';
  end if;
  with current_year as materialized (select id from public.academic_years where institution_id=p_institution_id and is_current and active),
  people as (
    select s.id,s.person_id from public.students s where p_kind='students' and s.institution_id=p_institution_id
    union all select t.id,t.person_id from public.teachers t where p_kind='teachers' and t.institution_id=p_institution_id
    union all select p.id,p.person_id from public.parents p where p_kind='parents' and p.institution_id=p_institution_id
  ), raw as materialized (
    select p.id,person.first_name||' '||person.last_name label,person.email subtitle,null::bigint group_id,null::bigint teacher_id,null::text room
      from people p join public.persons person on person.id=p.person_id and person.institution_id=p_institution_id and person.deleted_at is null
    union all select g.id,g.name,null,null,null,null from public.groups g
      where p_kind='groups' and g.institution_id=p_institution_id and g.active and g.academic_year_id in(select id from current_year)
    union all select c.id,coalesce(s.name,'Materia')||' ('||coalesce(g.name,'Sin salón')||')',null,c.group_id,c.teacher_id,room.name
      from public.classes c left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      left join public.classrooms room on room.id=g.classroom_id
      where p_kind='classes' and c.institution_id=p_institution_id and c.active and c.academic_year_id in(select id from current_year)
  ), matched as materialized (select * from raw where nullif(trim(p_search),'') is null or label ilike '%'||trim(p_search)||'%' or subtitle ilike '%'||trim(p_search)||'%'),
  page as (select * from matched order by lower(label),id limit p_page_size offset (p_page::bigint-1)*p_page_size),
  total as (select count(*) n from matched)
  select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',id::text,'label',label,'subtitle',subtitle,
    'groupId',group_id::text,'teacherId',teacher_id::text,'room',room) order by lower(label),id) from page),'[]'::jsonb),
    'selected',coalesce((select jsonb_agg(jsonb_build_object('id',id::text,'label',label)) from raw where id=any(p_include_ids)),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_directory_options(bigint,text,text,integer,integer,bigint[]) from public,anon,authenticated;
grant execute on function public.admin_directory_options(bigint,text,text,integer,integer,bigint[]) to service_role;

create or replace function public.admin_directory_counts(p_institution_id bigint) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce((select jsonb_object_agg(code,n) from (
    select 'student' code,count(*) n from public.students s join public.persons p on p.id=s.person_id where s.institution_id=p_institution_id and p.deleted_at is null
    union all select 'teacher',count(*) from public.teachers t join public.persons p on p.id=t.person_id where t.institution_id=p_institution_id and p.deleted_at is null
    union all select 'parent',count(*) from public.parents t join public.persons p on p.id=t.person_id where t.institution_id=p_institution_id and p.deleted_at is null
    union all select 'group',count(*) from public.groups g join public.academic_years y on y.id=g.academic_year_id
      where g.institution_id=p_institution_id and g.active and y.is_current and y.active
    union all select 'class',count(*) from public.classes c join public.academic_years y on y.id=c.academic_year_id
      where c.institution_id=p_institution_id and c.active and y.is_current and y.active
    union all select r.code,count(distinct u.id) from public.users u join public.user_roles ur on ur.user_id=u.id join public.roles r on r.id=ur.role_id
      where u.institution_id=p_institution_id and u.deleted_at is null and r.code in ('admin','super_admin','director','coordinator')
      and (r.institution_id is null or r.institution_id=p_institution_id) and (ur.institution_id is null or ur.institution_id=p_institution_id) group by r.code
  ) counts),'{}'::jsonb);
$$;
revoke all on function public.admin_directory_counts(bigint) from public,anon,authenticated;
grant execute on function public.admin_directory_counts(bigint) to service_role;

create or replace function public.admin_profiles_page(p_institution_id bigint,p_search text default null,p_page integer default 1,p_page_size integer default 50)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_institution_id is null or p_page is null or p_page<1 or p_page_size is null or p_page_size<1 or p_page_size>100 or length(p_search)>120 then
    raise exception 'Filtros inválidos.' using errcode='22023';
  end if;
  with base as materialized (
    select u.id from public.users u where u.institution_id=p_institution_id and u.deleted_at is null
      and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id
        and r.code in ('admin','coordinator','director') and (r.institution_id is null or r.institution_id=p_institution_id)
        and (ur.institution_id is null or ur.institution_id=p_institution_id))
      and (nullif(trim(p_search),'') is null or u.full_name ilike '%'||trim(p_search)||'%' or u.email ilike '%'||trim(p_search)||'%')
  ), page as (select u.id,u.institution_id,u.username,u.email,u.phone,u.full_name,u.active,u.admin_permissions,u.created_at,
    (select jsonb_agg(jsonb_build_object('roles',jsonb_build_object('code',r.code,'name',r.name)) order by r.code)
      from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id
        and (r.institution_id is null or r.institution_id=p_institution_id) and (ur.institution_id is null or ur.institution_id=p_institution_id)) user_roles
    from base b join public.users u on u.id=b.id order by lower(u.full_name),u.id limit p_page_size offset (p_page::bigint-1)*p_page_size),
  total as(select count(*) n from base)
  select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(page) order by lower(full_name),id) from page),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_profiles_page(bigint,text,integer,integer) from public,anon,authenticated;
grant execute on function public.admin_profiles_page(bigint,text,integer,integer) to service_role;

create or replace function public.admin_catalog_page(p_institution_id bigint,p_kind text default 'classes',p_search text default null,
  p_page integer default 1,p_page_size integer default 50,p_group_id bigint default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_institution_id is null or p_kind is null or p_kind not in ('groups','classes') or p_page is null or p_page<1
    or p_page_size is null or p_page_size<1 or p_page_size>100 or length(p_search)>120 then
    raise exception 'Filtros inválidos.' using errcode='22023';
  end if;
  with current_year as materialized (select id from public.academic_years where institution_id=p_institution_id and active and is_current),
  matched as materialized (
    select g.id,g.name sort_name from public.groups g where p_kind='groups' and g.institution_id=p_institution_id and g.active
      and g.academic_year_id in(select id from current_year) and (p_group_id is null or g.id=p_group_id)
      and (nullif(trim(p_search),'') is null or g.name ilike '%'||trim(p_search)||'%')
    union all select c.id,coalesce(s.name,'')||' '||coalesce(g.name,'') from public.classes c
      left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      left join public.teachers t on t.id=c.teacher_id left join public.persons person on person.id=t.person_id
      where p_kind='classes' and c.institution_id=p_institution_id and c.active and c.academic_year_id in(select id from current_year)
        and (p_group_id is null or c.group_id=p_group_id)
        and (nullif(trim(p_search),'') is null or s.name ilike '%'||trim(p_search)||'%' or g.name ilike '%'||trim(p_search)||'%'
          or person.first_name||' '||person.last_name ilike '%'||trim(p_search)||'%')
  ), page as materialized (select * from matched order by lower(sort_name),id limit p_page_size offset (p_page::bigint-1)*p_page_size),
  class_page as materialized (select c.* from page p join public.classes c on p_kind='classes' and c.id=p.id),
  group_page as materialized (select g.* from public.groups g where g.institution_id=p_institution_id
    and ((p_kind='groups' and g.id in(select id from page)) or (p_kind='classes' and (g.id in(select group_id from class_page)
      or (g.id=p_group_id and g.active and g.academic_year_id in(select id from current_year)))))),
  total as (select count(*) n from matched)
  select jsonb_build_object('classes',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('subjects',jsonb_build_object('name',coalesce(s.name,'Materia')),
      'groups',jsonb_build_object('name',coalesce(g.name,'Sin salón'),'classrooms',jsonb_build_object('name',room.name))) order by lower(coalesce(s.name,'')||' '||coalesce(g.name,'')),c.id)
      from class_page c left join public.subjects s on s.id=c.subject_id left join public.groups g on g.id=c.group_id
      left join public.classrooms room on room.id=g.classroom_id),'[]'::jsonb),
    'groups',coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('classrooms',
      (select jsonb_build_object('name',room.name) from public.classrooms room where room.id=g.classroom_id),
      'student_count',(select count(distinct e.student_id) from public.enrollments e join public.students student on student.id=e.student_id
        join public.persons person on person.id=student.person_id and person.deleted_at is null
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id where e.institution_id=p_institution_id and e.group_id=g.id and e.academic_year_id=g.academic_year_id and status.code='ACT'),
      'class_count',(select count(*) from public.classes c where c.institution_id=p_institution_id and c.group_id=g.id and c.academic_year_id=g.academic_year_id and c.active)) order by lower(g.name),g.id) from group_page g),'[]'::jsonb),
    'people',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'institution_id',t.institution_id,'person_id',t.person_id,'role','teacher','active',t.active,'group_id',null,'child_ids','[]'::jsonb,'class_ids','[]'::jsonb,
      'persons',jsonb_build_object('id',person.id,'first_name',person.first_name,'last_name',person.last_name,'email',person.email,'phone',person.phone)) order by t.id)
      from public.teachers t join public.persons person on person.id=t.person_id where t.institution_id=p_institution_id and t.id in(select teacher_id from class_page)),'[]'::jsonb),
    'pageInfo',jsonb_build_object('page',p_page,'pageSize',p_page_size,'total',total.n,'totalPages',ceil(total.n::numeric/p_page_size),
      'hasNextPage',p_page::bigint*p_page_size<total.n,'hasPreviousPage',p_page>1)) into result from total;
  return result;
end $$;
revoke all on function public.admin_catalog_page(bigint,text,text,integer,integer,bigint) from public,anon,authenticated;
grant execute on function public.admin_catalog_page(bigint,text,text,integer,integer,bigint) to service_role;
