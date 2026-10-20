import http from 'k6/http';
import { sleep } from 'k6';
import execution from 'k6/execution';
import { Counter, Rate, Trend } from 'k6/metrics';

const sessions = JSON.parse(__ENV.SESSIONS_JSON);
const base = __ENV.BASE_URL;
const realistic = __ENV.MODE === 'sessions';
const requests = new Counter('business_requests');
const failures = new Rate('business_failed');
const serverFailures = new Rate('business_server_failed');
const limited = new Rate('business_limited');
const latency = new Trend('business_duration', true);
const statuses = new Counter('business_status');
const probes = new Counter('operational_requests');
const probeLatency = new Trend('operational_duration', true);
const probeStatuses = new Counter('operational_status');
const thresholds = {
  business_failed: ['rate<0.01'],
  business_duration: ['p(95)<2000'],
  business_server_failed: [{ threshold: 'rate<0.05', abortOnFail: true, delayAbortEval: '20s' }],
  business_limited: [{ threshold: 'rate<0.10', abortOnFail: true, delayAbortEval: '20s' }],
};
for (const status of [0, 200, 400, 401, 403, 404, 429, 500, 502, 503, 504]) thresholds[`business_status{status:${status}}`] = [];
for (const endpoint of ['/health', '/ready']) {
  thresholds[`operational_duration{endpoint:${endpoint}}`] = [];
  for (const status of [0, 200, 503, 504]) thresholds[`operational_status{endpoint:${endpoint},status:${status}}`] = [];
}
for (const endpoint of new Set(sessions.flatMap(s => s.paths.map(p => p.split('?')[0])))) {
  thresholds[`business_duration{endpoint:${endpoint}}`] = [];
  thresholds[`business_failed{endpoint:${endpoint}}`] = [];
  thresholds[`business_requests{endpoint:${endpoint}}`] = [];
}
export const options = {
  scenarios: {
    business: realistic
      ? { executor: 'constant-vus', vus: sessions.length, duration: __ENV.DURATION, gracefulStop: '75s' }
      : { executor: 'constant-arrival-rate', rate: Number(__ENV.RPS), timeUnit: '1s', duration: __ENV.DURATION, preAllocatedVUs: 30, maxVUs: 200, gracefulStop: '75s' },
    ...(!realistic ? { probes: { executor: 'constant-vus', exec: 'probe', vus: 1, duration: __ENV.DURATION, gracefulStop: '75s' } } : {}),
  },
  thresholds,
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};
let errorSamples = 0;
export default function () {
  const i = execution.scenario.iterationInTest;
  const s = sessions[realistic ? (execution.vu.idInTest - 1) % sessions.length : i % sessions.length];
  const path = s.paths[Math.floor(i / sessions.length) % s.paths.length];
  const tags = { endpoint: path.split('?')[0], role: s.role, institution: s.institution };
  const r = http.get(base + path, { headers: { Authorization: `Bearer ${s.token}` }, timeout: '70s', tags: { ...tags, name: path.split('?')[0] } });
  let body; try { body = r.json(); } catch { /* proxy failure may not be JSON */ }
  const ok = r.status === 200 && body?.ok === true;
  requests.add(1, tags); failures.add(!ok, tags); latency.add(r.timings.duration, tags);
  serverFailures.add(r.status === 0 || r.status >= 500, tags); limited.add(r.status === 429, tags);
  statuses.add(1, { status: String(r.status) });
  if (!ok && errorSamples++ < 3) console.log('FAILURE ' + JSON.stringify({ ...tags, status: r.status, code: body?.error?.code, requestId: body?.error?.requestId || r.headers['X-Request-Id'], retryAfter: r.headers['Retry-After'], quotaRemaining: r.headers['X-User-Ratelimit-Remaining'], transportError: r.error, ms: r.timings.duration }));
  if (realistic) sleep(3 + Math.random() * 4);
}
export function probe() {
  for (const path of ['/health', '/ready']) {
    const r = http.get(base + path, { timeout: '70s', tags: { name: path, phase: 'operational' } });
    probes.add(1);
    probeLatency.add(r.timings.duration, { endpoint: path });
    probeStatuses.add(1, { endpoint: path, status: String(r.status) });
    if (r.status !== 200) console.log('PROBE_FAILURE ' + JSON.stringify({ path, status: r.status, requestId: r.headers['X-Request-Id'], ms: r.timings.duration }));
  }
  sleep(5);
}
export function handleSummary(data) {
  delete data.setup_data;
  return { [__ENV.SUMMARY_PATH]: JSON.stringify({ mode: __ENV.MODE, rps: Number(__ENV.RPS || 0), identities: sessions.length, metrics: data.metrics, state: data.state }, null, 2) };
}
