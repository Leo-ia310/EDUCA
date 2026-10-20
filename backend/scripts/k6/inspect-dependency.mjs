// Bounded, read-only calls isolate the error hidden by database_unavailable.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const env = require('dotenv').parse(fs.readFileSync(path.resolve(import.meta.dirname, '../../.env')));
const { createClient } = require('@supabase/supabase-js');
const concurrency = Number(process.env.DEPENDENCY_CONCURRENCY || 4);
if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 8) throw Error('Concurrency must be 1–8');
const result = { at: new Date().toISOString(), concurrency, backendRequests: 0, dependencyRequests: 0, calls: [] };
let token;
try {
  result.backendRequests++;
  const response = await fetch('https://nivra-backend-mcc4.onrender.com/api/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: process.env.TEST_USERNAME, password: process.env.TEST_PASSWORD, institutionCode: 'BIGSCHOOL' }), signal: AbortSignal.timeout(70000) });
  const body = await response.json(); token = body.data?.session?.accessToken;
  if (response.status !== 200 || !token || body.data?.institution?.code !== 'BIGSCHOOL') throw Error('Teacher diagnostic login failed');
  await Promise.all(Array.from({ length: concurrency }, async (_, i) => {
    const t = performance.now(); result.dependencyRequests++;
    const r = await fetch(env.SUPABASE_URL + '/rest/v1/rpc/assignment_feed', { method: 'POST', headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify({ p_limit: 20 }), signal: AbortSignal.timeout(25000) });
    let b; try { b = await r.json(); } catch { /* no payload persisted */ }
    const row = { i, status: r.status, ms: performance.now() - t, sqlCode: b?.code, error: b?.message, resultCount: b?.assignments?.length };
    result.calls.push(row); console.log(JSON.stringify(row));
  }));
} finally {
  if (token) {
    const admin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    result.dependencyRequests++;
    const { error } = await admin.auth.admin.signOut(token, 'local'); result.sessionClosed = !error;
  }
  const out=path.resolve(import.meta.dirname, '../../stress-results',process.env.RUN_LABEL || '2026-10-20');
  fs.mkdirSync(out,{recursive:true});
  fs.writeFileSync(path.join(out, `dependency-isolation-${concurrency}.json`), JSON.stringify(result, null, 2));
}
