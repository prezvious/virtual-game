import { createClient, SupabaseClient } from "@supabase/supabase-js";
import { getSupabaseConfig } from "./supabase";

let clientInstance: SupabaseClient | null = null;

export function getClientSupabase(): SupabaseClient {
  if (clientInstance) return clientInstance;

  const { url, anonKey } = getSupabaseConfig();

  clientInstance = createClient(url, anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  });

  return clientInstance;
}
