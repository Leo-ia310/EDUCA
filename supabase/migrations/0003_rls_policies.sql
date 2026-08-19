-- =============================================================================
-- Educa360 — 0003 ROW LEVEL SECURITY (multi-tenant)
-- Política base: cada tabla operativa solo es visible/escribible si
-- institution_id coincide con el claim `institution_id` del JWT del usuario.
--
-- Para que esto funcione, al confirmar el alta o crear el usuario en Supabase,
-- almacenar en `auth.users.raw_app_meta_data` los campos:
--   { "institution_id": 1, "roles": ["teacher"] }
-- =============================================================================

-- Helper: lee el institution_id del JWT.
-- NOTA: se crean en el schema `public` (no en `auth`) porque el rol de conexión
-- no tiene permiso CREATE sobre el schema `auth` en Supabase.
create or replace function public.current_institution_id() returns bigint
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'institution_id', '')::bigint,
    (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'institution_id')::bigint
  );
$$;

-- Helper: roles del usuario.
create or replace function public.current_roles() returns text[]
language sql stable as $$
  select coalesce(
    array(select jsonb_array_elements_text(
      current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' -> 'roles'
    )),
    array[]::text[]
  );
$$;

create or replace function public.has_role(role_code text) returns boolean
language sql stable as $$
  select role_code = any(public.current_roles());
$$;

-- -----------------------------------------------------------------------------
-- Activar RLS y aplicar política tenant a tablas operativas.
-- -----------------------------------------------------------------------------
do $$
declare
  tbl text;
  tenant_tables text[] := array[
    'institutions','roles','users','user_roles','audit_log',
    'persons','students','teachers','parents','staff',
    'academic_years','academic_periods','grade_levels','sections','classrooms','subjects','groups',
    'classes','schedules','enrollments',
    'holidays','calendar_events',
    'class_sessions','attendances','attendance_justifications',
    'files',
    'assignments','assignment_files','submissions','submission_files',
    'grading_scales','grading_scale_ranges','evaluations','grades','period_grades',
    'report_cards','report_card_lines',
    'email_templates','notifications',
    'announcements','announcement_reads',
    'conversations','conversation_participants','messages','message_reads',
    'payment_concepts','charges','payments',
    'sync_queue','change_log','institution_settings'
  ];
begin
  foreach tbl in array tenant_tables loop
    execute format('alter table %I enable row level security', tbl);
    execute format('drop policy if exists tenant_isolation on %I', tbl);
    -- institutions usa su propio id; el resto usa institution_id.
    if tbl = 'institutions' then
      execute format($f$
        create policy tenant_isolation on %I
          using (id = public.current_institution_id())
          with check (id = public.current_institution_id())
      $f$, tbl);
    elsif tbl in ('grading_scale_ranges','assignment_files','submission_files','report_card_lines',
                   'conversation_participants','messages','message_reads','announcement_reads') then
      -- Estas no llevan institution_id directo; se restringen vía join al padre
      -- mediante security definer functions o vistas. Aquí dejamos USING true y
      -- confiamos en políticas más finas (se afinará en 0004).
      execute format('create policy tenant_isolation on %I using (true) with check (true)', tbl);
    else
      execute format($f$
        create policy tenant_isolation on %I
          using (institution_id = public.current_institution_id())
          with check (institution_id = public.current_institution_id())
      $f$, tbl);
    end if;
  end loop;
end$$;

-- Roles y permisos globales del sistema (institution_id null): lectura para
-- cualquier usuario autenticado, además del aislamiento por institución de arriba.
-- Sin esto, los roles base sembrados (super_admin, teacher, ...) serían invisibles.
drop policy if exists roles_global_read on roles;
create policy roles_global_read on roles for select using (institution_id is null);

-- -----------------------------------------------------------------------------
-- Catálogos globales: lectura libre, sin escritura.
-- -----------------------------------------------------------------------------
do $$
declare
  tbl text;
  catalog_tables text[] := array[
    'catalog_countries','catalog_currencies','catalog_document_types','catalog_genders',
    'catalog_relationships','catalog_education_levels','catalog_weekdays',
    'catalog_attendance_statuses','catalog_evaluation_types','catalog_task_statuses',
    'catalog_enrollment_statuses','catalog_notification_channels','catalog_notification_types',
    'catalog_file_types','permissions','role_permissions'
  ];
begin
  foreach tbl in array catalog_tables loop
    execute format('alter table %I enable row level security', tbl);
    execute format('drop policy if exists public_read on %I', tbl);
    execute format('create policy public_read on %I for select using (true)', tbl);
  end loop;
end$$;

-- -----------------------------------------------------------------------------
-- Tablas sin institution_id directo: se aíslan por join a la tabla padre que sí
-- lo lleva (users / students / notifications), respetando el mismo tenant.
-- -----------------------------------------------------------------------------
-- sessions, devices, login_attempts -> users.institution_id
do $$
declare tbl text;
begin
  foreach tbl in array array['sessions','devices','login_attempts'] loop
    execute format('alter table %I enable row level security', tbl);
    execute format('drop policy if exists tenant_isolation on %I', tbl);
    execute format($f$
      create policy tenant_isolation on %I
        using (user_id in (select id from users where institution_id = public.current_institution_id()))
        with check (user_id in (select id from users where institution_id = public.current_institution_id()))
    $f$, tbl);
  end loop;
end$$;

-- parent_students -> students.institution_id
alter table parent_students enable row level security;
drop policy if exists tenant_isolation on parent_students;
create policy tenant_isolation on parent_students
  using (student_id in (select id from students where institution_id = public.current_institution_id()))
  with check (student_id in (select id from students where institution_id = public.current_institution_id()));

-- notification_deliveries -> notifications.institution_id
alter table notification_deliveries enable row level security;
drop policy if exists tenant_isolation on notification_deliveries;
create policy tenant_isolation on notification_deliveries
  using (notification_id in (select id from notifications where institution_id = public.current_institution_id()))
  with check (notification_id in (select id from notifications where institution_id = public.current_institution_id()));

-- -----------------------------------------------------------------------------
-- Política específica para mensajería: el usuario solo ve mensajes de
-- conversaciones donde participa.
-- -----------------------------------------------------------------------------
drop policy if exists tenant_isolation on messages;
create policy participants_only on messages
  using (
    conversation_id in (
      select conversation_id from conversation_participants cp
      join users u on u.id = cp.user_id
      where u.auth_user_id = auth.uid()
    )
  );

drop policy if exists tenant_isolation on conversation_participants;
create policy own_participation on conversation_participants
  using (
    user_id in (select id from users where auth_user_id = auth.uid())
    or conversation_id in (
      select conversation_id from conversation_participants cp2
      join users u on u.id = cp2.user_id
      where u.auth_user_id = auth.uid()
    )
  );

-- -----------------------------------------------------------------------------
-- Storage: el bucket "files" usa la convención de carpeta
--   {institution_id}/{folder}/{filename}
-- y se valida con un policy que extrae el primer segmento del path.
-- -----------------------------------------------------------------------------
-- (Se aplica desde la consola de Supabase Storage o vía:)
--   create policy "files_tenant_isolation"
--     on storage.objects for select using (
--       bucket_id = 'files'
--       and (storage.foldername(name))[1] = auth.current_institution_id()::text
--     );
