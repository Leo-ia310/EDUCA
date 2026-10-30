import {randomUUID} from 'node:crypto';
import {withRequestKey} from './request-keys.mjs';
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
ajv.addFormat('uuid',/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);

/** key «MÉTODO /api/ruta/:param» -> esquema del cuerpo 200 (respuesta) y del cuerpo de la petición */
const typed = new Map();
const typedRequest = new Map();
for (const [path, ops] of Object.entries(spec.paths)) {
  for (const [method, op] of Object.entries(ops)) {
    const schema = op.responses?.['200']?.content?.['application/json']?.schema;
    const key = `${method.toUpperCase()} ${path.replace(/\{(\w+)\}/g, ':$1')}`;
    if (schema?.properties?.data) typed.set(key, schema);
    const reqSchema = op.requestBody?.content?.['application/json']?.schema;
    if (reqSchema?.properties) typedRequest.set(key, reqSchema);
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
const checkedRequests = new Set();
/** Escritura: valida el cuerpo que se envía contra su esquema, hace la llamada y valida la respuesta. */
async function write(role, key, path, body) {
  const [method] = key.split(' ');
  body=withRequestKey(method,path,body);
  const reqSchema = typedRequest.get(key);
  if (reqSchema) {
    checkedRequests.add(key);
    const check = ajv.compile(reqSchema);
    if (check(body)) { results.ok++; console.log(`OK   petición ${key}`); }
    else { results.fail++; const e = check.errors?.[0]; console.log(`FAIL petición ${key}: ${e?.instancePath || '/'} ${e?.message} ${JSON.stringify(e?.params ?? {}).slice(0, 120)}`); }
  }
  const r = await call(role, method, path, body);
  if (typed.has(key)) validate(key, r.body, r.status);
  else if (r.status >= 300) { results.fail++; console.log(`FAIL ${key}: respondió ${r.status} ${JSON.stringify(r.body?.error ?? r.body).slice(0, 160)}`); }
  if (r.status >= 300) throw new Error(`${key} -> ${r.status}`);
  return r.body?.data;
}
async function get(role, key, path) { const r = await call(role, 'GET', path); validate(key, r.body, r.status); return r.body?.data; }

const tag = Date.now().toString(36);
const PW = `Chk-${tag}-9xA`;
let fx;
let createdProfileId = null;
try {
  await login('admin', USER, PASS);
  console.log('Creando la escuela temporal «CHK …»…');
  const teacher = (await write('admin', 'POST /api/admin/teachers', '/admin/teachers', { firstName: 'Prof', lastName: `CHK ${tag}`, phone: '', active: true, email: `chk.prof.${tag}@demo.test`, password: PW, teacherCode: `CHK-T-${tag}`, classIds: [] })).teacher;
  const group = (await write('admin', 'POST /api/admin/groups', '/admin/groups', { name: `CHK ${tag}` })).group;
  const klass = (await write('admin', 'POST /api/admin/classes', '/admin/classes', { subject: `CHK ${tag}`, groupId: Number(group.id), teacherId: Number(teacher.id) })).class;
  const students = [];
  for (const [i, n] of ['Ana', 'Beto'].entries()) {
    students.push((await write('admin', 'POST /api/admin/students', '/admin/students', { firstName: n, lastName: `CHK ${tag}`, phone: '', active: true, email: `chk.al${i}.${tag}@demo.test`, password: PW, studentCode: `CHK-S${i}-${tag}`, groupId: Number(group.id), classIds: [Number(klass.id)] })).student);
  }
  const parentRow = (await write('admin', 'POST /api/admin/parents', '/admin/parents', { firstName: 'Padre', lastName: `CHK ${tag}`, phone: '', active: true, email: `chk.pa.${tag}@demo.test`, password: PW, childIds: [Number(students[0].id)], isEmergencyContact: true })).parent;
  await login('teacher', `chk.prof.${tag}@demo.test`, PW);
  await login('student', `chk.al0.${tag}@demo.test`, PW);
  await login('parent', `chk.pa.${tag}@demo.test`, PW);

  await write('admin', 'POST /api/schedules', '/schedules', { kind: 'class', startTime: '07:00', endTime: '08:00', shift: 'morning', classId: Number(klass.id), room: `Aula ${tag}`, weekdayIds: [1, 2] });
  const concepts = await must('admin', 'GET', '/payments/concepts');
  const created = await write('admin', 'POST /api/payments/charges', '/payments/charges', { conceptId: Number(concepts.concepts[0].id), studentIds: [Number(students[0].id)], amount: 25, dueAt: new Date(Date.now() + 9 * 864e5).toISOString().slice(0, 10), description: 'Cargo CHK' });
  void created;
  // archivo adjunto a la tarea
  const prep = await write('teacher', 'POST /api/files/prepare-upload', '/files/prepare-upload', { originalName: 'chk.txt', mimeType: 'text/plain', sizeBytes: 3, folder: 'assignments' });
  const form = new FormData(); form.append('cacheControl', '3600'); form.append('', new Blob(['chk'], { type: 'text/plain' }), 'chk.txt');
  const put = await fetch(prep.signedUpload.signedUrl, { method: 'PUT', body: form, headers: { 'x-upsert': 'false' } });
  if (!put.ok) throw new Error(`Subida a almacenamiento: ${put.status}`);
  const file = (await write('teacher', 'POST /api/files/metadata', '/files/metadata', { originalName: 'chk.txt', storagePath: prep.storagePath, mimeType: 'text/plain', sizeBytes: 3, url: null })).file;
  const due = new Date(Date.now() + 3 * 3600e3).toISOString();
  const asg = (await write('teacher', 'POST /api/assignments/upsert', '/assignments/upsert', { classId: Number(klass.id), title: 'Tarea CHK', dueAt: due, maxScore: 20, allowLate: true, published: true, attachments: [{ id: Number(file.id) }] })).assignment;
  const submitted = await write('student', 'POST /api/assignments/submit', '/assignments/submit', { assignmentId: Number(asg.id), notes: 'chk' });
  await get('teacher', 'GET /api/assignments/submissions/:submissionId/originality', `/assignments/submissions/${submitted.submission.id}/originality?evidence=true`);
  await write('teacher', 'POST /api/assignments/submissions/:submissionId/originality/retry', `/assignments/submissions/${submitted.submission.id}/originality/retry`, {});
  const today = new Date().toLocaleDateString('en-CA');
  await write('teacher', 'POST /api/attendance/class/:classId', `/attendance/class/${klass.id}`, { date: today, marks: students.map((s, i) => ({ operationId:randomUUID(),uuid:randomUUID(),expectedVersion:0,recordedAt:new Date().toISOString(),studentId: Number(s.id), statusId: i === 0 ? 2 : 1 })) });
  // calificar la entrega crea la evaluación; luego se corrige otra nota con set-grade y se oculta/publica la tarea
  await write('teacher', 'PATCH /api/assignments/submissions/:submissionId/grade', `/assignments/submissions/${submitted.submission.id}/grade`, { score: 15, feedback: 'ok' });
  await write('teacher', 'PATCH /api/assignments/:id/publish', `/assignments/${asg.id}/publish`, { published: false });
  await write('teacher', 'PATCH /api/assignments/:id/publish', `/assignments/${asg.id}/publish`, { published: true });
  const periods = (await must('admin', 'GET', '/grades/periods')).periods;
  const period = periods.find((p) => p.startDate <= today && today <= p.endDate) ?? periods[0];
  const card = (await write('admin', 'POST /api/reports/report-cards', '/reports/report-cards', { studentId: Number(students[0].id), academicPeriodId: Number(period.id), generalNotes: 'CHK' })).reportCard;
  fx = { teacher, group, klass, students, asg, file, period, card, today };

  const s0 = students[0].id;
  const portalConfig = await must('admin', 'GET', '/portal-access/config');
  const editorUser = portalConfig.users.find(u => u.name.includes(`CHK ${tag}`) && u.roles?.includes('student'));
  if (!editorUser) throw new Error('No se encontró la cuenta temporal para verificar el editor de permisos.');
  console.log('\nValidando respuestas reales…');
  // Administración
  for (const [key, path] of [
    ['GET /api/admin/directory', '/admin/directory'], ['GET /api/admin/profiles', '/admin/profiles'],
    ['GET /api/admin/permissions/catalog', '/admin/permissions/catalog'], ['GET /api/admin/institutions', '/admin/institutions'],
    ['GET /api/admin/roles', '/admin/roles'], ['GET /api/admin/users', '/admin/users'], ['GET /api/admin/students', '/admin/students'],
    ['GET /api/admin/teachers', '/admin/teachers'], ['GET /api/admin/parents', '/admin/parents'], ['GET /api/files', '/files'],
    ['GET /api/auth/2fa/status', '/auth/2fa/status'], ['GET /api/portal-access/me', '/portal-access/me'], ['GET /api/portal-access/config', '/portal-access/config'],
    ['GET /api/portal-access/users/:id/permissions', `/portal-access/users/${editorUser.id}/permissions`],
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
  // Escrituras de segundo nivel
  const book = (await call('teacher', 'GET', `/grades/gradebook?classId=${klass.id}&periodId=${period.id}`)).body?.data;
  if (book?.evaluations?.[0]) await write('teacher', 'POST /api/grades/set-grade', '/grades/set-grade', { evaluationId: Number(book.evaluations[0].id), studentId: Number(students[1].id), rawScore: 12 });
  if (chargeId) await write('admin', 'POST /api/payments/charges/:chargeId/payments', `/payments/charges/${chargeId}/payments`, { method: 'cash', amount: 5, idempotencyKey: crypto.randomUUID() });
  await write('admin', 'PATCH /api/admin/groups/:id', `/admin/groups/${group.id}`, { name: `CHK ${tag} b` });
  await write('admin', 'PATCH /api/admin/classes/:id', `/admin/classes/${klass.id}`, { teacherId: Number(teacher.id) });
  await write('admin', 'PATCH /api/admin/teachers/:id', `/admin/teachers/${teacher.id}`, { phone: '555' });
  await write('admin', 'PATCH /api/admin/students/:id', `/admin/students/${students[1].id}`, { phone: '555' });
  await write('admin', 'PATCH /api/admin/parents/:id', `/admin/parents/${parentRow.id}`, { phone: '555', childIds: [Number(students[0].id)] });
  // perfil administrativo temporal (se archiva al final)
  const prof = (await write('admin', 'POST /api/admin/profiles', '/admin/profiles', { fullName: `Perfil CHK ${tag}`, email: `chk.perfil.${tag}@demo.test`, password: PW, roleCode: 'coordinator', permissions: ['dashboard.view'] })).profile;
  await write('admin', 'PATCH /api/admin/profiles/:id', `/admin/profiles/${prof.id}`, { permissions: ['dashboard.view', 'reports.view'], phone: '555' });
  createdProfileId = prof.id;
  const schedules = (await call('admin', 'GET', '/schedules')).body?.data?.schedules ?? [];
  const mine = schedules.find((x) => x.classId === String(klass.id));
  if (mine) await write('admin', 'PATCH /api/schedules/:id', `/schedules/${mine.id}`, { room: `Aula ${tag}b` });
  // Preferencias de la cuenta temporal del maestro (sin efectos sobre otros usuarios)
  await write('teacher', 'PATCH /api/notifications/preferences', '/notifications/preferences', { emailEnabled: false });
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
  // Al final: archivar la tarea (así familia conserva datos no vacíos durante las comprobaciones anteriores)
  const delTask = await call('teacher', 'DELETE', `/assignments/${asg.id}`); validate('DELETE /api/assignments/:id', delTask.body, delTask.status);
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
    if (createdProfileId) await call('admin', 'DELETE', `/admin/users/${createdProfileId}`);
    if (fx) { await call('admin', 'DELETE', `/admin/classes/${fx.klass.id}`); await call('admin', 'DELETE', `/admin/groups/${fx.group.id}`); }
    console.log(execFileSync('node', [join(BACKEND_DIR, 'scripts', 'cleanup_e2e_data.mjs'), 'CHK '], { encoding: 'utf8' }).trim());
  } catch (e) { console.error('Limpieza incompleta:', e.message); }
}

// Con efectos secundarios sobre datos reales (conversaciones/lecturas de chat): se validan a mano.
const SKIP = new Set(['POST /api/chats/individual', 'PATCH /api/chats/conversations/:conversationId/read']);
const untested = [...typed.keys()].filter((k) => !checked.has(k) && !SKIP.has(k));
const unrequested = [...typedRequest.keys()].filter((k) => !checkedRequests.has(k));
if (unrequested.length) { console.log('Cuerpos tipados que este verificador NO envía (efectos secundarios: avisos, correos, cuentas…):'); unrequested.forEach((k) => console.log('  ·', k)); }
console.log(`\nResultado: ${results.ok} correctos, ${results.fail} con diferencias.`);
if (untested.length) { console.log('Endpoints con esquema SIN caso de prueba en este verificador:'); untested.forEach((k) => console.log('  -', k)); }
process.exit(results.fail > 0 || untested.length > 0 ? 1 : 0);
