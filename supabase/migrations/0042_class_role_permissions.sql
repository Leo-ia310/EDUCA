-- A teacher grant is a resource grant even when that account also has a limited
-- administrative profile. It does not give that profile a tenant-wide bypass.
create or replace function public.teacher_class_permission(p_class_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.classes c join public.users u on u.institution_id=c.institution_id
    join public.teachers t on t.institution_id=u.institution_id and t.person_id=u.person_id and t.active
    where c.id=p_class_id and c.active and c.institution_id=public.current_institution_id() and u.auth_user_id=auth.uid()
      and public.user_has_role(u.id,'teacher') and (c.teacher_id=t.id or p_permission<>'collaborators.manage'
        and exists(select 1 from public.class_collaborators cc where cc.class_id=c.id and cc.institution_id=c.institution_id
          and cc.teacher_id=t.id and cc.teacher_user_id=u.id and cc.status='active' and p_permission=any(cc.permissions))))
$$;
revoke all on function public.teacher_class_permission(bigint,text) from public,anon;
grant execute on function public.teacher_class_permission(bigint,text) to authenticated;

create or replace function public.class_permission(p_class_id bigint,p_permission text) returns boolean
language sql stable security definer set search_path=public as $$
  select public.teacher_class_permission(p_class_id,p_permission) or exists(select 1 from public.classes c
    where c.id=p_class_id and c.active and c.institution_id=public.current_institution_id()
      and exists(select 1 from unnest(case p_permission
        when 'class.view' then array['classes.view','reports.view','schedules.view','dashboard.view']
        when 'students.view' then array['students.view','classes.view','reports.view']
        when 'assignments.review' then array['classes.view','reports.view']
        when 'assignments.grade' then array['reports.generate']
        when 'grades.write' then array['reports.generate']
        when 'assignments.create' then array['classes.edit']
        when 'attendance.write' then array['classes.edit']
        when 'collaborators.manage' then array['classes.edit']
        else array[]::text[] end) permission where public.administrative_permission(c.institution_id,permission)))
$$;

do $$ declare tbl text; cmd text; permission text; cid text; expr text; begin
  foreach tbl in array array['evaluations','grades','period_grades'] loop
    cid:=case when tbl='grades' then '(select class_id from public.evaluations where id=evaluation_id)' else 'class_id' end;
    foreach cmd in array array['select','insert','update','delete'] loop
      permission:=case when cmd='select' then 'reports.view' else 'reports.generate' end;
      expr:=format('(select public.admin_can(%L)) or public.teacher_class_permission(%s,%L)',permission,cid,
        case when cmd='select' then 'class.view' else 'grades.write' end);
      execute format('drop policy if exists admin_guard_%s on public.%I',cmd,tbl);
      if cmd='insert' then execute format('create policy admin_guard_insert on public.%I as restrictive for insert to authenticated with check(%s)',tbl,expr);
      elsif cmd='update' then execute format('create policy admin_guard_update on public.%I as restrictive for update to authenticated using(%s) with check(%s)',tbl,expr,expr);
      else execute format('create policy admin_guard_%s on public.%I as restrictive for %s to authenticated using(%s)',cmd,tbl,cmd,expr); end if;
    end loop;
  end loop;
end $$;
