import { createClient } from '@supabase/supabase-js';

let client;

export function getSupabaseClient() {
  const { VITE_SUPABASE_URL: url, VITE_SUPABASE_ANON_KEY: anonKey } = import.meta.env;
  if (!url || !anonKey) throw new Error('Falta la configuración pública de Supabase.');
  client ??= createClient(url, anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });
  return client;
}
