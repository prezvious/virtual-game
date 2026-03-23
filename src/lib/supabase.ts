import { createClient } from "@supabase/supabase-js";

const DEFAULT_SUPABASE_URL = "https://clgzhgczlafvuagbwapk.supabase.co";
const DEFAULT_SUPABASE_ANON_KEY = "sb_publishable_YJxmXd0uOHYMyVygm2vL6g_IsM7IVmo";

export function getSupabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || DEFAULT_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || DEFAULT_SUPABASE_ANON_KEY;
  return { url, anonKey };
}

export function createServerSupabaseClient() {
  const { url, anonKey } = getSupabaseConfig();
  return createClient(url, anonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

export function createServiceSupabaseClient() {
  const { url } = getSupabaseConfig();
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_FUNCTIONS_KEY || "";
  return createClient(url, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}
