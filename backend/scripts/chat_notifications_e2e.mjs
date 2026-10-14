// E2E del flujo chat -> notificación real. Requiere una cuenta admin real:
//   E2E_ADMIN_EMAIL=... E2E_ADMIN_PASSWORD=... [API=http://localhost:3001/api] \
//     node scripts/chat_notifications_e2e.mjs
// Crea un alumno temporal, intercambia mensajes y lo archiva al terminar.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

if (!process.env.E2E_ADMIN_EMAIL || !process.env.E2E_ADMIN_PASSWORD) {
  console.error('Define E2E_ADMIN_EMAIL y E2E_ADMIN_PASSWORD.');
  process.exit(1);
}
const env = Object.fromEntries(
  readFileSync(fileURLToPath(new URL('../.env', import.meta.url)), 'utf8')
    .split(/\r?\n/).filter((l) => /^[A-Z_]+=/.test(l))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
);
const API = process.env.API ?? 'http://localhost:3001/api';
const login = async (email, password) => {
  const r = await fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: 'POST', headers: { apikey: env.SUPABASE_ANON_KEY, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('login falló ' + email);
  return j.access_token;
};
const call = async (token, method, path, body) => {
  const r = await fetch(API + path, { method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  return { status: r.status, j: await r.json().catch(() => ({})) };
};
let fails = 0;
const check = (label, ok, extra = '') => { if (!ok) fails++; console.log(`${ok ? 'OK  ' : 'FAIL'} ${label} ${extra}`); };

const admin = await login(process.env.E2E_ADMIN_EMAIL, process.env.E2E_ADMIN_PASSWORD);
const adminUserId = (await call(admin, 'GET', '/admin/profiles')).j.data.profiles.find((p) => p.email === process.env.E2E_ADMIN_EMAIL).id;
const email = `chat.e2e.${Date.now()}@demo.com`;
const st = await call(admin, 'POST', '/admin/students', { firstName: 'Chat', lastName: 'Prueba', email, password: 'demo1234', studentCode: `CH-${Date.now()}` });
const stUserId = st.j.data?.student?.user?.id;
const stId = st.j.data?.student?.id;
console.log('alumno temporal', st.status, 'userId', stUserId);
try {
  const student = await login(email, 'demo1234');
  const conv = await call(admin, 'POST', '/business-api', { action: 'chat.ensureIndividual', payload: { otherUserId: Number(stUserId) } });
  const conversationId = conv.j.data?.conversationId;
  check('crear conversación', !!conversationId, `id ${conversationId}`);

  const before = await call(student, 'GET', '/notifications');
  check('alumno sin notificaciones previas de chat', !before.j.data?.some((n) => n.data?.conversationId == conversationId));

  const sent = await call(admin, 'POST', '/business-api', { action: 'chat.sendMessage', payload: { conversationId, content: 'Hola alumno, mensaje de prueba E2E' } });
  check('enviar mensaje', sent.status === 200 || sent.status === 201, String(sent.status));

  const list = await call(student, 'GET', '/notifications');
  const n = list.j.data?.find((x) => x.data?.conversationId == conversationId);
  check('el destinatario recibe notificación real', !!n);
  check('canal "message"', n?.channel === 'message', n?.channel);
  check('título = nombre del remitente', typeof n?.title === 'string' && n.title.length > 0, n?.title);
  check('cuerpo = texto del mensaje', n?.body === 'Hola alumno, mensaje de prueba E2E', n?.body);
  check('deepLink al chat', n?.data?.deepLink === `/chat/${conversationId}`, n?.data?.deepLink);
  check('llega sin leer', n?.read === false);

  const own = await call(admin, 'GET', '/notifications');
  check('el remitente NO se notifica a sí mismo', !own.j.data?.some((x) => x.data?.conversationId == conversationId));

  // segundo mensaje: dos notificaciones; leer la conversación las marca leídas
  await call(admin, 'POST', '/business-api', { action: 'chat.sendMessage', payload: { conversationId, content: 'Segundo mensaje' } });
  const list2 = await call(student, 'GET', '/notifications');
  check('un mensaje = una notificación', list2.j.data?.filter((x) => x.data?.conversationId == conversationId).length === 2);

  const read = await call(student, 'POST', '/business-api', { action: 'chat.markAsRead', payload: { conversationId } });
  check('marcar conversación como leída', read.status === 200);
  const list3 = await call(student, 'GET', '/notifications');
  check('sus notificaciones de chat quedan leídas', list3.j.data?.filter((x) => x.data?.conversationId == conversationId).every((x) => x.read === true));

  // un tercero no ve esas notificaciones
  check('el admin no ve las del alumno', !(await call(admin, 'GET', '/notifications')).j.data?.some((x) => x.data?.conversationId == conversationId));
} finally {
  if (stId) await call(admin, 'DELETE', `/admin/students/${stId}`);
}
console.log(fails === 0 ? 'RESULTADO: todo OK' : `RESULTADO: ${fails} fallo(s)`);
process.exit(fails === 0 ? 0 : 1);
