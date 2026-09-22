import { NEXAR_FAVICON_DATA_URI, NEXAR_LOGO_DATA_URI } from '../brand/assets.js';
import { getSupabaseClient } from '../supabase/client.js';
import {
  cancelRedeem,
  confirmRedeem,
  createEarn,
  getSessionUser,
  listPendingOperations,
  resolveStaffAccess,
  searchAccount,
  signOutFidelizacion,
} from './api.js';
import {
  createActionLock,
  operationPresentation,
  panelStateText,
  UnauthorizedStaffError,
} from './contracts.js';
import './styles.css';

const root = document.querySelector('#app');
let client;
const lock = createActionLock();
let earnAttempt = null;
const state = {
  access: null,
  account: null,
  operations: [],
  searchedEmail: '',
  loading: false,
  notice: null,
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
        ${renderNotice()}
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
          <h2>${escapeHtml(state.account.cliente_email)}</h2>
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
  root.querySelector('#earn-form')?.addEventListener('submit', handleEarn);
  root.querySelector('#refresh')?.addEventListener('click', refreshAccount);
  root.querySelectorAll('[data-action]').forEach((button) => {
    button.addEventListener('click', () => {
      const operation = state.operations[Number(button.dataset.operationIndex)];
      if (operation) void handleRedeem(button.dataset.action, operation.id);
    });
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
      state.account = await searchAccount(client, state.searchedEmail);
      state.operations = state.account
        ? await listPendingOperations(client, state.account.account_id)
        : [];
      earnAttempt = null;
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
  if (!earnAttempt || earnAttempt.signature !== signature) {
    earnAttempt = { signature, key: crypto.randomUUID() };
  }
  await lock.run(async () => {
    state.loading = true;
    state.notice = null;
    renderPanel();
    try {
      await createEarn(client, {
        accountId: state.account.account_id,
        points,
        idempotencyKey: earnAttempt.key,
      });
      earnAttempt = null;
      state.notice = { type: 'success', message: 'Acreditación creada. Está pendiente de confirmación del cliente.' };
      await refreshData();
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
  const account = await searchAccount(client, state.account.cliente_email);
  if (!account) throw new Error('La cuenta ya no está disponible.');
  state.account = account;
  state.operations = await listPendingOperations(client, account.account_id);
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
    renderPanel();
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
