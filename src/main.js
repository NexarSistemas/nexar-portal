import { NEXAR_FAVICON_DATA_URI } from './brand/assets.js';
import { signIn, signOut, resolveProfile } from './auth/auth.js';
import { restoreSession, watchSession } from './auth/session.js';
import { getSupabaseClient } from './supabase/client.js';
import { renderLogin, renderShell } from './ui/shell.js';
import './styles/main.css';

const favicon = document.createElement('link');
favicon.rel = 'icon';
favicon.type = 'image/png';
favicon.href = NEXAR_FAVICON_DATA_URI;
document.head.append(favicon);

const root = document.querySelector('#app');
let profile = null;
let resolving = false;
let unsubscribe = null;

function showLogin(message = '') {
  profile = null;
  renderLogin(root, { message, onSubmit: async (email, password) => {
    const user = await signIn(email, password);
    profile = await resolveProfile(user.id);
    showPortal();
  } });
}

function showPortal() {
  if (!profile) return;
  renderShell(root, profile, async () => { await signOut(); showLogin(); });
}

async function handleAuthUser(user) {
  if (!user || resolving) return;
  resolving = true;
  try { profile = await resolveProfile(user.id); showPortal(); }
  catch { showLogin('No pudimos validar el acceso. Iniciá sesión nuevamente.'); }
  finally { resolving = false; }
}

async function start() {
  root.innerHTML = '<main class="loading" role="status">Validando sesión…</main>';
  try {
    const client = getSupabaseClient();
    unsubscribe = watchSession(client, (user) => user ? void handleAuthUser(user) : showLogin());
    profile = await restoreSession(client);
    if (profile) showPortal();
    else showLogin();
  } catch (error) {
    showLogin(error.message.includes('configuración')
      ? 'Configurá las variables públicas de Supabase para iniciar.'
      : 'No pudimos validar el acceso. Iniciá sesión nuevamente.');
  }
}

window.addEventListener('pagehide', () => unsubscribe?.(), { once: true });
void start();
