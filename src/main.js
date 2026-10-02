import { NEXAR_FAVICON_DATA_URI } from './brand/assets.js';
import { signIn, signOut, resolveProfile } from './auth/auth.js';
import { restoreSession, watchSession } from './auth/session.js';
import { getSupabaseClient } from './supabase/client.js';
import { hasDashboardData, loadAdminDashboard } from './dashboard/admin.js';
import { clearClienteDetail, clientValues, createRequestGuard, loadClienteDetail, loadClientes, saveCliente, validateClient } from './dashboard/clientes.js';
import { clearVentaDetail, createRequestGuard as createVentasRequestGuard, loadVentaDetail, loadVentas } from './dashboard/ventas.js';
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
let ventas = null;
const clientesRequest = createRequestGuard();
const detalleRequest = createRequestGuard();
const clienteSaveRequest = createRequestGuard();
const ventasRequest = createVentasRequestGuard();
const ventaDetalleRequest = createVentasRequestGuard();
let resolving = false;
let unsubscribe = null;

function showLogin(message = '') {
  clientesRequest.next();
  detalleRequest.next();
  clienteSaveRequest.next();
  ventasRequest.next();
  ventaDetalleRequest.next();
  profile = null;
  dashboard = null;
  adminView = 'inicio';
  clientes = null;
  ventas = null;
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
    renderShell(root, profile, async () => { await signOut(); showLogin(); }, dashboard, loadDashboard, adminView, clientes, clientHandlers(), ventas);
    void loadDashboard();
    return;
  }
  renderShell(root, profile, async () => { await signOut(); showLogin(); }, isAdmin ? dashboard : null, loadDashboard, adminView, clientes, clientHandlers(), ventas);
}

function clientHandlers() {
  return {
    onNavigate(view) {
      if (profile?.rol !== 'admin') return;
      adminView = view;
      if (view !== 'clientes') {
        clientesRequest.next();
        detalleRequest.next();
        clienteSaveRequest.next();
        clientes = { ...clearClienteDetail(clientes), form: null };
      }
      if (view !== 'ventas') {
        ventaDetalleRequest.next();
        ventas = clearVentaDetail(ventas);
      }
      if (view === 'clientes' && !clientes) void loadClients();
      if (view === 'ventas' && !ventas) void loadSales();
      showPortal();
    },
    onSearch(query) { void loadClients(query); },
    onCreateClient() {
      clientesRequest.next();
      detalleRequest.next();
      clienteSaveRequest.next();
      clientes = { ...clientes, selected: null, detail: null, form: { id: null, values: {}, status: 'ready', error: '' }, notice: '' };
      showPortal();
    },
    onEditClient() {
      const cliente = clientes?.detail?.data?.cliente;
      if (!cliente) return;
      clientesRequest.next();
      detalleRequest.next();
      clienteSaveRequest.next();
      clientes = { ...clientes, form: { id: cliente.id, values: clientValues(cliente), status: 'ready', error: '' }, notice: '' };
      showPortal();
    },
    onCancelClientForm() {
      const query = clientes?.query || '';
      const reloadList = clientes?.status === 'loading';
      clienteSaveRequest.next();
      clientes = { ...clientes, form: null };
      showPortal();
      if (reloadList) void loadClients(query);
    },
    onSaveClient(values) { void saveClient(values); },
    onRetryList() { void loadClients(clientes?.query || ''); },
    onSelect(id) {
      const cliente = clientes?.items?.find((item) => item.id === id);
      if (cliente) void loadDetail(cliente);
    },
    onRetryDetail() { if (clientes?.selected) void loadDetail(clientes.selected); },
    onCloseDetail() { detalleRequest.next(); clienteSaveRequest.next(); clientes = clearClienteDetail(clientes); showPortal(); },
    onFilterSales(filters) { void loadSales(filters); },
    onRetrySales() { void loadSales(ventas?.filters || {}); },
    onSelectSale(id) {
      const venta = ventas?.items?.find((item) => item.id === id);
      if (venta) void loadSaleDetail(venta);
    },
    onRetrySaleDetail() { if (ventas?.selected) void loadSaleDetail(ventas.selected); },
    onCloseSaleDetail() { ventaDetalleRequest.next(); ventas = clearVentaDetail(ventas); showPortal(); },
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
  const request = clientesRequest.next();
  detalleRequest.next();
  clientes = { ...clientes, status: 'loading', items: clientes?.items ?? [], query, detail: null, selected: null };
  showPortal();
  try {
    const items = await loadClientes(getSupabaseClient(), query);
    if (!clientesRequest.isCurrent(request)) return;
    clientes = { ...clientes, status: items.length ? 'ready' : 'empty', items, query, detail: null, selected: null };
  } catch {
    if (!clientesRequest.isCurrent(request)) return;
    clientes = { ...clientes, status: 'error', items: [], query };
  }
  if (profile?.rol === 'admin' && adminView === 'clientes') showPortal();
}

async function loadDetail(cliente) {
  if (profile?.rol !== 'admin') return;
  const request = detalleRequest.next();
  clienteSaveRequest.next();
  clientes = { ...clientes, selected: cliente, detail: { status: 'loading' }, form: null };
  showPortal();
  try {
    const data = await loadClienteDetail(getSupabaseClient(), cliente);
    if (!detalleRequest.isCurrent(request)) return;
    clientes = { ...clientes, selected: cliente, detail: { status: 'ready', data } };
  } catch {
    if (!detalleRequest.isCurrent(request)) return;
    clientes = { ...clientes, selected: cliente, detail: { status: 'error' } };
  }
  if (profile?.rol === 'admin' && adminView === 'clientes') showPortal();
}

async function saveClient(values) {
  if (profile?.rol !== 'admin' || !clientes?.form || clientes.form.status === 'saving') return;
  const validation = validateClient(values);
  if (validation.error) {
    clientes = { ...clientes, form: { ...clientes.form, values, status: 'ready', error: validation.error } };
    showPortal();
    return;
  }
  const form = clientes.form;
  const request = clienteSaveRequest.next();
  clientes = { ...clientes, form: { ...form, values, status: 'saving', error: '' } };
  showPortal();
  try {
    const saved = await saveCliente(getSupabaseClient(), form.id, validation.client);
    if (!clienteSaveRequest.isCurrent(request)) return;
    const items = form.id ? (clientes.items ?? []).map((item) => item.id === saved.id ? saved : item) : [saved, ...(clientes.items ?? [])];
    clientes = { ...clientes, status: items.length ? 'ready' : 'empty', items, form: null, notice: form.id ? 'Los cambios se guardaron correctamente.' : 'El cliente se creó correctamente.' };
    void loadDetail(saved);
  } catch {
    if (!clienteSaveRequest.isCurrent(request)) return;
    clientes = { ...clientes, form: { ...form, values, status: 'ready', error: 'No pudimos guardar el cliente. Intentá nuevamente.' } };
    showPortal();
  }
}

async function loadSales(filters = {}) {
  if (profile?.rol !== 'admin') return;
  const request = ventasRequest.next();
  ventaDetalleRequest.next();
  ventas = { ...ventas, status: 'loading', items: ventas?.items ?? [], filters, detail: null, selected: null };
  showPortal();
  try {
    const items = await loadVentas(getSupabaseClient(), filters);
    if (!ventasRequest.isCurrent(request)) return;
    ventas = { status: items.length ? 'ready' : 'empty', items, filters, detail: null, selected: null };
  } catch {
    if (!ventasRequest.isCurrent(request)) return;
    ventas = { ...ventas, status: 'error', items: [], filters };
  }
  if (profile?.rol === 'admin' && adminView === 'ventas') showPortal();
}

async function loadSaleDetail(venta) {
  if (profile?.rol !== 'admin') return;
  const request = ventaDetalleRequest.next();
  ventas = { ...ventas, selected: venta, detail: { status: 'loading' } };
  showPortal();
  try {
    const data = await loadVentaDetail(getSupabaseClient(), venta);
    if (!ventaDetalleRequest.isCurrent(request)) return;
    ventas = { ...ventas, selected: venta, detail: { status: 'ready', data } };
  } catch {
    if (!ventaDetalleRequest.isCurrent(request)) return;
    ventas = { ...ventas, selected: venta, detail: { status: 'error' } };
  }
  if (profile?.rol === 'admin' && adminView === 'ventas') showPortal();
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
