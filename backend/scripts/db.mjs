// =============================================================================
// db.mjs — aplica SQL a la base Supabase usando SOLO la DB password de
// backend/.env (no requiere que la CLI de Supabase sea dueña del proyecto).
//
// Uso:
//   node db.mjs check                 # conectividad + resumen
//   node db.mjs migrate               # aplica migraciones nuevas (tracking)
//   node db.mjs seed                  # seed.sql + seed_auth_users.sql
//   node db.mjs apply <file.sql>...   # aplica archivos concretos (transaccional)
// =============================================================================
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import pg from 'pg';
import { loadEnv, pgConfig, BACKEND_DIR, ROOT_DIR } from './env.mjs';

const SUPA = join(ROOT_DIR, 'supabase');
const MIGR = join(SUPA, 'migrations');
const BASELINE = ['0001', '0002', '0003', '0004', '0005', '0006', '0007']; // ya aplicadas a mano

async function connect() {
  const client = new pg.Client(pgConfig(loadEnv()));
  await client.connect();
  return client;
}

async function applyFile(client, path, { tx = true } = {}) {
  const sql = readFileSync(path, 'utf8');
  process.stdout.write(`→ ${path.replace(ROOT_DIR, 'EDUCA')} ... `);
  try {
    if (tx) await client.query('begin');
    await client.query(sql);
    if (tx) await client.query('commit');
    console.log('OK');
    return true;
  } catch (e) {
    if (tx) await client.query('rollback').catch(() => {});
    console.log('ERROR:', e.message);
    return false;
  }
}

async function ensureTracking(client) {
  await client.query(`create table if not exists public._applied_scripts (
    name text primary key, applied_at timestamptz default now())`);
  const { rows } = await client.query('select count(*)::int n from public._applied_scripts');
  if (rows[0].n === 0) {
    const exists = await client.query("select to_regclass('public.institutions') r");
    if (exists.rows[0].r) {
      // Base preexistente: marcar 0001–0007 como ya aplicadas.
      for (const f of readdirSync(MIGR).filter(f => BASELINE.some(b => f.startsWith(b)))) {
        await client.query('insert into public._applied_scripts(name) values($1) on conflict do nothing', [f]);
      }
      console.log('Baseline 0001–0007 marcadas como aplicadas.');
    }
  }
}

async function cmdCheck(client) {
  const q = async (l, s) => { const r = await client.query(s); console.log(l, JSON.stringify(r.rows[0])); };
  await q('institución EDU360:', "select id, code, name from institutions where code='EDU360'");
  await q('conteos:', `select
    (select count(*)::int from classes) classes,
    (select count(*)::int from conversations) conversations,
    (select count(*)::int from auth.users) auth_users,
    (select case when to_regclass('public._applied_scripts') is null then 0
                 else (select count(*)::int from public._applied_scripts) end) applied`.replace(/\s+/g, ' '));
}

async function cmdMigrate(client) {
  await ensureTracking(client);
  const applied = new Set((await client.query('select name from public._applied_scripts')).rows.map(r => r.name));
  const files = readdirSync(MIGR).filter(f => f.endsWith('.sql')).sort();
  let n = 0;
  for (const f of files) {
    if (applied.has(f)) continue;
    const ok = await applyFile(client, join(MIGR, f));
    if (ok) { await client.query('insert into public._applied_scripts(name) values($1) on conflict do nothing', [f]); n++; }
    else throw new Error(`Migración ${f} falló; deteniendo.`);
  }
  console.log(n === 0 ? 'Nada nuevo que aplicar.' : `${n} migración(es) aplicada(s).`);
}

async function main() {
  const [cmd, ...args] = process.argv.slice(2);
  const client = await connect();
  try {
    if (cmd === 'check') await cmdCheck(client);
    else if (cmd === 'migrate') await cmdMigrate(client);
    else if (cmd === 'seed') {
      await applyFile(client, join(SUPA, 'seed.sql'));
      await applyFile(client, join(SUPA, 'seed_auth_users.sql'));
    } else if (cmd === 'apply') {
      if (!args.length) throw new Error('Uso: node db.mjs apply <file.sql>...');
      for (const f of args) await applyFile(client, f);
    } else {
      console.log('Comandos: check | migrate | seed | apply <file.sql>...');
      process.exitCode = 1;
    }
  } finally {
    await client.end();
  }
}

main().catch(e => { console.error('FATAL:', e.message); process.exit(1); });
