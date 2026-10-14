-- Las notificaciones llegan a la app en tiempo real (Supabase Realtime):
-- sin estar publicada, la tabla no emite cambios y la bandeja solo se
-- actualizaría al reabrir la app.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and tablename = 'notifications'
     ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
