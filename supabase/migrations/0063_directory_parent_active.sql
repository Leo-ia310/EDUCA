-- El directorio mostraba a todos los padres como activos (el SQL fijaba active=true) y no filtraba
-- los desactivados. parents no tiene columna "active": el estado vive en users.active (la cuenta),
-- que ya se actualiza al editar el padre (admin.service updatePeople). Aquí el listado lo lee de ahí.
CREATE OR REPLACE FUNCTION public.admin_people_page(p_institution_id bigint, p_resource text, p_search text DEFAULT NULL::text, p_active boolean DEFAULT NULL::boolean, p_page integer DEFAULT 1, p_page_size integer DEFAULT 50, p_id bigint DEFAULT NULL::bigint, p_group_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    union all select p.id,p.person_id,p.institution_id,coalesce((select u.active from public.users u where u.person_id=p.person_id and u.institution_id=p.institution_id and u.deleted_at is null limit 1),true),null::text,'parent' from public.parents p where p_resource in ('parents','all') and (p_institution_id is null or p.institution_id=p_institution_id)
  ), base as materialized (
    select r.*,lower(p.first_name||' '||p.last_name) sort_name from raw r
      join public.persons p on p.id=r.person_id and p.institution_id=r.institution_id and p.deleted_at is null
    where (p_id is null or r.id=p_id)
      and (p_group_id is null or r.role='student' and exists(select 1 from public.enrollments e
        join public.catalog_enrollment_statuses status on status.id=e.enrollment_status_id
        where e.student_id=r.id and e.institution_id=r.institution_id and e.group_id=p_group_id
          and e.academic_year_id in(select id from current_year) and status.code='ACT')) and (p_active is null or r.active=p_active)
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
end $function$;
