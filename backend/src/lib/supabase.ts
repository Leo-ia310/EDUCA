import { createClient } from "@supabase/supabase-js";
import { AsyncLocalStorage } from "node:async_hooks";

import { env } from "./env";

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
  env.supabaseServiceRoleKey || env.supabaseAnonKey,
  { auth: authOptions },
);

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
