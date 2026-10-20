-- Lightweight anonymous probe exposes only the installed API contract version.
create function public.backend_readiness_v1() returns jsonb
language sql stable security definer set search_path=public as $$
 select jsonb_build_object('schemaVersion',53)
$$;
revoke all on function public.backend_readiness_v1() from public;
grant execute on function public.backend_readiness_v1() to anon,authenticated,service_role;
