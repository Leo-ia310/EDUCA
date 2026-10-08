import { createClient } from "@supabase/supabase-js";
import { AsyncLocalStorage } from "node:async_hooks";

import { env } from "./env";
import { HttpError } from "./errors";

type SupabaseClientLike = ReturnType<typeof createClient<any>>;

const authOptions = {
  persistSession: false,
  autoRefreshToken: false,
};

const requestClients = new AsyncLocalStorage<SupabaseClientLike>();

function createUserClient(accessToken: string) {
  return createClient(env.supabaseUrl, env.supabaseAnonKey, {
    auth: authOptions,
    global: {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    },
  });
}

const fallbackClient = createClient(
  env.supabaseUrl,
  env.supabaseAnonKey,
  { auth: authOptions },
);

export const supabasePublic = fallbackClient;

export const supabaseServiceRole = env.supabaseServiceRoleKey
  ? createClient(env.supabaseUrl, env.supabaseServiceRoleKey, {
    auth: authOptions,
  })
  : null;

export function requireSupabaseServiceRole() {
  if (supabaseServiceRole == null) {
    throw new HttpError(
      503,
      "SUPABASE_SERVICE_ROLE_KEY es requerida para esta operación backend.",
      "service_role_required",
    );
  }
  return supabaseServiceRole as any;
}

export function createAuthorizedSupabase(accessToken: string) {
  return createUserClient(accessToken);
}

export function withRequestSupabase<T>(
  accessToken: string,
  callback: () => T,
) {
  return requestClients.run(createUserClient(accessToken), callback);
}

export function currentSupabaseClient() {
  return requestClients.getStore() ?? fallbackClient;
}

export const supabaseAdmin = new Proxy({} as SupabaseClientLike, {
  get(_target, property, receiver) {
    const client = currentSupabaseClient() as any;
    const value = Reflect.get(client, property, receiver);
    return typeof value === "function" ? value.bind(client) : value;
  },
});
