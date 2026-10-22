import {ConcurrencyGate} from './concurrency-gate';
import {env} from './env';

// Auth and PostgREST share the project's database resources. Protect them as
// one dependency per backend process; no authorization results are cached.
export const dependencyAdmission = new ConcurrencyGate(env.supabaseMaxConcurrent, env.supabaseMaxPending);
export const databaseAdmission = new ConcurrencyGate(env.supabaseMaxDatabase, env.supabaseMaxPending);
