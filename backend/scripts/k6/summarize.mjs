import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
const directory = process.argv[2] || 'backend/stress-results/2026-10-17';
const results = {};
for (const file of readdirSync(directory).filter(f => f.endsWith('.json') && !f.endsWith('-coverage.json') && !f.startsWith('discarded-') && f !== 'overview.json')) {
  const data = JSON.parse(readFileSync(join(directory, file), 'utf8').replace(/^\uFEFF/, ''));
  const m = data.metrics || {};
  const values = key => m[key]?.values;
  const stages = Object.keys(m).filter(k => /^(application_duration|health_duration)\{stage:/.test(k))
    .map(k => {
      const stage = k.match(/stage:([^}]+)/)[1];
      return { stage, latency: values(k), errors: values(`${m.application_failed ? 'application_failed' : 'service_failures'}{stage:${stage}}`),
        requests: values(`${m.responses ? 'responses' : 'health_responses'}{stage:${stage}}`)?.count };
    }).filter(x => x.requests > 0);
  const endpoints = Object.keys(m).filter(k => /^application_duration\{endpoint:/.test(k))
    .map(k => ({ endpoint: k.match(/endpoint:([^}]+)/)[1], ...values(k) }))
    .filter(e => e.max > 0).sort((a,b) => b['p(95)'] - a['p(95)']);
  results[file] = { duration_ms: data.state?.testRunDurationMs,
    requests: values('responses') || values('health_responses') || values('http_reqs'),
    failures: values('application_failed') || values('service_failures'), rate_limited: values('rate_limited'),
    latency: values('application_duration') || values('health_duration') || values('http_req_duration'),
    dropped: values('dropped_iterations'), max_vus: values('vus_max'), stages, slowest: endpoints.slice(0, 10),
    statuses: Object.fromEntries(Object.keys(m).filter(k => /^responses\{status:/.test(k)).map(k => [k.match(/status:([^}]+)/)[1], values(k)?.count]).filter(([,v]) => v)),
  };
}
writeFileSync(join(directory, 'overview.json'), JSON.stringify(results, null, 2));
for (const [file, r] of Object.entries(results)) console.log(JSON.stringify({ file, ...r }));
