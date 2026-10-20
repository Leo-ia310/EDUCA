import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Rate, Trend, Counter } from 'k6/metrics';

const base = __ENV.BASE_URL || 'https://nivra-backend-mcc4.onrender.com';
const profile = __ENV.PROFILE || 'inventory';
const contract = JSON.parse(open('../../../docs/openapi.json'));
const failed = new Rate('application_failed');
const limited = new Rate('rate_limited');
const serverFailed = new Rate('server_failed');
const latency = new Trend('application_duration', true);
const responses = new Counter('responses');
const limitSources = new Counter('rate_limit_sources');
const thresholds = {
  application_failed: ['rate<0.01'],
  server_failed: [{ threshold: 'rate<0.1', abortOnFail: true, delayAbortEval: '20s' }],
  rate_limited: [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '20s' }],
  application_duration: ['p(95)<2000'],
};
for (const stage of ['ramp_5', 'hold_5', 'ramp_10', 'hold_10', 'ramp_20', 'hold_20', 'ramp_40', 'hold_40', 'recovery']) {
  thresholds[`application_duration{stage:${stage}}`] = [];
  thresholds[`application_failed{stage:${stage}}`] = [];
  thresholds[`responses{stage:${stage}}`] = [];
}
for (const status of [200, 201, 400, 401, 403, 404, 429, 500, 502, 503, 504, 0]) thresholds[`responses{status:${status}}`] = [];
for (const source of ['ip_auth', 'ip_general', 'user_or_other']) thresholds[`rate_limit_sources{source:${source}}`] = [];
for (const path of Object.keys(contract.paths)) {
  if (contract.paths[path].get) thresholds[`application_duration{endpoint:${path}}`] = [];
}
export const options = {
  setupTimeout: '8m', teardownTimeout: '2m',
  scenarios: profile === 'reads' ? {
    reads: { executor: 'ramping-arrival-rate', exec: 'read', startRate: 1, timeUnit: '1s',
      preAllocatedVUs: 30, maxVUs: 200, stages: [
        { duration: '20s', target: 5 }, { duration: '30s', target: 5 },
        { duration: '10s', target: 10 }, { duration: '30s', target: 10 },
        { duration: '10s', target: 20 }, { duration: '30s', target: 20 },
        { duration: '10s', target: 40 }, { duration: '30s', target: 40 },
        { duration: '15s', target: 0 },
      ] },
  } : profile === 'soak' ? {
    soak: { executor: 'constant-arrival-rate', exec: 'read', rate: Number(__ENV.SOAK_RPS || 5),
      timeUnit: '1s', duration: __ENV.SOAK_DURATION || '120s', preAllocatedVUs: 20, maxVUs: 60 },
  } : profile === 'writes' ? {
    writes: { executor: 'constant-arrival-rate', exec: 'write', rate: Number(__ENV.WRITE_RPS || 2),
      timeUnit: '1s', duration: '45s', preAllocatedVUs: 8, maxVUs: 20 },
  } : profile === 'login' ? {
    login: { executor: 'constant-arrival-rate', exec: 'loginLoad', rate: 1,
      timeUnit: '1s', duration: '30s', preAllocatedVUs: 5, maxVUs: 10 },
  } : { inventory: { executor: 'shared-iterations', iterations: 1, vus: 1, exec: 'inventory' } },
  thresholds, summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
};

function body(r) { try { return r.json(); } catch (_) { return {}; } }
function request(method, path, token, payload, phase = 'setup', name = path) {
  return http.request(method, base + path, payload == null ? null : JSON.stringify(payload), {
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    timeout: '15s', tags: { endpoint: name, phase, name },
  });
}
function credentials(role) {
  return { username: __ENV[`${role.toUpperCase()}_USERNAME`] || `${role}@educa360.com`,
    password: __ENV[`${role.toUpperCase()}_PASSWORD`] || __ENV.DEMO_PASSWORD || 'demo1234', institutionCode: __ENV.INSTITUTION_CODE || 'EDU360' };
}
function measure(r, endpoint) {
  const ok = r.status >= 200 && r.status < 300 && body(r).ok !== false;
  const seconds = (Date.now() - exec.scenario.startTime) / 1000;
  const bounds = [20, 50, 60, 90, 100, 130, 140, 170, Infinity];
  const labels = ['ramp_5', 'hold_5', 'ramp_10', 'hold_10', 'ramp_20', 'hold_20', 'ramp_40', 'hold_40', 'recovery'];
  const tags = { endpoint, stage: profile === 'reads' ? labels[bounds.findIndex(x => seconds < x)] : profile };
  failed.add(!ok, tags); limited.add(r.status === 429, tags);
  serverFailed.add(r.status === 0 || r.status >= 500, tags);
  latency.add(r.timings.duration, tags); responses.add(1, { ...tags, status: String(r.status) });
  if (r.status === 429) {
    const message = body(r).error?.message || '';
    const source = message.includes('acciones autenticadas') ? 'ip_auth' : message.includes('Intenta de nuevo') ? 'ip_general' : 'user_or_other';
    limitSources.add(1, { source });
    if (exec.scenario.iterationInTest % 10 === 0) console.log('RATE_LIMIT ' + JSON.stringify({ endpoint, source, message,
      rateLimit: r.headers.Ratelimit, policy: r.headers['Ratelimit-Policy'], retryAfter: r.headers['Retry-After'] }));
  }
  check(r, { 'application success': () => ok }, tags);
  if (!ok && exec.scenario.iterationInTest < 3) console.log('FAILURE ' + JSON.stringify({ endpoint, status: r.status, error: r.error, detail: body(r).error, preview: r.status >= 500 ? String(r.body).slice(0, 160) : undefined }));
}
function list(value) {
  if (Array.isArray(value)) return value;
  if (!value || typeof value !== 'object') return [];
  for (const k of ['items', 'children', 'assignments', 'conversations', 'charges', 'reportCards', 'classes', 'periods'])
    if (Array.isArray(value[k])) return value[k];
  return [];
}

export function setup() {
  const tokens = {}, coverage = [], cases = [], cache = {};
  for (const role of ['admin', 'teacher', 'student', 'parent']) {
    const r = request('POST', '/api/auth/login', null, credentials(role));
    const b = body(r);
    tokens[role] = b.data?.session?.accessToken;
    console.log(JSON.stringify({ login: role, status: r.status, authenticated: !!tokens[role],
      institutionCode: b.data?.institution?.code, error: b.error?.code, message: b.error?.message,
      retryAfter: r.headers['Retry-After'] }));
    if (!tokens[role]) throw new Error(`Login unavailable for ${role}; no load generated.`);
    if (b.data?.institution?.code !== (__ENV.INSTITUTION_CODE || 'EDU360')) throw new Error('Institution mismatch');
  }
  if (profile === 'login') return { tokens, cases, fixtures: [] };
  function probe(path, role, template = path, method = 'GET', payload) {
    const r = request(method, path, tokens[role], payload);
    const b = body(r), ok = r.status >= 200 && r.status < 300 && b.ok !== false;
    coverage.push({ path: template, method, role, status: r.status, ms: r.timings.duration,
      error: b.error?.code, message: b.error?.message });
    if (ok) { cases.push({ path, role, template, method, payload }); cache[template] = b.data; }
    return b.data;
  }
  const classes = list(probe('/api/assignments/teacher-classes', 'teacher', '/api/assignments/teacher-classes', 'POST', {}));
  const classId = classes[0]?.classId;
  const groupId = classes[0]?.groupId;
  for (const [path, methods] of Object.entries(profile === 'writes' ? {} : contract.paths)) {
    if (!methods.get || /[:{*]/.test(path)) continue;
    if (!path.startsWith('/api/')) { coverage.push({ path, skipped: 'Operational endpoint excluded from business capacity' }); continue; }
    if (path.startsWith('/api/developer')) { coverage.push({ path, skipped: 'Requires developer account; institutional admin is insufficient' }); continue; }
    let role = 'admin';
    if (path.startsWith('/api/family')) role = 'parent';
    else if (path === '/api/payments/mine' || path === '/api/portal-access/grades' || path === '/api/schedules/mine') role = 'student';
    else if (path.startsWith('/api/assignments') || path.startsWith('/api/collaborations') || path.startsWith('/api/sync')) role = 'teacher';
    else if (path.startsWith('/api/chats') || path.startsWith('/api/notifications') || path === '/api/portal-access/me') role = 'parent';
    let actual = path;
    const period = list(cache['/api/grades/periods'])[0];
    if (path.endsWith('/gradebook')) actual += classId && period ? `?classId=${classId}&periodId=${period.id}` : '';
    if (path === '/api/family/attendance' || path === '/api/family/assignments') {
      const child = list(cache['/api/family/children'])[0];
      if (child) actual += `?studentId=${child.studentId || child.id}`;
    }
    if (path.endsWith('/report-cards/preview')) {
      const student = list(cache['/api/family/children'])[0];
      if (!student) { coverage.push({ path, skipped: 'No child fixture available for preview' }); continue; }
      actual += `?studentId=${student.studentId || student.id}&academicPeriodId=${period?.id || ''}`;
    }
    probe(actual, role, path);
  }
  const dynamic = [
    ['/api/attendance/class/:classId', classId, 'teacher'],
    ['/api/attendance/groups/:groupId', groupId, 'admin'],
    ['/api/assignments/:id/submissions', list(cache['/api/assignments/teacher'])[0]?.id, 'teacher'],
    ['/api/chats/conversations/:conversationId/messages', list(cache['/api/chats/conversations'])[0]?.id, 'parent'],
    ['/api/files/:id/download-url', list(cache['/api/files'])[0]?.id, 'admin'],
    ['/api/payments/charges/:chargeId', list(cache['/api/payments/charges'])[0]?.id, 'admin'],
    ['/api/reports/report-cards/:id', list(cache['/api/reports/report-cards'])[0]?.id, 'admin'],
  ];
  for (const [template, id, role] of profile === 'writes' ? [] : dynamic) {
    if (id) probe(template.replace(/:[A-Za-z]+/, String(id)), role, template);
    else coverage.push({ path: template, skipped: 'No matching fixture' });
  }
  console.log('COVERAGE ' + JSON.stringify(coverage));
  const fixtures = [];
  if (profile === 'writes') {
    if (__ENV.ALLOW_WRITES !== 'EDU360' || (__ENV.INSTITUTION_CODE || 'EDU360') !== 'EDU360' || !classId)
      throw new Error('Writes require explicit EDU360 opt-in and an EDU360 class fixture');
    for (let i = 0; i < 8; i++) {
      const payload = { classId, title: `K6-STRESS-${Date.now()}-${i}`, description: 'Temporary k6 draft',
        dueAt: new Date(Date.now() + 86400000 * 3).toISOString(), maxScore: 100, published: false };
      const r = request('POST', '/api/assignments/upsert', tokens.teacher, payload);
      const assignment = body(r).data?.assignment;
      if (assignment?.id) fixtures.push({ id: assignment.id, payload });
      else console.log(JSON.stringify({ fixture: i, status: r.status, error: body(r).error?.code }));
    }
    if (!fixtures.length) throw new Error('Could not create draft fixtures');
    console.log('FIXTURES ' + JSON.stringify(fixtures.map(x => ({ id: x.id, title: x.payload.title }))));
  }
  return { tokens, cases, fixtures };
}
export function inventory(data) {
  for (const c of data.cases) measure(request(c.method, c.path, data.tokens[c.role], c.payload, 'load', c.template), c.template);
}
export function read(data) {
  // Rotate roles evenly, so the institutional administrator does not monopolize the sample.
  const roles = ['admin', 'teacher', 'student', 'parent'];
  const i = exec.scenario.iterationInTest;
  const roleCases = data.cases.filter(c => c.role === roles[i % 4]);
  const c = roleCases[Math.floor(i / 4) % roleCases.length];
  measure(request(c.method, c.path, data.tokens[c.role], c.payload, 'load', c.template), c.template);
}
export function write(data) {
  const fixture = data.fixtures[(exec.vu.idInTest - 1) % data.fixtures.length];
  measure(request('POST', '/api/assignments/upsert', data.tokens.teacher,
    { ...fixture.payload, assignmentId: fixture.id, description: `k6 iteration ${exec.scenario.iterationInTest}` }, 'load'), '/api/assignments/upsert');
}
export function loginLoad() {
  const role = ['admin', 'teacher', 'student', 'parent'][exec.scenario.iterationInTest % 4];
  measure(request('POST', '/api/auth/login', null, credentials(role), 'load'), '/api/auth/login');
}
export function teardown(data) {
  for (const fixture of data.fixtures) {
    const r = request('DELETE', `/api/assignments/${fixture.id}`, data.tokens.admin, undefined, 'cleanup');
    console.log('CLEANUP ' + JSON.stringify({ id: fixture.id, status: r.status, softDelete: true }));
  }
  if (data.fixtures.length) {
    const r = request('GET', '/api/assignments/teacher', data.tokens.admin, undefined, 'cleanup');
    const remaining = list(body(r).data).filter(a => data.fixtures.some(f => String(f.id) === String(a.id))).map(a => a.id);
    console.log('CLEANUP_VERIFIED ' + JSON.stringify({ status: r.status, remaining, verified: r.status === 200 && remaining.length === 0 }));
  }
  const r = request('GET', '/health', null, undefined, 'recovery');
  console.log('RECOVERY ' + JSON.stringify({ status: r.status, ms: r.timings.duration }));
}
export function handleSummary(data) {
  // k6 includes setup_data in this version: never persist bearer tokens or personal fixtures.
  delete data.setup_data;
  return { [__ENV.SUMMARY_PATH || 'backend-summary.json']: JSON.stringify(data, null, 2) };
}
