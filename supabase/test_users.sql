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
  role_id int;
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
    -- 1) Auth user (idempotente vía on conflict).
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      raw_app_meta_data, raw_user_meta_data,
      email_confirmed_at, created_at, updated_at
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
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
      now(), now(), now()
    )
    on conflict (email) do update set
      encrypted_password = excluded.encrypted_password,
      raw_app_meta_data = excluded.raw_app_meta_data
    returning id into auth_uid;

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
    select id into role_id from roles where code = u[3] and is_system = true;
    if role_id is not null then
      insert into user_roles (user_id, role_id, institution_id)
      values (public_uid, role_id, inst_id)
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
