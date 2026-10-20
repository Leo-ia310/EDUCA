import http from 'k6/http';
import { check } from 'k6';
const base = __ENV.BASE_URL || 'https://nivra-backend-mcc4.onrender.com';
export const options = { vus: 1, iterations: 1, thresholds: { checks: ['rate==1'] } };
export default function () {
  for (const account of JSON.parse(__ENV.ACCOUNTS_JSON || '[]')) {
    const r = http.post(base + '/api/auth/login', JSON.stringify(account), {
      headers: { 'Content-Type': 'application/json' }, timeout: '20s',
    });
    let b = {}; try { b = r.json(); } catch (_) { /* no JSON */ }
    const ok = r.status === 200 && !!b.data?.session?.accessToken;
    console.log(JSON.stringify({ account: account.username, status: r.status, authenticated: ok,
      roles: b.data?.user?.roles, institution: b.data?.institution?.code, error: b.error,
      twoFactorRequired: b.data?.twoFactorRequired, retryAfter: r.headers['Retry-After'],
      rateLimit: r.headers.Ratelimit, policy: r.headers['Ratelimit-Policy'] }));
    check(r, { 'account login succeeds': () => ok });
  }
}
export function handleSummary(data) {
  delete data.setup_data;
  return { [__ENV.SUMMARY_PATH || 'accounts-summary.json']: JSON.stringify(data, null, 2) };
}
