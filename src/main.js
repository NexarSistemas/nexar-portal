import { NEXAR_FAVICON_DATA_URI } from './brand/assets.js';
import { signIn, signOut, resolveProfile } from './auth/auth.js';
import { restoreSession, watchSession } from './auth/session.js';
import { getSupabaseClient } from './supabase/client.js';
import { hasDashboardData, loadAdminDashboard } from './dashboard/admin.js';
import { loadClienteDetail, loadClientes } from './dashboard/clientes.js';
import { renderLogin, renderShell } from './ui/shell.js';
import './styles/main.css';

const favicon = document.createElement('link');
favicon.rel = 'icon';
favicon.type = 'image/png';
favicon.href = NEXAR_FAVICON_DATA_URI;
document.head.append(favicon);

const root = document.querySelector('#app');
let profile = null;
let dashboard = null;
let adminView = 'inicio';
let clientes = null;
let resolving = false;
let unsubscribe = null;

function showLogin(message = '') {
  profile = null;
  dashboard = null;
  adminView = 'inicio';
  clientes = null;
  renderLogin(root, { message, onSubmit: async (email, password) => {
    const user = await signIn(email, password);
    profile = await resolveProfile(user.id);
    showPortal();
  } });
}

function showPortal() {
  if (!profile) return;
  const isAdmin = profile.rol === 'admin';
  if (isAdmin && !dashboard) {
    dashboard = { status: 'loading' };
    renderShell(root, profile, async () => { await signOut(); showLogin(); }, dashboard, loadDashboard, adminView, clientes, clientHandlers());
    void loadDashboard();
    return;
  }
  renderShell(root, profile, async () => { await signOut(); showLogin(); }, isAdmin ? dashboard : null, loadDashboard, adminView, clientes, clientHandlers());
}

function clientHandlers() {
  return {
    onNavigate(view) {
      if (profile?.rol !== 'admin') return;
      adminView = view;
      if (view === 'clientes' && !clientes) void loadClients();
      showPortal();
    },
    onSearch(query) { void loadClients(query); },
    onRetryList() { void loadClients(clientes?.query || ''); },
    onSelect(id) {
      const cliente = clientes?.items?.find((item) => item.id === id);
      if (cliente) void loadDetail(cliente);
    },
    onRetryDetail() { if (clientes?.selected) void loadDetail(clientes.selected); },
    onCloseDetail() { clientes = { ...clientes, detail: null, selected: null }; showPortal(); },
  };
}

async function loadDashboard() {
  dashboard = { status: 'loading' };
  showPortal();
  try {
    const metrics = await loadAdminDashboard(getSupabaseClient());
    dashboard = { status: hasDashboardData(metrics) ? 'ready' : 'empty', metrics };
  } catch {
    dashboard = { status: 'error' };
  }
  if (profile?.rol === 'admin') showPortal();
}

async function loadClients(query = '') {
  if (profile?.rol !== 'admin') return;
  clientes = { ...clientes, status: 'loading', items: clientes?.items ?? [], query, detail: null, selected: null };
  showPortal();
  try {
    const items = await loadClientes(getSupabaseClient(), query);
    clientes = { status: items.length ? 'ready' : 'empty', items, query, detail: null, selected: null };
  } catch {
    clientes = { ...clientes, status: 'error', items: [], query };
  }
  if (profile?.rol === 'admin' && adminView === 'clientes') showPortal();
}

async function loadDetail(cliente) {
  if (profile?.rol !== 'admin') return;
  clientes = { ...clientes, selected: cliente, detail: { status: 'loading' } };
  showPortal();
  try {
    clientes = { ...clientes, selected: cliente, detail: { status: 'ready', data: await loadClienteDetail(getSupabaseClient(), cliente) } };
  } catch {
    clientes = { ...clientes, selected: cliente, detail: { status: 'error' } };
  }
  if (profile?.rol === 'admin' && adminView === 'clientes') showPortal();
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
