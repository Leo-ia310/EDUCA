// =============================================================================
// e2e_smoke.mjs — smoke test del MODO CONECTADO, determinista (sin UI).
//
// Inicia sesión con cada usuario demo vía la API de Auth y verifica que:
//  - el resolver de identidad del backend devuelve la entidad correcta,
//  - las lecturas clave (clases, tareas, conversaciones) respetan RLS y traen datos.
// Es la alternativa fiable a manejar el canvas de Flutter web con un navegador.
//
// Uso:  node e2e_smoke.mjs
// =============================================================================
import { loadEnv } from './env.mjs';

const env = loadEnv();
const URL = env.SUPABASE_URL;
const ANON = env.SUPABASE_ANON_KEY;
if (!URL || !ANON) { console.error('Faltan SUPABASE_URL/ANON_KEY en backend/.env'); process.exit(1); }

let pass = 0, fail = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? '✓ PASS' : '✗ FAIL'}  ${name}${detail ? '  ('+detail+')' : ''}`);
  ok ? pass++ : fail++;
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchRetry(url, opts, tries = 3) {
  for (let i = 0; i < tries; i++) {
    try {
      return await fetch(url, opts);
    } catch (e) {
      if (i === tries - 1) return null;
      await sleep(500 * (i + 1));
    }
  }
  return null;
}

async function login(email) {
  const r = await fetchRetry(`${URL}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: ANON, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: 'demo1234' }),
  });
  if (!r) return null;
  const j = await r.json();
  return j.access_token || null;
}

async function rpc(token, fn, body = {}) {
  const r = await fetchRetry(`${URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return r && r.ok ? r.json() : null;
}

async function rest(token, path) {
  const r = await fetchRetry(`${URL}/rest/v1/${path}`, {
    headers: { apikey: ANON, Authorization: `Bearer ${token}` },
  });
  return r && r.ok ? r.json() : null;
}

const roles = [
  { email: 'teacher@educa360.com', resolver: 'current_teacher_id' },
  { email: 'student@educa360.com', resolver: 'current_student_id' },
  { email: 'parent@educa360.com',  resolver: 'current_parent_id' },
  { email: 'admin@educa360.com',   resolver: null },
];

console.log(`\nSmoke test conectado → ${URL}\n`);
for (const role of roles) {
  const token = await login(role.email);
  check(`login ${role.email}`, !!token);
  if (!token) continue;
  if (role.resolver) {
    const id = await rpc(token, role.resolver);
    check(`${role.resolver}`, typeof id === 'number' && id > 0, `id=${id}`);
  }
  const classes = await rest(token, 'classes?select=id&institution_id=eq.1');
  check(`${role.email} lee classes`, Array.isArray(classes), `n=${classes?.length ?? 'null'}`);
  const convos = await rest(token, 'conversation_participants?select=conversation_id');
  check(`${role.email} lee sus conversaciones`, Array.isArray(convos), `n=${convos?.length ?? 'null'}`);

  // Datos que alimentan los dashboards conectados (bajo RLS).
  if (role.email.startsWith('student')) {
    const grades = await rest(token, 'grades?select=score');
    check('dashboard student: lee sus notas', Array.isArray(grades) && grades.length > 0, `n=${grades?.length ?? 'null'}`);
    const sched = await rest(token, 'schedules?select=id');
    check('dashboard student: lee horario', Array.isArray(sched), `n=${sched?.length ?? 'null'}`);
    const avg = await rest(token, 'student_weighted_averages?select=weighted_pct');
    check('dashboard student: promedio ponderado (vista)', Array.isArray(avg), `n=${avg?.length ?? 'null'}`);
  }
  if (role.email.startsWith('teacher')) {
    const asg = await rest(token, 'assignments?select=id&deleted_at=is.null');
    check('dashboard teacher: lee tareas', Array.isArray(asg) && asg.length > 0, `n=${asg?.length ?? 'null'}`);
    const evals = await rest(token, 'evaluations?select=id');
    check('dashboard teacher: lee evaluaciones', Array.isArray(evals), `n=${evals?.length ?? 'null'}`);
  }
  if (role.email.startsWith('parent')) {
    const kids = await rest(token, 'parent_students?select=student_id');
    check('dashboard parent: lee sus hijos', Array.isArray(kids) && kids.length > 0, `n=${kids?.length ?? 'null'}`);
    const ann = await rest(token, 'announcements?select=title&published=eq.true');
    check('dashboard parent: lee anuncios', Array.isArray(ann), `n=${ann?.length ?? 'null'}`);
  }
  if (role.email.startsWith('admin')) {
    const ann = await rest(token, 'announcements?select=title&published=eq.true');
    check('dashboard admin: lee anuncios', Array.isArray(ann) && ann.length > 0, `n=${ann?.length ?? 'null'}`);
    const teachers = await rest(token, 'teachers?select=id&institution_id=eq.1');
    check('dashboard admin: lee maestros', Array.isArray(teachers), `n=${teachers?.length ?? 'null'}`);
    const students = await rest(token, 'students?select=id&institution_id=eq.1');
    check('dashboard admin: lee estudiantes', Array.isArray(students), `n=${students?.length ?? 'null'}`);
    const events = await rest(token, 'calendar_events?select=id&institution_id=eq.1');
    check('dashboard admin: lee eventos', Array.isArray(events) && events.length > 0, `n=${events?.length ?? 'null'}`);
  }
}

console.log(`\n${pass} PASS · ${fail} FAIL\n`);
process.exit(fail ? 1 : 0);
