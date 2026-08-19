// Cargador mínimo de backend/.env (sin dependencias). El valor es todo lo que
// sigue al primer '=' (respeta contraseñas con caracteres especiales).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
export const BACKEND_DIR = join(here, '..');
export const ROOT_DIR = join(BACKEND_DIR, '..');

export function loadEnv() {
  const path = join(BACKEND_DIR, '.env');
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch {
    throw new Error(`Falta backend/.env. Copia backend/.env.example y complétalo.`);
  }
  const env = {};
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const i = t.indexOf('=');
    if (i === -1) continue;
    env[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
  return env;
}

export function pgConfig(env) {
  const ref = env.SUPABASE_PROJECT_REF || '';
  return {
    host: env.SUPABASE_DB_HOST,
    port: Number(env.SUPABASE_DB_PORT || 5432),
    user: env.SUPABASE_DB_USER || (ref ? `postgres.${ref}` : 'postgres'),
    password: env.SUPABASE_DB_PASSWORD,
    database: env.SUPABASE_DB_NAME || 'postgres',
    ssl: { rejectUnauthorized: false },
  };
}
