-- =============================================================================
-- Educa360 — Usuarios de prueba
-- Crea 4 usuarios (uno por rol) en `auth.users` + `public.users` + rol.
-- Ejecutar UNA vez después de aplicar `schema_all.sql`.
-- Password de los 4: demo1234
-- =============================================================================

-- Función helper: crea un usuario auth + public + user_role. Idempotente.
do $$
declare
  inst_id bigint;
  auth_uid uuid;
  public_uid bigint;
  v_role_id int;
  demo_users text[][] := array[
    array['student@educa360.com', 'Julián Vargas', 'student'],
    array['teacher@educa360.com', 'Elena Ramírez', 'teacher'],
    array['parent@educa360.com',  'Marta Hernández', 'parent'],
    array['admin@educa360.com',   'Roberto Castillo', 'admin']
  ];
  u text[];
begin
  -- Institución demo (ya insertada por 0004_seed_catalogs.sql).
  select id into inst_id from institutions where code = 'EDU360';
  if inst_id is null then
    raise exception 'Institución EDU360 no existe. Ejecuta schema_all.sql primero.';
  end if;

  foreach u slice 1 in array demo_users loop
    -- 1) Auth user. Idempotente vía chequeo de existencia (el índice de email
    --    en auth.users es parcial y no sirve para ON CONFLICT).
    select id into auth_uid from auth.users where email = u[1];
    if auth_uid is null then
      auth_uid := gen_random_uuid();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        raw_app_meta_data, raw_user_meta_data,
        email_confirmed_at, created_at, updated_at,
        -- GoTrue escanea estas columnas como string no-nulo: deben ser '' (no NULL).
        confirmation_token, recovery_token, email_change_token_new, email_change
      )
      values (
        '00000000-0000-0000-0000-000000000000',
        auth_uid,
        'authenticated',
        'authenticated',
        u[1],
        crypt('demo1234', gen_salt('bf')),
        jsonb_build_object(
          'institution_id', inst_id,
          'roles', jsonb_build_array(u[3]),
          'provider', 'email',
          'providers', jsonb_build_array('email')
        ),
        '{}'::jsonb,
        now(), now(), now(),
        '', '', '', ''
      );
    else
      update auth.users set
        encrypted_password = crypt('demo1234', gen_salt('bf')),
        raw_app_meta_data = jsonb_build_object(
          'institution_id', inst_id,
          'roles', jsonb_build_array(u[3]),
          'provider', 'email',
          'providers', jsonb_build_array('email')
        )
      where id = auth_uid;
    end if;

    -- 1b) Identity de email (requerida por GoTrue v2 para login por password).
    insert into auth.identities (
      provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    )
    values (
      u[1], auth_uid,
      jsonb_build_object('sub', auth_uid::text, 'email', u[1], 'email_verified', true),
      'email', now(), now(), now()
    )
    on conflict (provider, provider_id) do nothing;

    -- 2) public.users
    insert into public.users (
      auth_user_id, institution_id, email, full_name, active
    )
    values (auth_uid, inst_id, u[1], u[2], true)
    on conflict (institution_id, email) do update set
      auth_user_id = excluded.auth_user_id,
      full_name = excluded.full_name
    returning id into public_uid;

    -- 3) rol
    select id into v_role_id from roles where code = u[3] and is_system = true;
    if v_role_id is not null then
      insert into user_roles (user_id, role_id, institution_id)
      values (public_uid, v_role_id, inst_id)
      on conflict (user_id, role_id, institution_id) do nothing;
    end if;

    raise notice 'Usuario listo: % (rol %)', u[1], u[3];
  end loop;
end$$;

-- Verificar:
select u.email, r.code as rol, u.full_name
  from public.users u
  join user_roles ur on ur.user_id = u.id
  join roles r on r.id = ur.role_id
 order by u.email;
