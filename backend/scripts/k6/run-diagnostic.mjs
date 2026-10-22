import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
const require = createRequire(import.meta.url);
const dotenv = require('dotenv');
const { createClient } = require('@supabase/supabase-js');
const base = process.env.BASE_URL || 'https://nivra-backend-mcc4.onrender.com';
const root = path.resolve(import.meta.dirname, '../..');
const out = path.resolve(root, 'stress-results', process.env.RUN_LABEL || '2026-10-20');
fs.mkdirSync(out, { recursive: true });
const env = dotenv.parse(fs.readFileSync(path.join(root, '.env')));
const accounts = JSON.parse(process.env.K6_ACCOUNTS_JSON || '[]');
if (accounts.length !== 8) throw Error('Provide eight authorized distinct accounts in K6_ACCOUNTS_JSON');
const sessions = [], evidence = { startedAt: new Date().toISOString(), base, preflight: [], phases: [], cleanup: [], runnerRequests: 0 };
const common = ['/api/auth/2fa/status', '/api/portal-access/me', '/api/notifications?limit=20', '/api/chats/conversations?limit=20', '/api/events/announcements?limit=20'];
const routes = {
  admin: ['/api/admin/directory/counts', '/api/admin/directory/people?role=student&pageSize=20', '/api/admin/directory/people?role=parent&pageSize=20', '/api/admin/directory?kind=classes&pageSize=20', '/api/admin/profiles?pageSize=20', '/api/admin/roles', '/api/schedules?pageSize=20', '/api/payments/charges', '/api/payments/summary', '/api/grades/periods', '/api/grades/scales/default', '/api/reports/report-cards'],
  teacher: ['/api/assignments/teacher?limit=20', '/api/schedules/mine', '/api/grades/periods', '/api/grades/scales/default', '/api/sync/changes?limit=100'],
  student: ['/api/assignments/student?limit=20', '/api/payments/mine', '/api/schedules/mine', '/api/portal-access/grades'],
  parent: ['/api/family/children'],
};
function save() { fs.writeFileSync(path.join(out, 'evidence.json'), JSON.stringify(evidence, null, 2)); }
async function request(url, token, payload) {
  evidence.runnerRequests++;
  const t = performance.now();
  const r = await fetch(base + url, { method: payload ? 'POST' : 'GET', headers: { 'content-type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: payload ? JSON.stringify(payload) : undefined, signal: AbortSignal.timeout(70000) });
  let b; try { b = await r.json(); } catch { /* sanitized below */ }
  return { status: r.status, body: b, ms: performance.now() - t, requestId: r.headers.get('x-request-id') };
}
async function phase(name, mode, rps, duration) {
  const summary = path.join(out, `${name}-summary.json`);
  const log = fs.createWriteStream(path.join(out, `${name}.log`));
  console.log(`START ${name} ${new Date().toISOString()}`);
  const code = await new Promise((resolve, reject) => {
    const child = spawn(process.env.K6_PATH || 'C:\\Program Files\\k6\\k6.exe', ['run', '--quiet', path.join(import.meta.dirname, 'diagnostic.js')], { env: { ...process.env, K6_ACCOUNTS_JSON: '', SESSIONS_JSON: JSON.stringify(sessions), BASE_URL: base, MODE: mode, RPS: String(rps), DURATION: duration, SUMMARY_PATH: summary }, windowsHide: true });
    for (const stream of [child.stdout, child.stderr]) stream.on('data', chunk => { log.write(chunk); const str = String(chunk); if (/FAILURE|WARN|ERRO/.test(str)) process.stdout.write(str); });
    child.on('error', reject); child.on('close', resolve);
  });
  await new Promise(resolve => log.end(resolve));
  const result = fs.existsSync(summary) ? JSON.parse(fs.readFileSync(summary)) : null;
  const m = result?.metrics || {};
  const row = { name, code, requestedRps: rps, requests: m.business_requests?.values.count, failed: m.business_failed?.values.rate, serverFailed: m.business_server_failed?.values.rate, limited: m.business_limited?.values.rate, p95: m.business_duration?.values['p(95)'], p99: m.business_duration?.values['p(99)'], dropped: m.dropped_iterations?.values.count || 0 };
  evidence.phases.push(row); save(); console.log('RESULT ' + JSON.stringify(row)); return row;
}
try {
  for (const account of accounts) {
    const r = await request('/api/auth/login', null, { username: account.username, password: account.password, institutionCode: account.institutionCode });
    const d = r.body?.data;
    evidence.preflight.push({ operation: 'login', role: account.role, institution: account.institutionCode, status: r.status, ms: r.ms, error: r.body?.error?.code });
    if (r.status !== 200 || !d?.session?.accessToken || d.institution?.code !== account.institutionCode) throw Error(`Login failed for ${account.role}/${account.institutionCode}: ${r.status}`);
    if (sessions.some(s => s.userId === d.user.id)) throw Error('Repeated user identity');
    const s = { token: d.session.accessToken, userId: d.user.id, role: account.role, institution: account.institutionCode, paths: [] };
    sessions.push(s);
    for (const url of [...common, ...routes[s.role]]) {
      const p = await request(url, s.token);
      evidence.preflight.push({ operation: 'GET', path: url, role: s.role, institution: s.institution, status: p.status, ms: p.ms, error: p.body?.error?.code, requestId: p.requestId });
      if (p.status === 200 && p.body?.ok === true) s.paths.push(url);
      if (url === '/api/family/children' && p.status === 200) {
        const data = p.body.data; const children = Array.isArray(data) ? data : data?.children || data?.items || [];
        for (const child of children.slice(0, 1)) for (const suffix of ['attendance', 'assignments']) {
          const childUrl = `/api/family/${suffix}?studentId=${child.studentId || child.id}`;
          const c = await request(childUrl, s.token);
          evidence.preflight.push({ operation: 'GET', path: `/api/family/${suffix}`, role: s.role, institution: s.institution, status: c.status, ms: c.ms, error: c.body?.error?.code, requestId: c.requestId });
          if (c.status === 200 && c.body?.ok === true) s.paths.push(childUrl);
        }
      }
    }
    if (!s.paths.length) throw Error('No valid read paths for identity');
    console.log(JSON.stringify({ preflight: s.role, institution: s.institution, validPaths: s.paths.length }));
  }
  save();
  if (process.env.DIAGNOSTIC_MODE === 'soak') {
    await phase(`soak-${Number(process.env.SOAK_RPS || 1)}rps`, 'arrival', Number(process.env.SOAK_RPS || 1), process.env.SOAK_DURATION || '180s');
  } else {
    await phase('sessions-8', 'sessions', 0, '90s');
    for (const rps of [5, 10, 20, 40, 80]) {
      const row = await phase(`reads-${rps}rps`, 'arrival', rps, '45s');
      if (row.serverFailed > 0.01 || row.limited > 0.01 || row.dropped > 0 || (row.code && row.code !== 99) || row.p95 > 10000) break;
    }
    await phase('recovery-2rps', 'arrival', 2, '60s');
  }
} catch (error) {
  evidence.error = String(error.message).replace(/eyJ[\w.-]+/g, '[TOKEN]'); console.error(evidence.error); process.exitCode = 1;
} finally {
  const client = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  for (const s of sessions) {
    const { error } = await client.auth.admin.signOut(s.token, 'local');
    evidence.cleanup.push({ operation: 'close-test-session', role: s.role, institution: s.institution, ok: !error, error: error?.code });
  }
  evidence.finishedAt = new Date().toISOString(); save(); console.log('FINISHED ' + JSON.stringify({ phases: evidence.phases.length, runnerRequests: evidence.runnerRequests, closedSessions: evidence.cleanup.filter(c => c.ok).length }));
}
