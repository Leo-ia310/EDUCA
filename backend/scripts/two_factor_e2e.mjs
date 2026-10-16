// E2E del 2FA (TOTP + códigos de recuperación + bloqueo de reto).
//   E2E_ADMIN_EMAIL=... E2E_ADMIN_PASSWORD=... [API=http://localhost:3001/api] node scripts/two_factor_e2e.mjs
// Crea un alumno temporal y lo archiva al terminar.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createHmac } from 'node:crypto';

if (!process.env.E2E_ADMIN_EMAIL || !process.env.E2E_ADMIN_PASSWORD) { console.error('Define E2E_ADMIN_EMAIL y E2E_ADMIN_PASSWORD.'); process.exit(1); }
const env = Object.fromEntries(readFileSync(fileURLToPath(new URL('../.env', import.meta.url)), 'utf8').split(/\r?\n/).filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const API = process.env.API ?? 'http://localhost:3001/api';
const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const b32 = (s) => { let bits = ''; for (const c of s) bits += A.indexOf(c).toString(2).padStart(5, '0'); const o = []; for (let i = 0; i + 8 <= bits.length; i += 8) o.push(parseInt(bits.slice(i, i + 8), 2)); return Buffer.from(o); };
const totp = (secret, off = 0) => { const k = b32(secret); const c = Buffer.alloc(8); c.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000) + off)); const h = createHmac('sha1', k).update(c).digest(); const o = h[h.length - 1] & 15; return String((((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3]) % 1e6).padStart(6, '0'); };
const call = async (m, path, b, t) => { const r = await fetch(API + path, { method: m, headers: { 'content-type': 'application/json', ...(t ? { authorization: `Bearer ${t}` } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => ({})) }; };
const tok = async (e, p) => (await (await fetch(`${env.SUPABASE_URL}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: env.SUPABASE_ANON_KEY, 'content-type': 'application/json' }, body: JSON.stringify({ email: e, password: p }) })).json()).access_token;
let fails = 0;
const check = (l, ok, x = '') => { if (!ok) fails++; console.log(`${ok ? 'OK  ' : 'FAIL'} ${l} ${x}`); };

const admin = await tok(process.env.E2E_ADMIN_EMAIL, process.env.E2E_ADMIN_PASSWORD);
const mail = `twofa.e2e.${Date.now()}@demo.com`;
const st = await call('POST', '/admin/students', { firstName: 'Dos', lastName: 'Factores', email: mail, password: 'demo1234', studentCode: `TF-${Date.now()}` }, admin);
const stId = st.j.data?.student?.id;
const login = () => call('POST', '/auth/login', { username: mail, password: 'demo1234' });
try {
  const l0 = await login();
  const t0 = l0.j.data?.session?.accessToken;
  check('login sin 2FA entrega sesión', l0.s === 200 && !!t0 && !l0.j.data?.twoFactorRequired, `status=${l0.s}`);
  check('status: desactivado', (await call('GET', '/auth/2fa/status', null, t0)).j.data?.enabled === false);
  check('status sin sesión -> 401', (await call('GET', '/auth/2fa/status')).s === 401);
  check('enable sin setup -> 400', (await call('POST', '/auth/2fa/enable', { code: '123456' }, t0)).s === 400);
  const setup = await call('POST', '/auth/2fa/setup', { method: 'totp' }, t0);
  const secret = setup.j.data?.secret;
  check('setup devuelve secreto y otpauth', setup.s === 200 && !!secret && String(setup.j.data?.otpauthUrl).startsWith('otpauth://totp/'));
  check('enable con código malo -> 401', (await call('POST', '/auth/2fa/enable', { code: '000000' }, t0)).s === 401);
  const en = await call('POST', '/auth/2fa/enable', { code: totp(secret) }, t0);
  const rec = en.j.data?.recoveryCodes ?? [];
  check('enable con TOTP correcto + códigos de recuperación', en.s === 200 && en.j.data?.enabled === true && rec.length >= 5, `codes=${rec.length}`);
  check('status: activado', (await call('GET', '/auth/2fa/status', null, t0)).j.data?.enabled === true);

  const l1 = await login();
  const ch = l1.j.data?.challenge;
  check('login con 2FA pide reto y NO da sesión', l1.s === 200 && l1.j.data?.twoFactorRequired === true && !l1.j.data?.session && ch?.method === 'totp');
  check('verify con código malo -> 401', (await call('POST', '/auth/2fa/verify-login', { challengeId: ch.id, code: '000000' })).s === 401);
  const v = await call('POST', '/auth/2fa/verify-login', { challengeId: ch.id, code: totp(secret) });
  check('verify con TOTP correcto entrega sesión', v.s === 200 && !!v.j.data?.session?.accessToken);
  check('reto consumido: no se reutiliza', (await call('POST', '/auth/2fa/verify-login', { challengeId: ch.id, code: totp(secret) })).s === 401);
  check('la sesión emitida funciona', (await call('GET', '/auth/2fa/status', null, v.j.data?.session?.accessToken)).s === 200);

  const l2 = await login();
  const v2 = await call('POST', '/auth/2fa/verify-login', { challengeId: l2.j.data.challenge.id, recoveryCode: rec[0] });
  check('login con código de recuperación', v2.s === 200 && !!v2.j.data?.session?.accessToken);
  const l3 = await login();
  check('código de recuperación es de un solo uso', (await call('POST', '/auth/2fa/verify-login', { challengeId: l3.j.data.challenge.id, recoveryCode: rec[0] })).s === 401);

  // desactivar con TOTP (antes del bloqueo: tras 5 fallos el USUARIO queda bloqueado 15 min)
  const tAuth = v.j.data.session.accessToken;
  check('disable sin código -> error', (await call('POST', '/auth/2fa/disable', {}, tAuth)).s >= 400);
  const d = await call('POST', '/auth/2fa/disable', { code: totp(secret) }, tAuth);
  check('disable con TOTP correcto', d.s === 200 && d.j.data?.enabled === false, `status=${d.s} ${d.j.error?.code ?? ''} ${d.j.error?.message ?? ''}`);
  const l5 = await login();
  check('tras desactivar, login normal', l5.s === 200 && !!l5.j.data?.session?.accessToken && !l5.j.data?.twoFactorRequired);

  // volver a activar y probar el bloqueo
  const t1 = l5.j.data.session.accessToken;
  const setup2 = await call('POST', '/auth/2fa/setup', { method: 'totp' }, t1);
  const secret2 = setup2.j.data?.secret;
  const en2 = await call('POST', '/auth/2fa/enable', { code: totp(secret2) }, t1);
  check('se puede reactivar el 2FA', en2.s === 200 && en2.j.data?.enabled === true);
  const l4 = await login(); let last;
  for (let i = 0; i < 6; i++) last = await call('POST', '/auth/2fa/verify-login', { challengeId: l4.j.data.challenge.id, code: '000000' });
  check('5 intentos fallidos bloquean la verificación (423)', last.s === 423, `status=${last.s}`);
  check('bloqueado aunque luego el código sea bueno', (await call('POST', '/auth/2fa/verify-login', { challengeId: l4.j.data.challenge.id, code: totp(secret2) })).s === 423);
  const l6 = await login();
  check('el bloqueo es del usuario: un login nuevo tampoco entrega sesión', !l6.j.data?.session?.accessToken);
} finally {
  if (stId) await call('DELETE', `/admin/students/${stId}`, null, admin);
}
console.log(fails === 0 ? 'RESULTADO: todo OK' : `RESULTADO: ${fails} fallo(s)`);
process.exit(fails === 0 ? 0 : 1);
