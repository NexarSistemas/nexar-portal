import { getSupabaseClient } from '../supabase/client.js';

export const LOGIN_ERROR = 'No pudimos iniciar sesión. Verificá tus datos e intentá nuevamente.';
export const PROFILE_ERROR = 'No pudimos validar el acceso. Iniciá sesión nuevamente.';

export function isValidProfile(profile) {
  if (!profile || profile.activo !== true) return false;
  if (profile.rol === 'admin') return true;
  return profile.rol === 'vendedor' && typeof profile.vendedor_id === 'string' && profile.vendedor_id.length > 0;
}

export function viewForRole(role) {
  if (role === 'admin') return 'admin';
  if (role === 'vendedor') return 'vendedor';
  return null;
}

export async function signIn(email, password) {
  const { data, error } = await getSupabaseClient().auth.signInWithPassword({ email, password });
  if (error || !data.user) throw new Error(LOGIN_ERROR);
  return data.user;
}

export async function resolveProfile(userId) {
  const { data, error } = await getSupabaseClient()
    .from('perfiles')
    .select('user_id,nombre,rol,vendedor_id,activo')
    .eq('user_id', userId)
    .maybeSingle();

  if (error || !isValidProfile(data)) {
    await getSupabaseClient().auth.signOut({ scope: 'local' });
    throw new Error(PROFILE_ERROR);
  }
  return data;
}

export async function signOut() {
  const { error } = await getSupabaseClient().auth.signOut();
  if (error) throw new Error('No pudimos cerrar la sesión. Intentá nuevamente.');
}
