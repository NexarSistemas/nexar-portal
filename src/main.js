import { NEXAR_FAVICON_DATA_URI } from './brand/assets.js';
import { signIn, signOut, resolveProfile } from './auth/auth.js';
import { restoreSession, watchSession } from './auth/session.js';
import { getSupabaseClient } from './supabase/client.js';
import { hasDashboardData, loadAdminDashboard } from './dashboard/admin.js';
import { clearClienteDetail, clientValues, createRequestGuard, loadClienteDetail, loadClientes, saveCliente, validateClient } from './dashboard/clientes.js';
import { clearVentaDetail, createRequestGuard as createVentasRequestGuard, loadVentaDetail, loadVentaFormData, loadVentas, saveVenta, searchVentaClientes, validateSale } from './dashboard/ventas.js';
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
const ventaFormRequest = createVentasRequestGuard();
const ventaSaveRequest = createVentasRequestGuard();
const ventaClientSearchRequest = createVentasRequestGuard();
let resolving = false;
let unsubscribe = null;

function showLogin(message = '') {
  clientesRequest.next();
  detalleRequest.next();
  clienteSaveRequest.next();
  ventasRequest.next();
  ventaDetalleRequest.next();
  ventaFormRequest.next();
  ventaSaveRequest.next();
  ventaClientSearchRequest.next();
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
        ventaFormRequest.next();
        ventaSaveRequest.next();
        ventaClientSearchRequest.next();
        ventas = { ...clearVentaDetail(ventas), form: null };
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
    onCreateSale() { void createSaleForm(); },
    onCancelSaleForm() { ventaFormRequest.next(); ventaSaveRequest.next(); ventaClientSearchRequest.next(); ventas = { ...ventas, form: null }; showPortal(); },
    onCreateClientFromSale() {
      ventaFormRequest.next();
      ventaSaveRequest.next();
      ventaClientSearchRequest.next();
      adminView = 'clientes';
      clientesRequest.next();
      detalleRequest.next();
      clienteSaveRequest.next();
      clientes = { ...clientes, selected: null, detail: null, form: { id: null, values: {}, status: 'ready', error: '' }, notice: '' };
      showPortal();
    },
    onAddSaleItem() {
      if (!ventas?.form || ventas.form.status === 'saving') return;
      ventas = { ...ventas, form: { ...ventas.form, values: { ...ventas.form.values, items: [...(ventas.form.values.items ?? []), {}] } } };
      showPortal();
    },
    onRemoveSaleItem(index) {
      if (!ventas?.form || ventas.form.status === 'saving') return;
      const items = (ventas.form.values.items ?? []).filter((_, itemIndex) => itemIndex !== index);
      ventas = { ...ventas, form: { ...ventas.form, values: { ...ventas.form.values, items } } };
      showPortal();
    },
    onChangeSaleItem(index, field, value) {
      if (!ventas?.form || ventas.form.status === 'saving') return;
      const items = [...(ventas.form.values.items ?? [])];
      const item = { ...items[index], [field]: value };
      if (field === 'producto_id') item.plan_id = null;
      items[index] = item;
      ventas = { ...ventas, form: { ...ventas.form, values: { ...ventas.form.values, items } } };
      showPortal();
    },
    onChangeSaleField(field, value) {
      if (!ventas?.form || ventas.form.status === 'saving') return;
      ventas = { ...ventas, form: { ...ventas.form, values: { ...ventas.form.values, [field]: value } } };
      showPortal();
    },
    onSearchSaleClients(query) { void searchSaleClients(query); },
    onSaveSale(values) { void saveSale(values); },
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

async function createSaleForm() {
  if (profile?.rol !== 'admin') return;
  ventaDetalleRequest.next();
  ventaSaveRequest.next();
  const request = ventaFormRequest.next();
  const values = { cliente_id: '', vendedor_id: '', fecha_venta: new Date().toISOString(), moneda: 'ARS', items: [{}] };
  ventas = { ...ventas, selected: null, detail: null, form: { values, catalogo: {}, clientes: [], clientQuery: '', status: 'loading', error: '' }, notice: '' };
  showPortal();
  try {
    const catalogo = await loadVentaFormData(getSupabaseClient());
    if (!ventaFormRequest.isCurrent(request)) return;
    ventas = { ...ventas, form: { values, catalogo, clientes: [], clientQuery: '', status: 'ready', error: '', idempotencyKey: crypto.randomUUID() } };
  } catch {
    if (!ventaFormRequest.isCurrent(request)) return;
    ventas = { ...ventas, form: { values, catalogo: {}, clientes: [], clientQuery: '', status: 'ready', error: 'No pudimos cargar los datos para crear la venta.' } };
  }
  if (profile?.rol === 'admin' && adminView === 'ventas') showPortal();
}

async function searchSaleClients(query) {
  if (profile?.rol !== 'admin' || !ventas?.form || ventas.form.status !== 'ready') return;
  const request = ventaClientSearchRequest.next();
  const form = ventas.form;
  ventas = { ...ventas, form: { ...form, clientQuery: query, clientSearchStatus: 'loading', clientSearchError: '' } };
  showPortal();
  try {
    const clientesEncontrados = await searchVentaClientes(getSupabaseClient(), query);
    if (!ventaClientSearchRequest.isCurrent(request)) return;
    ventas = { ...ventas, form: { ...ventas.form, clientQuery: query, clientes: clientesEncontrados, clientSearchStatus: clientesEncontrados.length ? 'ready' : 'empty', clientSearchError: '' } };
  } catch {
    if (!ventaClientSearchRequest.isCurrent(request)) return;
    ventas = { ...ventas, form: { ...ventas.form, clientQuery: query, clientSearchStatus: 'error', clientSearchError: 'No pudimos buscar clientes. Intentá nuevamente.' } };
  }
  if (profile?.rol === 'admin' && adminView === 'ventas') showPortal();
}

async function saveSale(values) {
  if (profile?.rol !== 'admin' || !ventas?.form || ventas.form.status !== 'ready') return;
  const form = ventas.form;
  const input = { ...values, items: form.values.items };
  const validation = validateSale(input);
  if (validation.error) {
    ventas = { ...ventas, form: { ...form, values: input, error: validation.error } };
    showPortal();
    return;
  }
  const request = ventaSaveRequest.next();
  ventas = { ...ventas, form: { ...form, values: input, status: 'saving', error: '' } };
  showPortal();
  try {
    const created = await saveVenta(getSupabaseClient(), validation.sale, form.idempotencyKey);
    if (!ventaSaveRequest.isCurrent(request)) return;
    const items = [created, ...(ventas.items ?? []).filter((item) => item.id !== created.id)];
    ventas = { ...ventas, status: 'ready', items, form: null, selected: created, detail: { status: 'loading' }, notice: 'La venta se creó correctamente.' };
    showPortal();
    void loadSaleDetail(created);
  } catch {
    if (!ventaSaveRequest.isCurrent(request)) return;
    ventas = { ...ventas, form: { ...form, values: input, status: 'ready', error: 'No pudimos guardar la venta. Revisá los datos e intentá nuevamente.' } };
    showPortal();
  }
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
