-- =============================================================================
-- Educa360 — 0005 FIX: recursión infinita en RLS de mensajería (error 42P17)
--
-- Problema: en 0003 la política `own_participation` de `conversation_participants`
-- se auto-referenciaba (subconsulta a la propia tabla dentro de su USING), lo que
-- provoca "infinite recursion detected in policy for relation
-- conversation_participants". `messages` heredaba el fallo por su join.
--
-- Solución estándar Supabase: mover la comprobación de pertenencia a una función
-- SECURITY DEFINER (se ejecuta como el dueño de la función → NO aplica RLS dentro,
-- por lo que no hay recursión). Las políticas la invocan sin volver a evaluar RLS.
--
-- Aplicar en el SQL Editor de Supabase (o vía CLI) DESPUÉS de 0003.
-- Es idempotente: se puede correr varias veces sin error.
-- =============================================================================

-- Helper: ids de conversaciones donde participa el usuario autenticado.
-- SECURITY DEFINER evita la recursión de RLS al leer conversation_participants.
create or replace function public.my_conversation_ids()
returns setof bigint
language sql
stable
security definer
set search_path = public
as $$
  select cp.conversation_id
  from conversation_participants cp
  join users u on u.id = cp.user_id
  where u.auth_user_id = auth.uid();
$$;

revoke all on function public.my_conversation_ids() from public;
grant execute on function public.my_conversation_ids() to authenticated;

-- ---------------------------------------------------------------------------
-- conversation_participants: ver mis filas y las de mis conversaciones,
-- sin auto-referencia recursiva.
-- ---------------------------------------------------------------------------
alter table conversation_participants enable row level security;
drop policy if exists tenant_isolation on conversation_participants;
drop policy if exists own_participation on conversation_participants;
drop policy if exists participants_visible on conversation_participants;
drop policy if exists participants_insert on conversation_participants;

create policy participants_visible on conversation_participants
  for select
  using (
    user_id in (select id from users where auth_user_id = auth.uid())
    or conversation_id in (select public.my_conversation_ids())
  );

create policy participants_insert on conversation_participants
  for insert
  with check (
    user_id in (select id from users where auth_user_id = auth.uid())
    or conversation_id in (select public.my_conversation_ids())
  );

-- ---------------------------------------------------------------------------
-- messages: solo mensajes de conversaciones donde participo.
-- ---------------------------------------------------------------------------
alter table messages enable row level security;
drop policy if exists tenant_isolation on messages;
drop policy if exists participants_only on messages;
drop policy if exists messages_select on messages;
drop policy if exists messages_insert on messages;

create policy messages_select on messages
  for select
  using (conversation_id in (select public.my_conversation_ids()));

create policy messages_insert on messages
  for insert
  with check (conversation_id in (select public.my_conversation_ids()));

-- ---------------------------------------------------------------------------
-- message_reads: acuses de lectura de mis conversaciones.
-- (0003 la dejaba en USING true; la afinamos a la pertenencia real.)
-- ---------------------------------------------------------------------------
alter table message_reads enable row level security;
drop policy if exists tenant_isolation on message_reads;
drop policy if exists message_reads_rw on message_reads;

create policy message_reads_rw on message_reads
  using (
    message_id in (
      select m.id from messages m
      where m.conversation_id in (select public.my_conversation_ids())
    )
  )
  with check (
    message_id in (
      select m.id from messages m
      where m.conversation_id in (select public.my_conversation_ids())
    )
  );
