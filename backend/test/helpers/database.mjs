import EmbeddedPostgres from 'embedded-postgres';
import { randomBytes } from 'node:crypto';
import { mkdtemp, readFile, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';

// Never reads .env or accepts a remote URL. Integration tests own a temporary
// loopback-only PostgreSQL instance and cannot reach the production database.
export async function database({through=null}={}) {
  const port = await new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
  });
  const root = await mkdtemp(join(tmpdir(), 'educa-db-test-'));
  const instance = new EmbeddedPostgres({
    databaseDir: join(root, 'data'), port, user: 'postgres',
    password: randomBytes(24).toString('hex'), persistent: false,
    initdbFlags: ['--encoding=UTF8'],
    postgresFlags: ['-h', '127.0.0.1', '-c', 'log_min_messages=warning'],
    onLog() {}, onError() {},
  });
  const clients = new Set();
  async function connect() {
    const client = instance.getPgClient('postgres', '127.0.0.1');
    await client.connect();
    await client.query("set statement_timeout='10s'; set lock_timeout='5s'");
    clients.add(client);
    return client;
  }
  async function close() {
    await Promise.allSettled([...clients].map(client => client.end()));
    await instance.stop();
  }
  try {
    await instance.initialise();
    await instance.start();
    const admin = await connect();
    // Only Supabase-managed schemas are represented here. All application
    // tables, RLS policies and functions come from the actual migrations.
    await admin.query(`
      create role anon nologin; create role authenticated nologin;
      create role service_role nologin bypassrls;
      create schema auth; create schema storage;
      create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb default '{}'::jsonb);
      create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id));
      create function auth.jwt() returns jsonb language sql stable as
        $$ select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}') $$;
      create function auth.uid() returns uuid language sql stable as
        $$ select (auth.jwt()->>'sub')::uuid $$;
      create table storage.buckets(id text primary key,name text,public boolean);
      create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,owner_id text);
      alter table storage.objects enable row level security;
      create function storage.foldername(text) returns text[] language sql immutable as
        $$ select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1] $$;
      grant usage on schema auth,storage,public to anon,authenticated,service_role;
      grant execute on all functions in schema auth,storage to anon,authenticated,service_role;
      alter default privileges in schema public grant select,insert,update,delete on tables to authenticated;
      alter default privileges in schema public grant usage,select on sequences to authenticated;
    `);
    const migrations = new URL('../../../supabase/migrations/', import.meta.url);
    const names=(await readdir(migrations)).filter(n=>n.endsWith('.sql')).sort();
    if(through!==null&&!names.includes(through))throw new Error(`Unknown test migration: ${through}`);
    for (const name of names.filter(name=>through===null||name<=through)) {
      // Historical demo-only seeds assume manually provisioned group/student
      // IDs. Tests provision their own tenants; these contain no application DDL.
      if (['0011_demo_rich.sql', '0013_demo_more_children.sql'].includes(name)) continue;
      const source=await readFile(new URL(name,migrations),'utf8');
      try { await admin.query(source); }
      catch (error) {
        const line=error.position ? source.slice(0,Number(error.position)-1).split('\n').length : '?';
        throw new Error(`Migration ${name}, line ${line}: ${error.message}${error.where ? ` (${error.where})` : ''}`, { cause: error });
      }
    }
    return { admin, connect, close, release: async()=>{
      const finished=[...clients].filter(client=>client!==admin);
      await Promise.allSettled(finished.map(client=>client.end()));
      finished.forEach(client=>clients.delete(client));
    } };
  } catch (error) {
    await close();
    throw error;
  }
}

export async function asUser(client, userId, institutionId) {
  await client.query('set role authenticated');
  await client.query("select set_config('request.jwt.claims',$1,false)", [JSON.stringify({
    sub: userId, institution_id: String(institutionId), role: 'authenticated',
  })]);
}
