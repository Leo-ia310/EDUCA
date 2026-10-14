// E2E de las preferencias de notificación por correo (GET/PATCH /notifications/preferences).
//   E2E_ADMIN_EMAIL=... E2E_ADMIN_PASSWORD=... [API=http://localhost:3001/api] \
//     node scripts/notification_preferences_e2e.mjs
// Crea un alumno temporal y lo archiva al terminar. Comprueba también en la BD.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { loadEnv, pgConfig } from './env.mjs';

if (!process.env.E2E_ADMIN_EMAIL || !process.env.E2E_ADMIN_PASSWORD) {
  console.error('Define E2E_ADMIN_EMAIL y E2E_ADMIN_PASSWORD.');
  process.exit(1);
}
const pg = createRequire(import.meta.url)('pg');
const env = Object.fromEntries(
  readFileSync(fileURLToPath(new URL('../.env', import.meta.url)), 'utf8').split(/\r?\n/).filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
);
const API = process.env.API ?? 'http://localhost:3001/api';
const tok = async (e, p) => (await (await fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: env.SUPABASE_ANON_KEY, 'content-type': 'application/json' }, body: JSON.stringify({ email: e, password: p }) })).json()).access_token;
const api = async (t, m, path, b) => { const r = await fetch(API + path, { method: m, headers: { authorization: `Bearer ${t}`, 'content-type': 'application/json' }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => ({})) }; };
let fails = 0;
const check = (label, ok, extra = '') => { if (!ok) fails++; console.log(`${ok ? 'OK  ' : 'FAIL'} ${label} ${extra}`); };

const db = new pg.Client(pgConfig(loadEnv()));
await db.connect();
const admin = await tok(process.env.E2E_ADMIN_EMAIL, process.env.E2E_ADMIN_PASSWORD);
const mail = `prefs.e2e.${Date.now()}@demo.com`;
const st = await api(admin, 'POST', '/admin/students', { firstName: 'Pref', lastName: 'E2E', email: mail, password: 'demo1234', studentCode: `PE-${Date.now()}` });
const uid = Number(st.j.data?.student?.user?.id);
const stId = st.j.data?.student?.id;
const student = await tok(mail, 'demo1234');
const inDb = async () => (await db.query('select email_notifications_enabled v from users where id = $1', [uid])).rows[0]?.v;
const mine = async () => (await api(student, 'GET', '/notifications/preferences')).j.data?.emailEnabled;
try {
  check('valor inicial: correo activo', (await mine()) === true && (await inDb()) === true);
  for (const v of [false, true, false, true]) {
    const p = await api(student, 'PATCH', '/notifications/preferences', { emailEnabled: v });
    check(`guardar emailEnabled=${v}`, p.s === 200 && p.j.data?.emailEnabled === v && (await mine()) === v && (await inDb()) === v);
  }
  // nombres equivalentes: no se ignoran en silencio
  await api(student, 'PATCH', '/notifications/preferences', { emailEnabled: false });
  const alias = await api(student, 'PATCH', '/notifications/preferences', { emailNotifications: true });
  check('alias emailNotifications=true se guarda', alias.s === 200 && (await inDb()) === true);
  // entradas inválidas
  check('payload vacío -> 400', (await api(student, 'PATCH', '/notifications/preferences', {})).s === 400);
  check('valor no booleano -> 400', (await api(student, 'PATCH', '/notifications/preferences', { emailEnabled: 'si' })).s === 400);
  check('el valor no cambió con las entradas inválidas', (await inDb()) === true);
  // aislamiento: el admin no modifica la preferencia del alumno
  const adminBefore = (await api(admin, 'GET', '/notifications/preferences')).j.data?.emailEnabled;
  await api(student, 'PATCH', '/notifications/preferences', { emailEnabled: false });
  check('la preferencia es por usuario', (await api(admin, 'GET', '/notifications/preferences')).j.data?.emailEnabled === adminBefore);
  check('sin sesión -> 401', (await fetch(API + '/notifications/preferences')).status === 401);
} finally {
  if (stId) await api(admin, 'DELETE', `/admin/students/${stId}`);
  await db.end();
}
console.log(fails === 0 ? 'RESULTADO: todo OK' : `RESULTADO: ${fails} fallo(s)`);
process.exit(fails === 0 ? 0 : 1);
