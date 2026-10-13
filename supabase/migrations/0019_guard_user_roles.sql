-- Los roles de un usuario (user_roles) solo los asigna el backend con la
-- service role. Las políticas RLS solo aíslan por institución: sin este guard
-- cualquier usuario autenticado podría darse el rol super_admin escribiendo
-- directo en PostgREST y saltarse los permisos administrativos.
-- Conexiones directas a Postgres (migraciones, seeds) no se ven afectadas.
create or replace function public.guard_user_roles()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    raise exception 'los roles solo puede asignarlos el backend'
      using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_user_roles on public.user_roles;
create trigger trg_guard_user_roles
  before insert or update or delete on public.user_roles
  for each row execute function public.guard_user_roles();
