// =============================================================================
// developer_api_e2e.mjs - E2E de /api/developer.
//
// Arranca backend/dist/server.js, inicia sesion como admin/teacher y verifica
// lectura, create, patch, archive y bloqueo por rol no administrativo.
// =============================================================================
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import pg from 'pg';
import { loadEnv, pgConfig, BACKEND_DIR } from './env.mjs';

const env = loadEnv();
const PORT = Number(process.env.E2E_DEVELOPER_PORT || 3389);
const API_BASE = `http://127.0.0.1:${PORT}`;
const mark = `E2E developer dashboard ${Date.now()}`;

let pass = 0;
let fail = 0;

function check(name, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` (${detail})` : ''}`);
  ok ? pass++ : fail++;
}

async function fetchJson(url, options = {}) {
  const response = await fetch(url, options);
  let body = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }
  return { response, body };
}

async function waitForHealth(child) {
  for (let i = 0; i < 40; i++) {
    if (child.exitCode != null) {
      throw new Error(`Backend termino antes de /health (code=${child.exitCode}).`);
    }
    try {
      const { response, body } = await fetchJson(`${API_BASE}/health`);
      if (response.ok && body?.ok === true) return;
    } catch {
      // Esperar siguiente intento.
    }
    await sleep(250);
  }
  throw new Error('Backend no respondio /health.');
}

async function startBackend() {
  const child = spawn(process.execPath, ['dist/server.js'], {
    cwd: BACKEND_DIR,
    env: { ...process.env, ...env, PORT: String(PORT) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', (chunk) => process.stdout.write(`[backend] ${chunk}`));
  child.stderr.on('data', (chunk) => process.stderr.write(`[backend] ${chunk}`));
  await waitForHealth(child);
  return child;
}

async function login(email) {
  const { response, body } = await fetchJson(
    `${env.SUPABASE_URL}/auth/v1/token?grant_type=password`,
    {
      method: 'POST',
      headers: { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'demo1234' }),
    },
  );
  if (!response.ok || !body?.access_token) {
    throw new Error(`No se pudo iniciar sesion con ${email}`);
  }
  return body.access_token;
}

function headers(token) {
  return {
    Authorization: `Bearer ${token}`,
    apikey: env.SUPABASE_ANON_KEY,
    'Content-Type': 'application/json',
  };
}

async function cleanup(client) {
  await client.query(
    `delete from developer_audit_events
      where entity_table = 'developer_tasks'
        and coalesce(data_after->>'title', data_before->>'title') like $1`,
    [`${mark}%`],
  );
  await client.query(`delete from developer_tasks where title like $1`, [`${mark}%`]);
}

async function main() {
  const backend = await startBackend();
  const client = new pg.Client(pgConfig(env));
  await client.connect();

  try {
    const admin = await login('admin@educa360.com');
    const teacher = await login('teacher@educa360.com');
    check('login admin/teacher', true);

    const summary = await fetchJson(`${API_BASE}/api/developer/summary`, {
      headers: headers(admin),
    });
    check('admin GET /api/developer/summary', summary.response.ok && summary.body?.ok === true);

    const modules = await fetchJson(`${API_BASE}/api/developer/modules`, {
      headers: headers(admin),
    });
    check(
      'admin GET /api/developer/modules',
      modules.response.ok && Array.isArray(modules.body?.data) && modules.body.data.length > 0,
      `n=${modules.body?.data?.length ?? 0}`,
    );

    const apis = await fetchJson(`${API_BASE}/api/developer/apis?frontendStatus=pending`, {
      headers: headers(admin),
    });
    check(
      'admin GET /api/developer/apis pending',
      apis.response.ok && Array.isArray(apis.body?.data) && apis.body.data.length > 0,
      `n=${apis.body?.data?.length ?? 0}`,
    );

    const created = await fetchJson(`${API_BASE}/api/developer/tasks`, {
      method: 'POST',
      headers: headers(admin),
      body: JSON.stringify({
        title: `${mark} task`,
        moduleKey: 'apis',
        priority: 'low',
        backendReady: true,
      }),
    });
    const taskId = created.body?.data?.task?.id;
    check('admin POST /api/developer/tasks', created.response.status === 201 && Number(taskId) > 0);

    const patched = await fetchJson(`${API_BASE}/api/developer/tasks/${taskId}`, {
      method: 'PATCH',
      headers: headers(admin),
      body: JSON.stringify({
        status: 'done',
        completedAt: new Date().toISOString(),
      }),
    });
    check('admin PATCH /api/developer/tasks/:id', patched.response.ok && patched.body?.data?.task?.status === 'done');

    const archived = await fetchJson(`${API_BASE}/api/developer/tasks/${taskId}`, {
      method: 'DELETE',
      headers: headers(admin),
    });
    check('admin DELETE /api/developer/tasks/:id archives', archived.response.ok && archived.body?.data?.task?.deleted_at != null);

    const forbidden = await fetchJson(`${API_BASE}/api/developer/summary`, {
      headers: headers(teacher),
    });
    check('teacher blocked from /api/developer', forbidden.response.status === 403);
  } finally {
    await cleanup(client);
    await client.end();
    backend.kill();
  }

  console.log(`\n${pass} PASS - ${fail} FAIL\n`);
  process.exit(fail ? 1 : 0);
}

main().catch((error) => {
  console.error(`FATAL: ${error.message}`);
  process.exit(1);
});
