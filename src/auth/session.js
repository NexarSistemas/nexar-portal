import { resolveProfile } from './auth.js';

export async function restoreSession(client) {
  const { data, error } = await client.auth.getSession();
  if (error) throw new Error('No pudimos restaurar la sesión. Iniciá sesión nuevamente.');
  if (!data.session?.user) return null;
  return resolveProfile(data.session.user.id);
}

export function watchSession(client, onChange) {
  const { data } = client.auth.onAuthStateChange((event, session) => {
    if (event === 'SIGNED_OUT') onChange(null);
    else if (event === 'SIGNED_IN' && session?.user) onChange(session.user);
  });
  return () => data.subscription.unsubscribe();
}
