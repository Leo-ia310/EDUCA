-- Módulo de horarios: además de bloques de clase, soporta recesos (por grupo o
-- para toda la institución) y turnos. Un horario de clase sigue ligado a
-- classes (grupo, materia, maestro); un receso no tiene clase.
alter table schedules
  add column if not exists kind     varchar(10) not null default 'class',
  add column if not exists label    varchar(80),
  add column if not exists shift    varchar(20),
  add column if not exists group_id bigint references groups(id) on delete cascade;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'schedules_kind_check') then
    alter table schedules add constraint schedules_kind_check
      check (kind in ('class', 'break'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'schedules_shift_check') then
    alter table schedules add constraint schedules_shift_check
      check (shift is null or shift in ('morning', 'afternoon', 'evening'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'schedules_class_required_check') then
    alter table schedules add constraint schedules_class_required_check
      check (kind <> 'class' or class_id is not null);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'schedules_time_order_check') then
    alter table schedules add constraint schedules_time_order_check
      check (start_time is null or end_time is null or start_time < end_time);
  end if;
end $$;

create index if not exists idx_schedules_institution_day_start
  on schedules(institution_id, weekday_id, start_time);
create index if not exists idx_schedules_class on schedules(class_id);
create index if not exists idx_schedules_group on schedules(group_id) where group_id is not null;

-- Escribir horarios exige el permiso administrativo (leer lo ve cualquiera de
-- la institución: alumnos, padres y maestros consultan su horario).
drop policy if exists admin_guard_insert on schedules;
drop policy if exists admin_guard_update on schedules;
drop policy if exists admin_guard_delete on schedules;
create policy admin_guard_insert on schedules as restrictive for insert to authenticated
  with check (public.admin_can('schedules.create'));
create policy admin_guard_update on schedules as restrictive for update to authenticated
  using (public.admin_can('schedules.edit')) with check (public.admin_can('schedules.edit'));
create policy admin_guard_delete on schedules as restrictive for delete to authenticated
  using (public.admin_can('schedules.delete'));
