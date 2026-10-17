// =============================================================================
// create_super_admin.mjs - crea (o repara) una cuenta super_admin («developer»).
//
// Uso (desde backend/):
//   SUPER_ADMIN_EMAIL=dev@tuempresa.com node scripts/create_super_admin.mjs
//   (opcional) SUPER_ADMIN_NAME="Nombre" SUPER_ADMIN_INSTITUTION=EDU360 SUPER_ADMIN_PASSWORD=...
//
// Si no se indica SUPER_ADMIN_PASSWORD se genera una contraseña aleatoria y se guarda en
// backend/.super-admin.local (ignorado por git); no se imprime en pantalla. Cambiala luego desde
// «Mi cuenta». Es idempotente: si el correo ya existe, repara el perfil y NO toca su contraseña.
// Requiere SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY y las variables de BD de backend/.env.
// =============================================================================
import { randomBytes } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { createClient } from '@supabase/supabase-js';
import pg from 'pg';
import { BACKEND_DIR, loadEnv, pgConfig } from './env.mjs';

const env = loadEnv();
const email = (process.env.SUPER_ADMIN_EMAIL ?? '').trim().toLowerCase();
if (!email.includes('@')) {
  console.error('Define SUPER_ADMIN_EMAIL con el correo del super administrador.');
  process.exit(1);
}
const fullName = process.env.SUPER_ADMIN_NAME?.trim() || 'Super Administrador';
const institutionCode = process.env.SUPER_ADMIN_INSTITUTION?.trim() || 'EDU360';
const given = process.env.SUPER_ADMIN_PASSWORD;
const password = given || `${randomBytes(12).toString('base64url')}-Aa1`;
if (password.length < 10) {
  console.error('La contraseña debe tener al menos 10 caracteres.');
  process.exit(1);
}

const admin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const db = new pg.Client(pgConfig(env));
await db.connect();

try {
  const inst = (await db.query('select id from institutions where code = $1 and deleted_at is null', [institutionCode])).rows[0];
  if (!inst) throw new Error(`No existe la institución ${institutionCode}.`);
  const role = (await db.query("select id from roles where code = 'super_admin'")).rows[0];
  if (!role) throw new Error('No existe el rol super_admin.');

  let userRow = (await db.query('select id, auth_user_id from users where lower(email) = $1', [email])).rows[0];
  let authId = userRow?.auth_user_id ?? null;
  let created = false;

  if (!authId) {
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
      app_metadata: { institution_id: Number(inst.id), roles: ['super_admin'], provider: 'email', providers: ['email'] },
    });
    if (error || !data?.user) throw new Error(`No se pudo crear la cuenta de acceso: ${error?.message ?? 'sin detalle'}`);
    authId = data.user.id;
    created = true;
  }

  await db.query('begin');
  try {
    if (!userRow) {
      userRow = (await db.query(
        `insert into users (institution_id, auth_user_id, email, full_name, active, admin_permissions)
         values ($1, $2, $3, $4, true, null) returning id`,
        [inst.id, authId, email, fullName],
      )).rows[0];
    } else {
      await db.query('update users set active = true, deleted_at = null, admin_permissions = null where id = $1', [userRow.id]);
    }
    const has = (await db.query('select 1 from user_roles where user_id = $1 and role_id = $2', [userRow.id, role.id])).rowCount;
    if (!has) await db.query('insert into user_roles (user_id, role_id, institution_id) values ($1, $2, $3)', [userRow.id, role.id, inst.id]);
    await db.query('commit');
  } catch (e) {
    await db.query('rollback');
    if (created) await admin.auth.admin.deleteUser(authId).catch(() => undefined);
    throw e;
  }

  console.log(`Super administrador listo: ${email} (usuario ${userRow.id}, institución ${institutionCode}).`);
  if (created && !given) {
    const file = join(BACKEND_DIR, '.super-admin.local');
    writeFileSync(file, `email=${email}\npassword=${password}\n`, { mode: 0o600 });
    console.log(`Contraseña generada y guardada en ${file} (ignorado por git). Cámbiala desde «Mi cuenta».`);
  } else if (!created) {
    console.log('La cuenta ya existía: su contraseña no se modificó.');
  }
} finally {
  await db.end();
}
