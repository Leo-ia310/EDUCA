-- A small revision row per institution replaces permission polling by clients.
-- No names, rules or protected academic data are sent over this channel.
create table if not exists public.portal_access_revisions (
 institution_id bigint primary key references public.institutions(id) on delete cascade,
 revision bigint not null default 1,
 updated_at timestamptz not null default now()
);
alter table public.portal_access_revisions enable row level security;
revoke all on public.portal_access_revisions from public,anon,authenticated;
grant select on public.portal_access_revisions to authenticated;
grant all on public.portal_access_revisions to service_role;
drop policy if exists portal_revision_read on public.portal_access_revisions;
create policy portal_revision_read on public.portal_access_revisions for select to authenticated using (
 institution_id=public.current_institution_id() and exists(select 1 from public.users u
 where u.auth_user_id=auth.uid() and u.institution_id=portal_access_revisions.institution_id and u.active and u.deleted_at is null)
);
create or replace function public.bump_portal_access_revision() returns trigger
language plpgsql security definer set search_path=public as $$
declare inst bigint;
begin
 inst:=case when tg_op='DELETE' then old.institution_id else new.institution_id end;
 -- Cascading institution deletion must not recreate its revision row.
 if not exists(select 1 from public.institutions where id=inst) then return null; end if;
 insert into public.portal_access_revisions(institution_id) values(inst)
 on conflict(institution_id) do update set revision=portal_access_revisions.revision+1,updated_at=now();
 return null;
end $$;
revoke all on function public.bump_portal_access_revision() from public,anon,authenticated;
drop trigger if exists portal_permission_changed on public.portal_permission_rules;
create trigger portal_permission_changed after insert or update or delete on public.portal_permission_rules
for each row execute function public.bump_portal_access_revision();
drop trigger if exists portal_visibility_changed on public.grade_visibility_rules;
create trigger portal_visibility_changed after insert or update or delete on public.grade_visibility_rules
for each row execute function public.bump_portal_access_revision();
insert into public.portal_access_revisions(institution_id) select id from public.institutions on conflict do nothing;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
  select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='portal_access_revisions'
 ) then alter publication supabase_realtime add table public.portal_access_revisions; end if;
end $$;
notify pgrst,'reload schema';
