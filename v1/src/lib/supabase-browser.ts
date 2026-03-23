import { createClient, SupabaseClient } from "@supabase/supabase-js";
import { getSupabaseConfig } from "./supabase";

let browserClient: SupabaseClient | null = null;

export function getSupabaseBrowser(): SupabaseClient {
  if (browserClient) return browserClient;

  const { url, anonKey } = getSupabaseConfig();
  browserClient = createClient(url, anonKey, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true,
    },
  });

  return browserClient;
}
