-- Los permisos administrativos (users.admin_permissions) solo los puede
-- escribir el backend con la service role. Las políticas RLS de `users` solo
-- aíslan por institución, así que sin este guard cualquier usuario autenticado
-- podría auto-asignarse permisos escribiendo directo en PostgREST.
-- Conexiones directas a Postgres (migraciones, mantenimiento) no se ven
-- afectadas: solo se bloquean los roles de API `authenticated` y `anon`.
create or replace function public.guard_admin_permissions()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.admin_permissions is not null then
        raise exception 'admin_permissions solo puede asignarlo el backend'
          using errcode = '42501';
      end if;
    elsif new.admin_permissions is distinct from old.admin_permissions then
      raise exception 'admin_permissions solo puede modificarlo el backend'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_admin_permissions on public.users;
create trigger trg_guard_admin_permissions
  before insert or update on public.users
  for each row execute function public.guard_admin_permissions();
