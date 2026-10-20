import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Rate, Trend, Counter } from 'k6/metrics';

const failures = new Rate('service_failures');
const latency = new Trend('health_duration', true);
const count = new Counter('health_responses');
const thresholds = { service_failures: [{ threshold: 'rate<0.2', abortOnFail: true, delayAbortEval: '30s' }] };
for (const stage of ['warmup', '50', '100', '200', '500', '1000', 'recovery']) {
  thresholds[`health_duration{stage:${stage}}`] = [];
  thresholds[`service_failures{stage:${stage}}`] = [];
  thresholds[`health_responses{stage:${stage}}`] = [];
}
export const options = {
  scenarios: {
    health: __ENV.SMOKE === '1'
      ? { executor: 'shared-iterations', vus: 1, iterations: 3, maxDuration: '3m' }
      : { executor: 'ramping-arrival-rate', startRate: 1, timeUnit: '1s',
          preAllocatedVUs: 100, maxVUs: 500, stages: [
            { duration: '15s', target: 10 }, { duration: '15s', target: 50 },
            { duration: '20s', target: 50 }, { duration: '10s', target: 100 },
            { duration: '20s', target: 100 }, { duration: '10s', target: 200 },
            { duration: '20s', target: 200 }, { duration: '10s', target: 500 },
            { duration: '20s', target: 500 }, { duration: '10s', target: 1000 },
            { duration: '20s', target: 1000 }, { duration: '15s', target: 0 },
          ] },
  },
  thresholds,
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
};
export default function () {
  const res = http.get(`${__ENV.BASE_URL || 'https://nivra-backend-mcc4.onrender.com'}/health`, {
    timeout: __ENV.SMOKE === '1' ? '50s' : '10s', tags: { endpoint: 'health' },
  });
  let ok = false;
  try { ok = res.status === 200 && res.json('ok') === true; } catch (_) { /* Non-JSON gateway response. */ }
  const seconds = (Date.now() - exec.scenario.startTime) / 1000;
  const stage = seconds < 30 ? 'warmup' : seconds < 50 ? '50' : seconds < 80 ? '100' : seconds < 110 ? '200' : seconds < 140 ? '500' : seconds < 170 ? '1000' : 'recovery';
  failures.add(!ok, { stage });
  latency.add(res.timings.duration, { stage });
  count.add(1, { stage, status: String(res.status) });
  check(res, { 'health: HTTP 200 and ok=true': () => ok });
  if (__ENV.SMOKE === '1') console.log(JSON.stringify({ status: res.status, error: res.error, duration_ms: res.timings.duration }));
}
export function handleSummary(data) {
  return { [__ENV.SUMMARY_PATH || 'health-summary.json']: JSON.stringify(data, null, 2) };
}
