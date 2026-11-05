import { NEXAR_FAVICON_DATA_URI, NEXAR_LOGO_DATA_URI } from '../brand/assets.js';
import { getSupabaseClient } from '../supabase/client.js';
import {
  cancelRedeem,
  confirmRedeem,
  createEarn,
  getSessionUser,
  listCustomers,
  listCheckIns,
  listPendingOperations,
  resolveStaffAccess,
  searchAccount,
  signOutFidelizacion,
} from './api.js';
import {
  commerceQrUrl,
  createActionLock,
  operationPresentation,
  panelStateText,
  UnauthorizedStaffError,
} from './contracts.js';
import {
  createEarnAttemptStore,
  earnFlowNotice,
  runEarnCreation,
  runSuccessfulRefresh,
} from './earn-flow.js';
import { createCommerceQrImage } from './qr.js';
import { loadCheckIns } from './check-in.js';
import './styles.css';

const root = document.querySelector('#app');
const checkInEnabled = import.meta.env.VITE_CHECK_IN_QR_ENABLED === 'true';
let checkIns = [];
let checkInLoading = false;
let checkInError = false;
let checkInTimer;
let client;
const lock = createActionLock();
const earnAttempts = createEarnAttemptStore(() => crypto.randomUUID());
const state = {
  access: null,
  account: null,
  operations: [],
  searchedEmail: '',
  customerSearch: '',
  customers: [],
  customerOffset: 0,
  customerError: null,
  loading: false,
  notice: null,
  commerceQrUrl: null,
  commerceQrImage: null,
};

function loginUrl() {
  return new URL('../login/', window.location.href);
}

function addFavicon() {
  const favicon = document.createElement('link');
  favicon.rel = 'icon';
  favicon.type = 'image/png';
  favicon.href = NEXAR_FAVICON_DATA_URI;
  document.head.append(favicon);
}

function renderLoading() {
  root.innerHTML = `<main class="fidelity-loading" role="status">${panelStateText('loading')}</main>`;
}

function renderUnauthorized() {
  root.innerHTML = `
    <main class="fidelity-centered">
      <section class="fidelity-message-card">
        <p class="fidelity-eyebrow">Acceso no autorizado</p>
        <h1>No podés ingresar al panel</h1>
        <p class="fidelity-muted">${panelStateText('unauthorized')}</p>
        <button class="fidelity-button fidelity-button-primary" id="logout" type="button">Cerrar sesión</button>
      </section>
    </main>`;
  root.querySelector('#logout').addEventListener('click', logout);
}

function renderPanel() {
  const accountSection = state.account ? renderAccount() : renderInitialState();
  root.innerHTML = `
    <div class="fidelity-app">
      <header class="fidelity-header">
        <div class="fidelity-brand">
          <img src="${NEXAR_LOGO_DATA_URI}" alt="Nexar Sistemas" />
          <span>Nexar Fidelización</span>
        </div>
        <div class="fidelity-session">
          <span>${escapeHtml(state.access.tenantName)}</span>
          <span class="fidelity-role">${state.access.role === 'admin' ? 'Administrador' : 'Operador'}</span>
          <button class="fidelity-button fidelity-button-quiet" id="logout" type="button">Cerrar sesión</button>
        </div>
      </header>
      <main class="fidelity-main">
        <section class="fidelity-intro">
          <p class="fidelity-eyebrow">Panel operador</p>
          <h1>Gestión de puntos y canjes</h1>
          <p class="fidelity-muted">Buscá una cuenta por email para acreditar puntos o gestionar sus canjes pendientes.</p>
        </section>
        ${renderCommerceQr()}
        ${renderNotice()}
        ${checkInEnabled ? '<section class="fidelity-card" id="check-ins" aria-live="polite"></section>' : ''}
        ${renderCustomers()}
        <section class="fidelity-card fidelity-search-card" aria-labelledby="search-title">
          <div>
            <p class="fidelity-step">01</p>
            <h2 id="search-title">Buscar cliente</h2>
          </div>
          <form id="search-form" class="fidelity-inline-form">
            <label class="fidelity-sr-only" for="customer-email">Email del cliente</label>
            <input id="customer-email" name="email" type="email" autocomplete="off" placeholder="cliente@ejemplo.com" value="${escapeHtml(state.searchedEmail)}" required />
            <button class="fidelity-button fidelity-button-primary" type="submit" ${state.loading ? 'disabled' : ''}>${state.loading ? 'Buscando…' : 'Buscar'}</button>
          </form>
        </section>
        ${accountSection}
      </main>
    </div>`;
  bindPanelEvents();
  renderCheckIns();
}

function renderCheckIns() {
  const target = root.querySelector('#check-ins');
  if (!target) return;
  target.innerHTML = `<h2>Clientes presentes</h2>${checkInError ? '<p role="alert">No pudimos actualizar los check-ins.</p>' : ''}${checkIns.length ? `<ul>${checkIns.map((item, index) => `<li>${escapeHtml(item.cliente_email || `Cuenta ${item.account_id}`)} <button class="fidelity-button fidelity-button-quiet" type="button" data-check-in="${index}">Seleccionar</button></li>`).join('')}</ul>` : '<p>No hay check-ins vigentes.</p>'}`;
  target.querySelectorAll('[data-check-in]').forEach((button) => button.addEventListener('click', () => {
    const item = checkIns[Number(button.dataset.checkIn)];
    if (item && Date.parse(item.expires_at) > Date.now()) void selectCustomer(item);
  }));
}

async function refreshCheckIns() {
  if (!checkInEnabled || checkInLoading || document.hidden || !state.access) return;
  checkInLoading = true;
  try {
    checkIns = await loadCheckIns(client, listCheckIns, listCustomers);
    checkInError = false;
  } catch (_) {
    checkIns = [];
    checkInError = true;
  } finally {
    checkInLoading = false;
    renderCheckIns();
  }
}

function renderCustomers() {
  return `<section class="fidelity-card" aria-labelledby="customers-title">
    <h2 id="customers-title">Clientes del comercio</h2>
    <form id="customers-form" class="fidelity-inline-form">
      <label class="fidelity-sr-only" for="customer-filter">Buscar por email</label>
      <input id="customer-filter" name="filter" type="search" maxlength="254" placeholder="Buscar por email" value="${escapeHtml(state.customerSearch)}" />
      <button class="fidelity-button fidelity-button-primary" type="submit" ${state.loading ? 'disabled' : ''}>Buscar</button>
    </form>
    ${state.customerError ? `<p role="alert">${escapeHtml(state.customerError)}</p>` : ''}
    ${state.customers.length ? `<ul>${state.customers.map((customer, index) => `<li>${escapeHtml(customer.cliente_email || `Cuenta ${customer.account_id}`)} <button class="fidelity-button fidelity-button-quiet" type="button" data-customer="${index}" ${state.loading ? 'disabled' : ''}>Seleccionar</button></li>`).join('')}</ul>` : '<p>No hay clientes para mostrar.</p>'}
    <button class="fidelity-button fidelity-button-quiet" id="customers-prev" type="button" ${state.loading || state.customerOffset === 0 ? 'disabled' : ''}>Anterior</button>
    <button class="fidelity-button fidelity-button-quiet" id="customers-next" type="button" ${state.loading || state.customers.length < 20 ? 'disabled' : ''}>Siguiente</button>
  </section>`;
}

function renderCommerceQr() {
  if (!state.commerceQrUrl || !state.commerceQrImage) return '';
  return `
    <section class="fidelity-card fidelity-qr-card" aria-labelledby="commerce-qr-title">
      <img class="fidelity-qr-image" src="${state.commerceQrImage}" alt="Código QR estático de ${escapeHtml(state.access.tenantName)}" />
      <div>
        <p class="fidelity-step">QR del comercio</p>
        <h2 id="commerce-qr-title">Compartí este QR con tus clientes</h2>
        <p class="fidelity-muted">Identifica a ${escapeHtml(state.access.tenantName)}. Escanearlo abre el programa del comercio; por sí solo no acredita ni descuenta puntos.</p>
        <a class="fidelity-button fidelity-button-quiet" href="${state.commerceQrUrl}">Abrir enlace del QR</a>
      </div>
    </section>`;
}

function renderInitialState() {
  if (!state.searchedEmail) return '';
  return `
    <section class="fidelity-empty" role="status">
      <h2>Cliente no encontrado</h2>
      <p>No hay una cuenta activa con ese email en este comercio.</p>
    </section>`;
}

function renderAccount() {
  return `
    <section class="fidelity-account" aria-label="Cuenta seleccionada">
      <article class="fidelity-card fidelity-balance-card">
        <div>
          <p class="fidelity-step">Cuenta seleccionada</p>
          <h2>${escapeHtml(state.account.cliente_email || `Cuenta ${state.account.account_id}`)}</h2>
        </div>
        <div class="fidelity-balance"><strong>${formatPoints(state.account.saldo)}</strong><span>puntos disponibles</span></div>
      </article>
      <div class="fidelity-columns">
        <section class="fidelity-card" aria-labelledby="earn-title">
          <p class="fidelity-step">02</p>
          <h2 id="earn-title">Acreditar puntos</h2>
          <p class="fidelity-muted">La acreditación quedará pendiente hasta que el cliente la confirme.</p>
          <form id="earn-form" class="fidelity-stack-form">
            <label for="points">Puntos</label>
            <input id="points" name="points" type="number" inputmode="numeric" min="1" step="1" placeholder="Ej. 180" required />
            <button class="fidelity-button fidelity-button-primary" type="submit" ${state.loading ? 'disabled' : ''}>Crear acreditación</button>
          </form>
        </section>
        <section class="fidelity-card" aria-labelledby="pending-title">
          <div class="fidelity-section-heading">
            <div><p class="fidelity-step">03</p><h2 id="pending-title">Operaciones pendientes</h2></div>
            <button class="fidelity-button fidelity-button-quiet" id="refresh" type="button" ${state.loading ? 'disabled' : ''}>Actualizar</button>
          </div>
          ${renderOperations()}
        </section>
      </div>
    </section>`;
}

function renderOperations() {
  if (!state.operations.length) {
    return `<p class="fidelity-empty-inline" role="status">${panelStateText('empty')}</p>`;
  }
  return `<div class="fidelity-operation-list">${state.operations.map((operation, index) => {
    const view = operationPresentation(operation);
    const reward = Array.isArray(operation.reward) ? operation.reward[0] : operation.reward;
    const title = operation.tipo === 'earn' ? 'Acreditación' : (reward?.nombre || 'Canje de recompensa');
    return `
      <article class="fidelity-operation">
        <div class="fidelity-operation-copy">
          <span class="fidelity-badge fidelity-badge-${view.tone}">${escapeHtml(view.label)}</span>
          <h3>${escapeHtml(title)}</h3>
          <p>${operation.tipo === 'earn' ? '+' : '−'}${formatPoints(operation.puntos)} puntos · ${formatDate(operation.created_at)}</p>
        </div>
        ${view.actions.length ? `<div class="fidelity-operation-actions">
          ${view.actions.includes('confirm') ? `<button class="fidelity-button fidelity-button-primary" data-action="confirm" data-operation-index="${index}" type="button" ${state.loading ? 'disabled' : ''}>Confirmar</button>` : ''}
          ${view.actions.includes('cancel') ? `<button class="fidelity-button fidelity-button-danger" data-action="cancel" data-operation-index="${index}" type="button" ${state.loading ? 'disabled' : ''}>Cancelar</button>` : ''}
        </div>` : ''}
      </article>`;
  }).join('')}</div>`;
}

function renderNotice() {
  if (!state.notice) return '';
  return `<p class="fidelity-notice fidelity-notice-${state.notice.type}" role="status" aria-live="polite">${escapeHtml(state.notice.message)}</p>`;
}

function bindPanelEvents() {
  root.querySelector('#logout').addEventListener('click', logout);
  root.querySelector('#search-form').addEventListener('submit', handleSearch);
  root.querySelector('#customers-form').addEventListener('submit', (event) => {
    event.preventDefault();
    void loadCustomers(String(new FormData(event.currentTarget).get('filter')).trim(), 0);
  });
  root.querySelector('#customers-prev').addEventListener('click', () => void loadCustomers(state.customerSearch, Math.max(0, state.customerOffset - 20)));
  root.querySelector('#customers-next').addEventListener('click', () => void loadCustomers(state.customerSearch, state.customerOffset + 20));
  root.querySelectorAll('[data-customer]').forEach((button) => button.addEventListener('click', () => {
    const customer = state.customers[Number(button.dataset.customer)];
    if (customer) void selectCustomer(customer);
  }));
  root.querySelector('#earn-form')?.addEventListener('submit', handleEarn);
  root.querySelector('#refresh')?.addEventListener('click', refreshAccount);
  root.querySelectorAll('[data-action]').forEach((button) => {
    button.addEventListener('click', () => {
      const operation = state.operations[Number(button.dataset.operationIndex)];
      if (operation) void handleRedeem(button.dataset.action, operation.id);
    });
  });
}

async function loadCustomers(search, offset) {
  await lock.run(async () => {
    state.loading = true;
    state.customerError = null;
    renderPanel();
    try {
      const customers = await listCustomers(client, search, offset);
      state.customerSearch = search;
      state.customerOffset = offset;
      state.customers = customers;
    } catch (error) {
      state.customerError = error.message;
    } finally {
      state.loading = false;
      renderPanel();
    }
  });
}

async function selectCustomer(customer) {
  await lock.run(async () => {
    state.loading = true;
    state.notice = null;
    renderPanel();
    try {
      await synchronizeAccountById(customer.account_id);
      state.searchedEmail = customer.cliente_email || '';
    } catch (error) {
      state.account = null;
      state.operations = [];
      state.notice = { type: 'error', message: error.message };
    } finally {
      state.loading = false;
      renderPanel();
    }
  });
}

async function handleSearch(event) {
  event.preventDefault();
  const email = new FormData(event.currentTarget).get('email');
  await lock.run(async () => {
    state.searchedEmail = String(email).trim();
    state.loading = true;
    state.notice = null;
    renderPanel();
    try {
      await synchronizeOperator(state.searchedEmail);
    } catch (error) {
      state.account = null;
      state.operations = [];
      state.notice = { type: 'error', message: error.message };
    } finally {
      state.loading = false;
      renderPanel();
    }
  });
}

async function handleEarn(event) {
  event.preventDefault();
  const points = Number(new FormData(event.currentTarget).get('points'));
  if (!Number.isSafeInteger(points) || points <= 0) {
    state.notice = { type: 'error', message: 'Ingresá una cantidad válida de puntos.' };
    return renderPanel();
  }
  const signature = `${state.account.account_id}:${points}`;
  const attempt = earnAttempts.get(signature);
  await lock.run(async () => {
    state.loading = true;
    state.notice = null;
    renderPanel();
    try {
      const result = await runEarnCreation({
        create: () => createEarn(client, {
          accountId: state.account.account_id,
          points,
          idempotencyKey: attempt.key,
        }),
        refresh: refreshData,
      });
      state.notice = earnFlowNotice(result);
    } catch (error) {
      state.notice = { type: 'error', message: error.message };
    } finally {
      state.loading = false;
      renderPanel();
    }
  });
}

async function handleRedeem(action, operationId) {
  await lock.run(async () => {
    state.loading = true;
    state.notice = null;
    renderPanel();
    try {
      if (action === 'confirm') {
        await confirmRedeem(client, operationId);
        state.notice = { type: 'success', message: 'Canje confirmado correctamente.' };
      } else {
        await cancelRedeem(client, operationId);
        state.notice = { type: 'success', message: 'Canje cancelado correctamente.' };
      }
      await refreshData();
    } catch (error) {
      state.notice = { type: 'error', message: error.message };
    } finally {
      state.loading = false;
      renderPanel();
    }
  });
}

async function refreshAccount() {
  await lock.run(async () => {
    state.loading = true;
    state.notice = null;
    renderPanel();
    try {
      await refreshData();
    } catch (error) {
      state.notice = { type: 'error', message: error.message };
    } finally {
      state.loading = false;
      renderPanel();
    }
  });
}

async function refreshData() {
  await synchronizeAccountById(state.account.account_id);
}

async function synchronizeAccountById(accountId) {
  await runSuccessfulRefresh({
    refresh: async () => {
      const [account] = await listCustomers(client, '', 0, 1, accountId);
      if (!account) throw new Error('La cuenta ya no está disponible.');
      const operations = await listPendingOperations(client, account.account_id);
      state.account = account;
      state.operations = operations;
    },
    onSuccess: () => earnAttempts.clear(),
  });
}

async function synchronizeOperator(email, requireAccount = false) {
  await runSuccessfulRefresh({
    refresh: async () => {
      const account = await searchAccount(client, email);
      if (!account && requireAccount) throw new Error('La cuenta ya no está disponible.');
      state.account = account;
      state.operations = account
        ? await listPendingOperations(client, account.account_id)
        : [];
    },
    onSuccess: () => earnAttempts.clear(),
  });
}

async function logout() {
  try { await signOutFidelizacion(client); } finally { window.location.assign(loginUrl()); }
}

async function start() {
  addFavicon();
  renderLoading();
  try {
    client = getSupabaseClient();
    const user = await getSessionUser(client);
    if (!user) return window.location.assign(loginUrl());
    state.access = await resolveStaffAccess(client, user.id);
    state.commerceQrUrl = commerceQrUrl(state.access.tenantQrCode, window.location);
    state.commerceQrImage = await createCommerceQrImage(state.commerceQrUrl);
    renderPanel();
    await loadCustomers('', 0);
    if (checkInEnabled) {
      void refreshCheckIns();
      checkInTimer = window.setInterval(() => void refreshCheckIns(), 30000);
      document.addEventListener('visibilitychange', () => { if (!document.hidden) void refreshCheckIns(); });
      window.addEventListener('pagehide', () => window.clearInterval(checkInTimer), { once: true });
    }
  } catch (error) {
    if (error instanceof UnauthorizedStaffError) return renderUnauthorized();
    root.innerHTML = `<main class="fidelity-centered"><section class="fidelity-message-card"><h1>No pudimos cargar el panel</h1><p class="fidelity-muted">${escapeHtml(error.message)}</p><a class="fidelity-button fidelity-button-primary" href="${loginUrl()}">Volver al ingreso</a></section></main>`;
  }
}

function formatPoints(value) {
  return new Intl.NumberFormat('es-AR', { maximumFractionDigits: 0 }).format(Number(value));
}

function formatDate(value) {
  return new Intl.DateTimeFormat('es-AR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value));
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

void start();
