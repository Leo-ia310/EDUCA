-- Permisos administrativos aplicados también a nivel de datos (RLS).
-- Parte de la app lee Supabase directo con el JWT del usuario (pagos, notas,
-- boletines), sin pasar por el backend; estas políticas RESTRICTIVE hacen que
-- un perfil admin con lista explícita (users.admin_permissions) solo vea y
-- modifique lo que tiene concedido. No afectan a quien no tiene lista
-- (admin histórico, maestros, alumnos, padres) ni a la service role.

create or replace function public.admin_can(code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select case
      when u.admin_permissions is null then true
      -- quien también es maestro/alumno/padre/super_admin no se restringe aquí
      when exists (
        select 1
        from user_roles ur
        join roles r on r.id = ur.role_id
        where ur.user_id = u.id
          and r.code in ('teacher', 'student', 'parent', 'super_admin')
      ) then true
      else code = any (u.admin_permissions)
    end
    from users u
    where u.auth_user_id = auth.uid() and u.deleted_at is null
    limit 1
  ), true);
$$;

do $$
declare
  tbl text;
begin
  -- Pagos: ver / crear / editar / cancelar (eliminar)
  foreach tbl in array array['charges', 'payments', 'payment_concepts'] loop
    execute format('drop policy if exists admin_guard_select on %I', tbl);
    execute format('drop policy if exists admin_guard_insert on %I', tbl);
    execute format('drop policy if exists admin_guard_update on %I', tbl);
    execute format('drop policy if exists admin_guard_delete on %I', tbl);
    execute format($p$create policy admin_guard_select on %I as restrictive for select to authenticated using (public.admin_can('payments.view'))$p$, tbl);
    execute format($p$create policy admin_guard_insert on %I as restrictive for insert to authenticated with check (public.admin_can('payments.create'))$p$, tbl);
    execute format($p$create policy admin_guard_update on %I as restrictive for update to authenticated using (public.admin_can('payments.edit')) with check (public.admin_can('payments.edit'))$p$, tbl);
    execute format($p$create policy admin_guard_delete on %I as restrictive for delete to authenticated using (public.admin_can('payments.cancel'))$p$, tbl);
  end loop;

  -- Notas y boletines: ver / generar
  foreach tbl in array array[
    'evaluations', 'grades', 'period_grades', 'report_cards', 'report_card_lines'
  ] loop
    execute format('drop policy if exists admin_guard_select on %I', tbl);
    execute format('drop policy if exists admin_guard_insert on %I', tbl);
    execute format('drop policy if exists admin_guard_update on %I', tbl);
    execute format('drop policy if exists admin_guard_delete on %I', tbl);
    execute format($p$create policy admin_guard_select on %I as restrictive for select to authenticated using (public.admin_can('reports.view'))$p$, tbl);
    execute format($p$create policy admin_guard_insert on %I as restrictive for insert to authenticated with check (public.admin_can('reports.generate'))$p$, tbl);
    execute format($p$create policy admin_guard_update on %I as restrictive for update to authenticated using (public.admin_can('reports.generate')) with check (public.admin_can('reports.generate'))$p$, tbl);
    execute format($p$create policy admin_guard_delete on %I as restrictive for delete to authenticated using (public.admin_can('reports.generate'))$p$, tbl);
  end loop;

  -- Configuración (escalas e institución): escribir exige settings.edit
  foreach tbl in array array[
    'institution_settings', 'grading_scales', 'grading_scale_ranges'
  ] loop
    execute format('drop policy if exists admin_guard_insert on %I', tbl);
    execute format('drop policy if exists admin_guard_update on %I', tbl);
    execute format('drop policy if exists admin_guard_delete on %I', tbl);
    execute format($p$create policy admin_guard_insert on %I as restrictive for insert to authenticated with check (public.admin_can('settings.edit'))$p$, tbl);
    execute format($p$create policy admin_guard_update on %I as restrictive for update to authenticated using (public.admin_can('settings.edit')) with check (public.admin_can('settings.edit'))$p$, tbl);
    execute format($p$create policy admin_guard_delete on %I as restrictive for delete to authenticated using (public.admin_can('settings.edit'))$p$, tbl);
  end loop;
end $$;
