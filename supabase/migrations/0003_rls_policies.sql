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
create or replace function auth.current_institution_id() returns bigint
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'institution_id', '')::bigint,
    (current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'institution_id')::bigint
  );
$$;

-- Helper: roles del usuario.
create or replace function auth.current_roles() returns text[]
language sql stable as $$
  select coalesce(
    array(select jsonb_array_elements_text(
      current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' -> 'roles'
    )),
    array[]::text[]
  );
$$;

create or replace function auth.has_role(role_code text) returns boolean
language sql stable as $$
  select role_code = any(auth.current_roles());
$$;

-- -----------------------------------------------------------------------------
-- Activar RLS y aplicar política tenant a tablas operativas.
-- -----------------------------------------------------------------------------
do $$
declare
  tbl text;
  tenant_tables text[] := array[
    'institutions','roles','users','user_roles','sessions','devices','login_attempts','audit_log',
    'persons','students','teachers','parents','parent_students','staff',
    'academic_years','academic_periods','grade_levels','sections','classrooms','subjects','groups',
    'classes','schedules','enrollments',
    'holidays','calendar_events',
    'class_sessions','attendances','attendance_justifications',
    'files',
    'assignments','assignment_files','submissions','submission_files',
    'grading_scales','grading_scale_ranges','evaluations','grades','period_grades',
    'report_cards','report_card_lines',
    'email_templates','notifications','notification_deliveries',
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
          using (id = auth.current_institution_id())
          with check (id = auth.current_institution_id())
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
          using (institution_id = auth.current_institution_id())
          with check (institution_id = auth.current_institution_id())
      $f$, tbl);
    end if;
  end loop;
end$$;

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
