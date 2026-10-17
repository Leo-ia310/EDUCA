// =============================================================================
// check_api_schemas.mjs - verifica que las respuestas REALES del backend cumplan los esquemas tipados
// de backend/src/lib/api-schemas.ts (los que van en docs/openapi.json y de los que la web genera tipos).
//
//   cd backend && npm run docs:apis          (regenera docs/openapi.json)
//   CHECK_USER=admin@x CHECK_PASSWORD=... node scripts/check_api_schemas.mjs
//
// Necesita el backend corriendo (API_BASE_URL, por defecto http://localhost:3001) y una cuenta de
// administración. Crea una mini escuela temporal (salones «CHK …»: maestro, 2 alumnos, padre, tarea con
// archivo, entrega, asistencia, cargo, horario), llama a cada endpoint con el rol que corresponde,
// valida con Ajv y al final borra lo creado con scripts/cleanup_e2e_data.mjs «CHK ».
// Sale con código 1 si algún esquema no coincide o si un endpoint tipado no tiene caso de prueba.
// =============================================================================
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import Ajv from 'ajv';
import { BACKEND_DIR } from './env.mjs';

const BASE = (process.env.API_BASE_URL ?? 'http://localhost:3001') + '/api';
const USER = process.env.CHECK_USER, PASS = process.env.CHECK_PASSWORD;
if (!USER || !PASS) { console.error('Define CHECK_USER y CHECK_PASSWORD (una cuenta de administración).'); process.exit(1); }

const spec = JSON.parse(readFileSync(join(BACKEND_DIR, '..', 'docs', 'openapi.json'), 'utf8'));
const ajv = new Ajv({ strict: false, allErrors: false });

/** key «MÉTODO /api/ruta/:param» -> esquema del cuerpo 200 */
const typed = new Map();
for (const [path, ops] of Object.entries(spec.paths)) {
  for (const [method, op] of Object.entries(ops)) {
    const schema = op.responses?.['200']?.content?.['application/json']?.schema;
    if (schema?.properties?.data) typed.set(`${method.toUpperCase()} ${path.replace(/\{(\w+)\}/g, ':$1')}`, schema);
  }
}

const tokens = {};
async function call(role, method, path, body) {
  const res = await fetch(BASE + path, {
    method, headers: { 'content-type': 'application/json', ...(tokens[role] ? { authorization: `Bearer ${tokens[role]}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: await res.json().catch(() => null) };
}
async function login(role, username, password) {
  const r = await call(role, 'POST', '/auth/login', { username, password });
  if (r.status !== 200 || !r.body?.data?.session?.accessToken) throw new Error(`No se pudo iniciar sesión como ${role} (${r.status}).`);
  tokens[role] = r.body.data.session.accessToken;
}
async function must(role, method, path, body) {
  const r = await call(role, method, path, body);
  if (r.status >= 300) throw new Error(`${method} ${path} -> ${r.status} ${JSON.stringify(r.body?.error ?? r.body).slice(0, 200)}`);
  return r.body.data;
}

const results = { ok: 0, fail: 0, skipped: [] };
const checked = new Set();
function validate(key, response, status = 200) {
  const schema = typed.get(key);
  if (!schema) { results.skipped.push(`${key} (sin esquema)`); return; }
  checked.add(key);
  if (status >= 300) { results.fail++; console.log(`FAIL ${key}: respondió ${status} ${JSON.stringify(response?.error ?? response).slice(0, 160)}`); return; }
  const check = ajv.compile(schema);
  if (check(response)) { results.ok++; console.log(`OK   ${key}`); return; }
  results.fail++;
  const e = check.errors?.[0];
  console.log(`FAIL ${key}: ${e?.instancePath || '/'} ${e?.message} ${JSON.stringify(e?.params ?? {}).slice(0, 120)}`);
}
async function get(role, key, path) { const r = await call(role, 'GET', path); validate(key, r.body, r.status); return r.body?.data; }

const tag = Date.now().toString(36);
const PW = `Chk-${tag}-9xA`;
let fx;
try {
  await login('admin', USER, PASS);
  console.log('Creando la escuela temporal «CHK …»…');
  const teacher = (await must('admin', 'POST', '/admin/teachers', { firstName: 'Prof', lastName: `CHK ${tag}`, phone: '', active: true, email: `chk.prof.${tag}@demo.test`, password: PW, teacherCode: `CHK-T-${tag}`, classIds: [] })).teacher;
  const group = (await must('admin', 'POST', '/admin/groups', { name: `CHK ${tag}` })).group;
  const klass = (await must('admin', 'POST', '/admin/classes', { subject: `CHK ${tag}`, groupId: Number(group.id), teacherId: Number(teacher.id) })).class;
  const students = [];
  for (const [i, n] of ['Ana', 'Beto'].entries()) {
    students.push((await must('admin', 'POST', '/admin/students', { firstName: n, lastName: `CHK ${tag}`, phone: '', active: true, email: `chk.al${i}.${tag}@demo.test`, password: PW, studentCode: `CHK-S${i}-${tag}`, groupId: Number(group.id), classIds: [Number(klass.id)] })).student);
  }
  await must('admin', 'POST', '/admin/parents', { firstName: 'Padre', lastName: `CHK ${tag}`, phone: '', active: true, email: `chk.pa.${tag}@demo.test`, password: PW, childIds: [Number(students[0].id)], isEmergencyContact: true });
  await login('teacher', `chk.prof.${tag}@demo.test`, PW);
  await login('student', `chk.al0.${tag}@demo.test`, PW);
  await login('parent', `chk.pa.${tag}@demo.test`, PW);

  await must('admin', 'POST', '/schedules', { kind: 'class', startTime: '07:00', endTime: '08:00', shift: 'morning', classId: Number(klass.id), room: `Aula ${tag}`, weekdayIds: [1, 2] });
  const concepts = await must('admin', 'GET', '/payments/concepts');
  const created = await call('admin', 'POST', '/payments/charges', { conceptId: Number(concepts.concepts[0].id), studentIds: [Number(students[0].id)], amount: 25, dueAt: new Date(Date.now() + 9 * 864e5).toISOString().slice(0, 10), description: 'Cargo CHK' });
  validate('POST /api/payments/charges', created.body, created.status);
  // archivo adjunto a la tarea
  const prep = await must('teacher', 'POST', '/files/prepare-upload', { originalName: 'chk.txt', mimeType: 'text/plain', sizeBytes: 3, folder: 'assignments' });
  const form = new FormData(); form.append('cacheControl', '3600'); form.append('', new Blob(['chk'], { type: 'text/plain' }), 'chk.txt');
  const put = await fetch(prep.signedUpload.signedUrl, { method: 'PUT', body: form, headers: { 'x-upsert': 'false' } });
  if (!put.ok) throw new Error(`Subida a almacenamiento: ${put.status}`);
  const file = (await must('teacher', 'POST', '/files/metadata', { originalName: 'chk.txt', storagePath: prep.storagePath, mimeType: 'text/plain', sizeBytes: 3, url: null })).file;
  const due = new Date(Date.now() + 3 * 3600e3).toISOString();
  const asg = (await must('teacher', 'POST', '/assignments/upsert', { classId: Number(klass.id), title: 'Tarea CHK', dueAt: due, maxScore: 20, allowLate: true, published: true, attachments: [{ id: Number(file.id) }] })).assignment;
  await must('student', 'POST', '/assignments/submit', { assignmentId: Number(asg.id), notes: 'chk' });
  const today = new Date().toLocaleDateString('en-CA');
  const att = await call('teacher', 'POST', `/attendance/class/${klass.id}`, { date: today, marks: students.map((s, i) => ({ studentId: Number(s.id), statusId: i === 0 ? 2 : 1 })) });
  validate('POST /api/attendance/class/:classId', att.body, att.status);
  const periods = (await must('admin', 'GET', '/grades/periods')).periods;
  const period = periods.find((p) => p.startDate <= today && today <= p.endDate) ?? periods[0];
  const card = (await must('admin', 'POST', '/reports/report-cards', { studentId: Number(students[0].id), academicPeriodId: Number(period.id) })).reportCard;
  fx = { teacher, group, klass, students, asg, file, period, card, today };

  const s0 = students[0].id;
  console.log('\nValidando respuestas reales…');
  // Administración
  for (const [key, path] of [
    ['GET /api/admin/directory', '/admin/directory'], ['GET /api/admin/profiles', '/admin/profiles'],
    ['GET /api/admin/permissions/catalog', '/admin/permissions/catalog'], ['GET /api/admin/institutions', '/admin/institutions'],
    ['GET /api/admin/roles', '/admin/roles'], ['GET /api/admin/users', '/admin/users'], ['GET /api/admin/students', '/admin/students'],
    ['GET /api/admin/teachers', '/admin/teachers'], ['GET /api/admin/parents', '/admin/parents'], ['GET /api/files', '/files'],
    ['GET /api/auth/2fa/status', '/auth/2fa/status'], ['GET /api/portal-access/me', '/portal-access/me'], ['GET /api/portal-access/config', '/portal-access/config'],
    ['GET /api/grades/periods', '/grades/periods'], ['GET /api/grades/scales/default', '/grades/scales/default'],
    ['GET /api/payments/summary', '/payments/summary'], ['GET /api/payments/concepts', '/payments/concepts'], ['GET /api/payments/charges', '/payments/charges'],
    ['GET /api/schedules', '/schedules'], ['GET /api/events/announcements', '/events/announcements'], ['GET /api/notifications', '/notifications'],
    ['GET /api/notifications/preferences', '/notifications/preferences'], ['GET /api/chats/conversations', '/chats/conversations'], ['GET /api/chats/contacts', '/chats/contacts'],
    ['GET /api/attendance/summary', `/attendance/summary?from=${today}&to=${today}`], ['GET /api/attendance/groups/:groupId', `/attendance/groups/${group.id}?from=${today}&to=${today}`],
    ['GET /api/grades/gradebook', `/grades/gradebook?classId=${klass.id}&periodId=${period.id}`],
    ['GET /api/reports/report-cards', `/reports/report-cards?academicPeriodId=${period.id}`],
    ['GET /api/reports/report-cards/preview', `/reports/report-cards/preview?studentId=${s0}&academicPeriodId=${period.id}`],
    ['GET /api/reports/report-cards/:id', `/reports/report-cards/${card.id}`],
    ['GET /api/portal-access/grades', `/portal-access/grades?studentId=${s0}`],
    ['GET /api/files/:id/download-url', `/files/${file.id}/download-url`],
    ['GET /api/developer/summary', '/developer/summary'], ['GET /api/developer/institutions', '/developer/institutions'], ['GET /api/developer/users', '/developer/users'],
    ['GET /api/developer/audit-events', '/developer/audit-events'], ['GET /api/developer/modules', '/developer/modules'], ['GET /api/developer/apis', '/developer/apis'],
    ['GET /api/developer/tasks', '/developer/tasks'], ['GET /api/developer/feature-flags', '/developer/feature-flags'], ['GET /api/developer/system-checks', '/developer/system-checks'],
  ]) await get('admin', key, path);
  const charges = await call('admin', 'GET', '/payments/charges'); const chargeId = charges.body.data.charges.find((c) => c.studentId === String(s0))?.id;
  if (chargeId) await get('admin', 'GET /api/payments/charges/:chargeId', `/payments/charges/${chargeId}`);
  const convs = (await call('admin', 'GET', '/chats/conversations')).body?.data?.conversations ?? [];
  if (convs[0]) await get('admin', 'GET /api/chats/conversations/:conversationId/messages', `/chats/conversations/${convs[0].id}/messages`);
  else results.skipped.push('GET /api/chats/conversations/:conversationId/messages (el administrador no tiene conversaciones)');
  // Maestro
  await get('teacher', 'GET /api/collaborations', '/collaborations');
  await get('teacher', 'GET /api/schedules/mine', '/schedules/mine');
  await get('teacher', 'GET /api/assignments/teacher', '/assignments/teacher');
  await get('teacher', 'GET /api/assignments/:id/submissions', `/assignments/${asg.id}/submissions`);
  await get('teacher', 'GET /api/attendance/class/:classId', `/attendance/class/${klass.id}?date=${today}`);
  const del = await call('teacher', 'DELETE', `/assignments/${asg.id}/attachments/${file.id}`); validate('DELETE /api/assignments/:id/attachments/:fileId', del.body, del.status);
  // Alumno y padre
  for (const role of ['student', 'parent']) {
    const id = role === 'student' ? '' : `&studentId=${s0}`;
    const q = role === 'student' ? '' : `?studentId=${s0}`;
    await get(role, 'GET /api/family/children', '/family/children');
    await get(role, 'GET /api/family/attendance', `/family/attendance?from=${today}&to=${today}${id}`);
    await get(role, 'GET /api/family/assignments', `/family/assignments${q}`);
    await get(role, 'GET /api/payments/mine', `/payments/mine${q}`);
  }
} catch (e) {
  results.fail++;
  console.error('\nERROR:', e.message);
} finally {
  console.log('\nLimpiando…');
  try {
    // archivar lo creado y borrar lo que cuelga de los salones «CHK …»
    const list = async (path) => (await call('admin', 'GET', path)).body?.data?.items ?? [];
    for (const kind of ['parents', 'students', 'teachers']) {
      for (const row of await list(`/admin/${kind}`)) {
        const email = row.persons?.email ?? '';
        if (email.startsWith('chk.')) await call('admin', 'DELETE', `/admin/${kind}/${row.id}`);
      }
    }
    if (fx) { await call('admin', 'DELETE', `/admin/classes/${fx.klass.id}`); await call('admin', 'DELETE', `/admin/groups/${fx.group.id}`); }
    console.log(execFileSync('node', [join(BACKEND_DIR, 'scripts', 'cleanup_e2e_data.mjs'), 'CHK '], { encoding: 'utf8' }).trim());
  } catch (e) { console.error('Limpieza incompleta:', e.message); }
}

const untested = [...typed.keys()].filter((k) => !checked.has(k));
console.log(`\nResultado: ${results.ok} correctos, ${results.fail} con diferencias.`);
if (untested.length) { console.log('Endpoints con esquema SIN caso de prueba en este verificador:'); untested.forEach((k) => console.log('  -', k)); }
process.exit(results.fail > 0 || untested.length > 0 ? 1 : 0);
