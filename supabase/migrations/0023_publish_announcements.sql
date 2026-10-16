-- Publish the calendar entry and its announcement in the same transaction.
alter table public.announcements
  add column if not exists event_id bigint references public.calendar_events(id) on delete set null;

create or replace function public.publish_school_announcement(
  p_institution_id bigint,
  p_created_by bigint,
  p_title text,
  p_content text,
  p_start_at timestamptz,
  p_audience text
) returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_event public.calendar_events%rowtype;
  v_announcement public.announcements%rowtype;
begin
  if not exists (
    select 1 from public.users u
    join public.user_roles ur on ur.user_id = u.id
    join public.roles r on r.id = ur.role_id
    where u.auth_user_id = auth.uid()
      and u.id = p_created_by and u.institution_id = p_institution_id
      and u.active = true and u.deleted_at is null
      and r.code in ('teacher', 'admin', 'coordinator', 'director', 'super_admin')
  ) then
    raise exception 'No tienes permiso para publicar anuncios.' using errcode = '42501';
  end if;
  if p_title is null or length(btrim(p_title)) = 0 or length(p_title) > 150
     or p_content is null or length(btrim(p_content)) = 0 or length(p_content) > 2000
     or p_start_at is null or p_audience is null
     or p_audience not in ('all', 'parents', 'students', 'teachers', 'staff') then
    raise exception 'Datos de anuncio inválidos.' using errcode = '22023';
  end if;

  insert into public.calendar_events (institution_id, title, description, start_at, audience, type, created_by)
  values (p_institution_id, btrim(p_title), btrim(p_content), p_start_at, p_audience, 'announcement', p_created_by)
  returning * into v_event;

  insert into public.announcements (institution_id, event_id, title, content, kind, audience, published, published_at, created_by)
  values (p_institution_id, v_event.id, btrim(p_title), btrim(p_content), 'general', p_audience, true, now(), p_created_by)
  returning * into v_announcement;

  return jsonb_build_object('event', to_jsonb(v_event), 'announcement', to_jsonb(v_announcement));
end;
$$;

revoke all on function public.publish_school_announcement(bigint, bigint, text, text, timestamptz, text) from public, anon;
grant execute on function public.publish_school_announcement(bigint, bigint, text, text, timestamptz, text) to authenticated;

notify pgrst, 'reload schema';
