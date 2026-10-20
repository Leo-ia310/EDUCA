import {withRequestKey} from './request-keys.mjs';
// E2E de permisos admin contra el backend real. Requiere una cuenta admin real:
//   E2E_ADMIN_EMAIL=... E2E_ADMIN_PASSWORD=... [API=http://localhost:3001/api] \
//     node scripts/admin_permissions_e2e.mjs
// Crea un perfil temporal (coordinador/director) y lo desactiva al terminar.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

if (!process.env.E2E_ADMIN_EMAIL || !process.env.E2E_ADMIN_PASSWORD) {
  console.error('Define E2E_ADMIN_EMAIL y E2E_ADMIN_PASSWORD.');
  process.exit(1);
}
const env = Object.fromEntries(
  readFileSync(fileURLToPath(new URL('../.env', import.meta.url)), 'utf8')
    .split(/\r?\n/)
    .filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
);
const API = process.env.API ?? 'http://localhost:3001/api';

async function login(email, password) {
  const r = await fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_ANON_KEY, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('login falló ' + email + ' ' + JSON.stringify(j).slice(0, 120));
  return j.access_token;
}
async function call(token, method, path, body) {
  body=withRequestKey(method,path,body);
  const r = await fetch(API + path, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  let j = {};
  try { j = await r.json(); } catch {}
  return { status: r.status, j };
}
const show = (label, r, extra) =>
  console.log(label.padEnd(46), r.status, extra ? extra(r.j) : (r.j.error?.message ?? r.j.message ?? ''));

const admin = await login(process.env.E2E_ADMIN_EMAIL, process.env.E2E_ADMIN_PASSWORD);
show('catálogo (admin)', await call(admin, 'GET', '/admin/permissions/catalog'), (j) => `${j.data.modules.length} módulos`);

const email = `perm.test.${Date.now()}@demo.com`;
const created = await call(admin, 'POST', '/admin/profiles', {
  fullName: 'Prueba Permisos',
  email,
  password: 'demo1234',
  roleCode: 'coordinator',
  permissions: ['students.edit', 'payments.view'],
});
show('crear coordinador restringido', created, (j) => JSON.stringify(j.data?.profile?.permissions));
const pid = created.j.data?.profile?.id;

show('permiso inválido', await call(admin, 'POST', '/admin/profiles', {
  fullName: 'X', email: 'x' + email, password: 'demo1234', roleCode: 'coordinator', permissions: ['foo.bar'],
}));
show('rol inválido (teacher)', await call(admin, 'POST', '/admin/profiles', {
  fullName: 'X', email: 'y' + email, password: 'demo1234', roleCode: 'teacher', permissions: [],
}));

const restricted = await login(email, 'demo1234');
show('restringido: alumnos (view auto-añadido) -> 200', await call(restricted, 'GET', '/admin/students?pageSize=1'));
show('restringido: maestros -> 403', await call(restricted, 'GET', '/admin/teachers?pageSize=1'));
show('restringido: roles -> 403', await call(restricted, 'GET', '/admin/roles'));
show('restringido: perfiles -> 403', await call(restricted, 'GET', '/admin/profiles'));
show('restringido: crear alumno -> 403', await call(restricted, 'POST', '/admin/students', { email: 'a@a.com' }));
show('restringido: borrar clase -> 403', await call(restricted, 'DELETE', '/admin/classes/1'));
show('restringido: instituciones -> 403', await call(restricted, 'GET', '/admin/institutions'));
show('restringido: directorio -> 200', await call(restricted, 'GET', '/admin/directory'), (j) => `${j.data?.people?.length ?? '?'} personas`);

// pagos / reportes / escalas: el backend exige permiso aunque se llame directo
show('restringido: anular cargo -> 403', await call(restricted, 'POST', '/payments/cancel-charge', { chargeId: 1 }));
show('restringido: registrar pago -> 403', await call(restricted, 'POST', '/business-api', { action: 'payments.register', payload: { chargeId: 1, amount: 1 } }));
show('restringido: generar boletín -> 403', await call(restricted, 'POST', '/reports/report-cards', { studentId: 1, academicPeriodId: 1 }));
show('restringido: ver boletín -> 403', await call(restricted, 'GET', '/reports/report-cards/1'));
show('restringido: configurar escala -> 403', await call(restricted, 'POST', '/grades/scales/upsert', {}));

// escalada directa por PostgREST: el trigger debe impedir auto-asignarse permisos
{
  const myRow = await fetch(`${env.SUPABASE_URL}/rest/v1/users?email=eq.${encodeURIComponent(email)}&select=id,admin_permissions`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${restricted}` },
  }).then((r) => r.json());
  const patch = await fetch(`${env.SUPABASE_URL}/rest/v1/users?id=eq.${myRow[0].id}`, {
    method: 'PATCH',
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${restricted}`, 'content-type': 'application/json', prefer: 'return=representation' },
    body: JSON.stringify({ admin_permissions: null }),
  });
  const patchBody = await patch.json();
  const after = await fetch(`${env.SUPABASE_URL}/rest/v1/users?id=eq.${myRow[0].id}&select=admin_permissions`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${restricted}` },
  }).then((r) => r.json());
  console.log('auto-quitarse restricciones (PostgREST)'.padEnd(46), patch.status, patchBody.message ?? '', '| permisos siguen:', JSON.stringify(after[0]?.admin_permissions));
}

// escalada por roles: darse el rol super_admin directo en PostgREST debe fallar
{
  const h = { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${restricted}`, 'content-type': 'application/json' };
  const me = await fetch(`${env.SUPABASE_URL}/rest/v1/users?email=eq.${encodeURIComponent(email)}&select=id,institution_id`, { headers: h }).then((r) => r.json());
  const sa = await fetch(`${env.SUPABASE_URL}/rest/v1/roles?code=eq.super_admin&select=id`, { headers: h }).then((r) => r.json());
  const ins = await fetch(`${env.SUPABASE_URL}/rest/v1/user_roles`, {
    method: 'POST', headers: h,
    body: JSON.stringify({ institution_id: me[0].institution_id, user_id: me[0].id, role_id: sa[0].id }),
  });
  const insBody = await ins.json().catch(() => ({}));
  console.log('darse super_admin (PostgREST)'.padEnd(46), ins.status, insBody.message ?? '');
}
show('restringido: asignar super_admin por API -> 403', await call(restricted, 'PATCH', '/admin/users/1', { roleCodes: ['super_admin'] }));

// lecturas directas a Supabase (RLS): cuentan filas visibles por tabla
async function visible(token, table) {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/${table}?select=id&limit=1`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${token}`, prefer: 'count=exact' },
  });
  const range = r.headers.get('content-range') ?? '*/?';
  return Number(range.split('/')[1]);
}
for (const table of ['charges', 'payments', 'grades', 'report_cards']) {
  const full = await visible(admin, table);
  const mine = await visible(restricted, table);
  console.log(`RLS ${table}: admin completo=${full}  restringido(payments.view)=${mine}`);
}

// actualizar permisos del perfil
const upd = await call(admin, 'PATCH', `/admin/profiles/${pid}`, { permissions: ['teachers.view', 'roles.view'], roleCode: 'director' });
show('admin actualiza permisos y rol', upd, (j) => `${j.data?.profile?.roleCode} ${JSON.stringify(j.data?.profile?.permissions)}`);
const restricted2 = await login(email, 'demo1234');
show('tras cambio: maestros -> 200', await call(restricted2, 'GET', '/admin/teachers?pageSize=1'));
show('tras cambio: alumnos -> 403', await call(restricted2, 'GET', '/admin/students?pageSize=1'));

// escalada: el director con roles.view no puede crear perfiles; ni concederse lo que no tiene
show('restringido no puede crear perfil -> 403', await call(restricted2, 'POST', '/admin/profiles', {
  fullName: 'Z', email: 'z' + email, password: 'demo1234', roleCode: 'coordinator', permissions: ['dashboard.view'],
}));
// el admin no puede cambiar su propio acceso
const me = (await call(admin, 'GET', '/admin/profiles')).j.data.profiles.find((p) => p.email === process.env.E2E_ADMIN_EMAIL);
show('admin editando su propio perfil -> 400', await call(admin, 'PATCH', `/admin/profiles/${me.id}`, { permissions: [] }));
console.log('listado perfiles:', (await call(admin, 'GET', '/admin/profiles')).j.data.profiles.map((p) => `${p.email}:${p.roleCode}:${p.customized ? p.permissions.length : 'todos'}`).join(' | '));

// limpieza: desactivar el perfil de prueba
show('limpieza: desactivar perfil prueba', await call(admin, 'PATCH', `/admin/profiles/${pid}`, { active: false }));
