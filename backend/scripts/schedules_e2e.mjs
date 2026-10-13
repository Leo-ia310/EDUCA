// E2E del módulo de horarios contra el backend real. Requiere una cuenta admin:
//   E2E_ADMIN_EMAIL=... E2E_ADMIN_PASSWORD=... [API=http://localhost:3001/api] \
//     node scripts/schedules_e2e.mjs
// Crea horarios y un alumno temporales y los elimina/archiva al terminar.
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
  if (!j.access_token) throw new Error('login falló ' + email);
  return j.access_token;
}
async function call(token, method, path, body) {
  const r = await fetch(API + path, {
    method,
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  let j = {};
  try { j = await r.json(); } catch {}
  return { status: r.status, j };
}
let failures = 0;
function check(label, r, expected, extra) {
  const ok = r.status === expected;
  if (!ok) failures++;
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${label.padEnd(52)} ${r.status}`, extra ? extra(r.j) : (r.j.error?.message ?? r.j.message ?? ''));
}

const admin = await login(process.env.E2E_ADMIN_EMAIL, process.env.E2E_ADMIN_PASSWORD);
const dir = (await call(admin, 'GET', '/admin/directory')).j.data;
const classes = dir.classes.filter((c) => c.group_id != null || c.groupId != null);
console.log(`directorio: ${dir.groups.length} grupos, ${classes.length} clases`);
const gid = (c) => String(c.group_id ?? c.groupId);
const tid = (c) => c.teacher_id ?? c.teacherId;

// Dos clases del mismo grupo y dos de grupos distintos con el mismo maestro (si existen)
const classA = classes[0];
const sameGroup = classes.find((c) => c.id !== classA.id && gid(c) === gid(classA));
const sameTeacherOtherGroup = classes.find((c) => c.id !== classA.id && gid(c) !== gid(classA) && tid(c) != null && tid(c) === tid(classA));
const otherGroupClass = classes.find((c) => gid(c) !== gid(classA));

const DAY = 6; // sábado: libre de datos reales
const created = [];
const track = (r) => { for (const s of r.j.data?.schedules ?? []) created.push(s.id); if (r.j.data?.schedule) created.push(r.j.data.schedule.id); };

try {
  const base = { classId: classA.id, weekdayId: DAY, startTime: '05:00', endTime: '05:45', room: 'Aula E2E', shift: 'morning' };
  const ok1 = await call(admin, 'POST', '/schedules', base);
  check('crear horario de clase', ok1, 201, (j) => `${j.data?.schedules?.[0]?.subject} ${j.data?.schedules?.[0]?.startTime}-${j.data?.schedules?.[0]?.endTime} aula ${j.data?.schedules?.[0]?.room}`);
  track(ok1);
  const sid = ok1.j.data?.schedules?.[0]?.id;

  check('validar: hora fin <= inicio', await call(admin, 'POST', '/schedules', { ...base, startTime: '06:00', endTime: '05:00' }), 400);
  check('validar: hora inválida', await call(admin, 'POST', '/schedules', { ...base, startTime: '25:99' }), 400);
  check('validar: sin día', await call(admin, 'POST', '/schedules', { classId: classA.id, startTime: '07:00', endTime: '08:00' }), 400);
  check('validar: día fuera de rango', await call(admin, 'POST', '/schedules', { ...base, weekdayId: 9 }), 400);
  check('validar: sin clase', await call(admin, 'POST', '/schedules', { weekdayId: DAY, startTime: '07:00', endTime: '08:00' }), 400);
  check('validar: turno inválido', await call(admin, 'POST', '/schedules', { ...base, startTime: '07:00', endTime: '08:00', shift: 'luna' }), 400);
  check('validar: clase de otra institución/inexistente', await call(admin, 'POST', '/schedules', { ...base, classId: 99999999, startTime: '07:00', endTime: '08:00' }), 400);

  check('choque: misma clase/grupo mismo horario', await call(admin, 'POST', '/schedules', { ...base, startTime: '05:30', endTime: '06:00' }), 409);
  if (sameGroup) check('choque: otro curso del mismo grupo', await call(admin, 'POST', '/schedules', { classId: sameGroup.id, weekdayId: DAY, startTime: '05:10', endTime: '05:20' }), 409);
  if (sameTeacherOtherGroup) check('choque: mismo maestro en otro grupo', await call(admin, 'POST', '/schedules', { classId: sameTeacherOtherGroup.id, weekdayId: DAY, startTime: '05:10', endTime: '05:20' }), 409);
  if (otherGroupClass && !sameTeacherOtherGroup) {
    const r = await call(admin, 'POST', '/schedules', { classId: otherGroupClass.id, weekdayId: DAY, startTime: '05:10', endTime: '05:20', room: 'Aula E2E' });
    check('choque: misma aula (otro grupo)', r, 409);
    track(r);
  }
  const adjacent = await call(admin, 'POST', '/schedules', { ...base, startTime: '05:45', endTime: '06:30', room: 'Aula E2E' });
  check('bloques contiguos NO chocan (05:45-06:30)', adjacent, 201);
  track(adjacent);

  const brk = await call(admin, 'POST', '/schedules', { kind: 'break', label: 'Receso E2E', groupId: gid(classA), weekdayIds: [DAY], startTime: '06:40', endTime: '07:00', shift: 'morning' });
  check('crear receso del grupo', brk, 201, (j) => `${j.data?.schedules?.[0]?.subject} grupo ${j.data?.schedules?.[0]?.groupName}`);
  track(brk);
  check('choque: clase del grupo dentro del receso', await call(admin, 'POST', '/schedules', { classId: classA.id, weekdayId: DAY, startTime: '06:50', endTime: '07:10' }), 409);
  check('choque: receso encima de la clase', await call(admin, 'POST', '/schedules', { kind: 'break', groupId: gid(classA), weekdayId: DAY, startTime: '05:30', endTime: '05:50' }), 409);

  const multi = await call(admin, 'POST', '/schedules', { classId: classA.id, weekdayIds: [1, 2, 3], startTime: '04:00', endTime: '04:40' });
  check('crear en varios días (lun-mié)', multi, 201, (j) => `${j.data?.schedules?.length} bloques`);
  track(multi);

  const list = await call(admin, 'GET', `/schedules?groupId=${gid(classA)}&weekdayId=${DAY}`);
  check('listar por grupo y día', list, 200, (j) => `${j.data?.schedules?.length} (clase + receso del grupo)`);

  if (sid) {
    check('editar horario (hora)', await call(admin, 'PATCH', `/schedules/${sid}`, { startTime: '05:05', endTime: '05:40' }), 200, (j) => `${j.data?.schedule?.startTime}-${j.data?.schedule?.endTime}`);
    check('editar: choque con receso', await call(admin, 'PATCH', `/schedules/${sid}`, { startTime: '06:45', endTime: '06:55' }), 409);
  }

  // Alumno temporal inscrito en el grupo de la clase: ve sus clases y sus recesos
  const email = `horario.e2e.${Date.now()}@demo.com`;
  const st = await call(admin, 'POST', '/admin/students', {
    firstName: 'Horario', lastName: 'E2E', email, password: 'demo1234', studentCode: `E2E-${Date.now()}`, groupId: gid(classA),
  });
  check('crear alumno temporal en el grupo', st, 201);
  const stId = st.j.data?.student?.id;
  if (st.status === 201) {
    const studentToken = await login(email, 'demo1234');
    const mine = await call(studentToken, 'GET', '/schedules/mine');
    const items = mine.j.data?.schedules ?? [];
    check('alumno: /schedules/mine', mine, 200, () => `${items.length} bloques; recesos: ${items.filter((i) => i.kind === 'break').length}`);
    const onlyOwn = items.every((i) => i.kind === 'break' ? (i.groupId == null || i.groupId === gid(classA)) : true);
    console.log(`${onlyOwn ? 'OK  ' : 'FAIL'} alumno solo ve recesos de su grupo/generales`); if (!onlyOwn) failures++;
    const hasMine = items.some((i) => i.subject === (created.length ? items.find((x) => x.classId === String(classA.id))?.subject : '') && i.weekdayIndex === DAY - 1);
    console.log(`${hasMine ? 'OK  ' : 'FAIL'} alumno ve el horario creado (sábado)`); if (!hasMine) failures++;
    check('alumno no puede crear horarios', await call(studentToken, 'POST', '/schedules', base), 403);
    check('alumno no puede listar el general', await call(studentToken, 'GET', '/schedules'), 403);
    check('admin: /schedules/mine -> 400', await call(admin, 'GET', '/schedules/mine'), 400);
    if (stId) await call(admin, 'DELETE', `/admin/students/${stId}`);
  }
} finally {
  for (const id of created) await call(admin, 'DELETE', `/schedules/${id}`);
  console.log(`limpieza: ${created.length} horarios eliminados`);
}
console.log(failures === 0 ? 'RESULTADO: todo OK' : `RESULTADO: ${failures} fallo(s)`);
process.exit(failures === 0 ? 0 : 1);
