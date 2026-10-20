-- Cache ONLY statement-invariant helpers. Row-dependent class/student grants
-- remain evaluated against each resource; there is no cache across requests.
do $$
declare p record; expr text; check_expr text; pattern text;
begin
  for p in select pol.polname,n.nspname,c.relname,pg_get_expr(pol.polqual,pol.polrelid) qual,
      pg_get_expr(pol.polwithcheck,pol.polrelid) check_qual
    from pg_policy pol join pg_class c on c.oid=pol.polrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname in('public','storage') loop
    expr:=p.qual; check_expr:=p.check_qual;
    foreach pattern in array array[
      '\m(public\.)?auth_2fa_session_allowed\(\)',
      '\m(public\.)?current_institution_id\(\)',
      '\m(public\.)?class_admin_actor\(\)',
      '\m(public\.)?is_teacher_actor\(\)',
      '\mauth\.uid\(\)', '\mauth\.jwt\(\)',
      '\m(public\.)?admin_can\(''[^'']+''::text\)',
      '\m(public\.)?portal_can\(''[^'']+''::text\)'
    ] loop
      expr:=regexp_replace(expr,pattern,'(select \& )','g');
      check_expr:=regexp_replace(check_expr,pattern,'(select \& )','g');
    end loop;
    if expr is distinct from p.qual or check_expr is distinct from p.check_qual then
      execute format('alter policy %I on %I.%I %s %s',p.polname,p.nspname,p.relname,
        case when expr is null then '' else 'using ('||expr||')' end,
        case when check_expr is null then '' else 'with check ('||check_expr||')' end);
    end if;
  end loop;
end $$;

-- Match actual filters/order or relationship lookups. Existing leading-key
-- indexes are retained; none is dropped on speculation about other clients.
create index parent_students_parent_student on public.parent_students(parent_id,student_id);
create index teachers_institution_person on public.teachers(institution_id,person_id);
create index parents_institution_person on public.parents(institution_id,person_id);
create index students_institution_person on public.students(institution_id,person_id);
create index notifications_user_recent on public.notifications(user_id,created_at desc,id desc);
create index enrollments_current_roster on public.enrollments(institution_id,academic_year_id,group_id,enrollment_status_id,student_id);
create index classes_current_teacher on public.classes(institution_id,academic_year_id,teacher_id,id) where active;
create index persons_full_name_search on public.persons using gin ((first_name||' '||last_name) gin_trgm_ops) where deleted_at is null;
