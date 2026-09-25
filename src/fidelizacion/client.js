import { NEXAR_FAVICON_DATA_URI, NEXAR_LOGO_DATA_URI } from '../brand/assets.js';
import { getSupabaseClient } from '../supabase/client.js';
import { getSessionUser, signOutFidelizacion } from './api.js';
import {
  confirmClientEarn,
  createClientRedeem,
  getClientBalance,
  getPendingEarns,
  loadClientAccess,
  listClientMovements,
  listClientOperations,
  listClientRewards,
  scanClientRedeem,
} from './client-api.js';
import {
  activeQrCode,
  availableRedeemPoints,
  clientOperationText,
  createAttemptStore,
  pendingRedeems,
  qrCodeFromLocation,
  reconcileQrState,
  urlWithoutQr,
} from './client-contracts.js';
import { createActionLock } from './contracts.js';
import './styles.css';

const root = document.querySelector('#app');
const lock = createActionLock();
const redeemAttempts = createAttemptStore(() => crypto.randomUUID());
const state = {
  user: null,
  accounts: [],
  account: null,
  rewards: [],
  movements: [],
  operations: [],
  pendingEarns: [],
  balance: 0,
  qrContext: null,
  loading: false,
  notice: null,
};
let client;

function addFavicon() {
  const favicon = document.createElement('link');
  favicon.rel = 'icon';
  favicon.type = 'image/png';
  favicon.href = NEXAR_FAVICON_DATA_URI;
  document.head.append(favicon);
}

function loginUrl() {
  const url = new URL('./login/', window.location.href);
  if (state.qrContext?.qrCode) url.searchParams.set('qr', state.qrContext.qrCode);
  return url;
}

function renderLoading(text = 'Cargando tu programa de puntos…') {
  root.innerHTML = `<main class="fidelity-loading" role="status">${escapeHtml(text)}</main>`;
}

function render() {
  if (!state.account) return renderNoPrograms();
  const balance = state.balance;
  const availableBalance = availableRedeemPoints(balance, state.operations);
  root.innerHTML = `
    <div class="fidelity-app fidelity-client-app">
      <header class="fidelity-header">
        <div class="fidelity-brand">
          <img src="${NEXAR_LOGO_DATA_URI}" alt="Nexar Sistemas" />
          <span>${escapeHtml(state.account.tenantName)}</span>
        </div>
        <div class="fidelity-session">
          ${state.accounts.length > 1 ? '<button class="fidelity-button fidelity-button-quiet" id="change-program" type="button">Cambiar comercio</button>' : ''}
          <button class="fidelity-button fidelity-button-quiet" id="logout" type="button">Cerrar sesión</button>
        </div>
      </header>
      <main class="fidelity-main fidelity-client-main">
        <section class="fidelity-client-hero">
          <div>
            <p class="fidelity-eyebrow">Tu saldo</p>
            <h1>${formatPoints(balance)} <span>puntos</span></h1>
            <p>Saldo confirmado según tus movimientos.</p>
            <p><strong>Disponible para canjes: ${formatPoints(availableBalance)} puntos.</strong></p>
          </div>
          <button class="fidelity-button fidelity-button-light" id="refresh" type="button" ${state.loading ? 'disabled' : ''}>${state.loading ? 'Actualizando…' : 'Actualizar'}</button>
        </section>
        ${renderNotice()}
        ${renderQrPanel()}
        <div class="fidelity-client-grid">
          <section class="fidelity-card fidelity-client-rewards" aria-labelledby="rewards-title">
            <div class="fidelity-section-heading">
              <div><p class="fidelity-step">Beneficios</p><h2 id="rewards-title">Recompensas</h2></div>
            </div>
            ${renderRewards(availableBalance)}
          </section>
          <section class="fidelity-card" aria-labelledby="activity-title">
            <div class="fidelity-section-heading">
              <div><p class="fidelity-step">Actividad</p><h2 id="activity-title">Movimientos</h2></div>
            </div>
            ${renderMovements()}
          </section>
        </div>
        ${renderPendingRedeems()}
        <section class="fidelity-qr-help">
          <div>
            <p class="fidelity-step">En el comercio</p>
            <h2>Usá el QR para continuar</h2>
            <p>Escaneá con la cámara de tu celular el QR estático del comercio. Abrirlo no suma ni descuenta puntos por sí solo.</p>
          </div>
        </section>
      </main>
    </div>`;
  bindEvents();
}

function renderNoPrograms() {
  root.innerHTML = `
    <main class="fidelity-centered">
      <section class="fidelity-message-card">
        <p class="fidelity-eyebrow">Nexar Fidelización</p>
        <h1>Todavía no tenés un programa asociado</h1>
        <p class="fidelity-muted">Escaneá el QR de un comercio participante para vincular tu cuenta.</p>
        ${renderNotice()}
        <button class="fidelity-button fidelity-button-quiet" id="logout" type="button">Cerrar sesión</button>
      </section>
    </main>`;
  root.querySelector('#logout').addEventListener('click', logout);
}

function renderProgramPicker() {
  root.innerHTML = `
    <main class="fidelity-centered">
      <section class="fidelity-message-card fidelity-program-picker">
        <p class="fidelity-eyebrow">Tus programas</p>
        <h1>Elegí un comercio</h1>
        <div class="fidelity-program-list">
          ${state.accounts.map((account, index) => `<button class="fidelity-button fidelity-button-quiet" data-program-index="${index}" type="button">${escapeHtml(account.tenantName)}</button>`).join('')}
        </div>
      </section>
    </main>`;
  root.querySelectorAll('[data-program-index]').forEach((button) => {
    button.addEventListener('click', async () => {
      state.account = state.accounts[Number(button.dataset.programIndex)];
      const qrState = reconcileQrState(state.qrContext, state.account, state.pendingEarns);
      if (state.qrContext && !qrState.qrContext) discardQrContext();
      state.qrContext = qrState.qrContext;
      state.rewards = [];
      state.movements = [];
      state.operations = [];
      state.pendingEarns = qrState.pendingEarns;
      state.balance = 0;
      await runAction(refreshSnapshot);
    });
  });
}

function renderNotice() {
  if (!state.notice) return '';
  return `<p class="fidelity-notice fidelity-notice-${state.notice.type}" role="status" aria-live="polite">${escapeHtml(state.notice.message)}</p>`;
}

function renderQrPanel() {
  if (!activeQrCode(state.qrContext, state.account)) return '';
  const redeemToScan = pendingRedeems(state.operations).filter((operation) => operation.estado === 'pending_customer');
  return `
    <section class="fidelity-card fidelity-qr-panel" aria-labelledby="qr-actions-title">
      <div class="fidelity-section-heading">
        <div><p class="fidelity-step">QR del comercio</p><h2 id="qr-actions-title">Acciones pendientes</h2></div>
      </div>
      ${state.pendingEarns.length === 0 ? '<p class="fidelity-empty-inline">No hay puntos pendientes para acreditar.</p>' : `
        <div class="fidelity-operation-list">
          ${state.pendingEarns.map((operation) => `
            <article class="fidelity-operation">
              <div><span class="fidelity-badge fidelity-badge-info">Acreditación</span><h3>+${formatPoints(operation.puntos)} puntos</h3><p>Confirmá para sumarlos a tu saldo.</p></div>
              <button class="fidelity-button fidelity-button-primary" data-confirm-earn="${operation.operation_id}" type="button" ${state.loading ? 'disabled' : ''}>Confirmar</button>
            </article>`).join('')}
        </div>`}
      ${redeemToScan.length === 0 ? '' : `
        <div class="fidelity-operation-list">
          ${redeemToScan.map((operation) => `
            <article class="fidelity-operation">
              <div><span class="fidelity-badge fidelity-badge-warning">Canje</span><h3>${escapeHtml(rewardName(operation))}</h3><p>Continuá el canje para que el comercio pueda confirmarlo.</p></div>
              <button class="fidelity-button fidelity-button-primary" data-scan-redeem="${operation.id}" type="button" ${state.loading ? 'disabled' : ''}>Continuar canje</button>
            </article>`).join('')}
        </div>`}
    </section>`;
}

function renderRewards(balance) {
  if (state.rewards.length === 0) return '<p class="fidelity-empty-inline">Este comercio todavía no publicó recompensas.</p>';
  return `<div class="fidelity-reward-list">${state.rewards.map((reward) => {
    const enough = balance >= Number(reward.puntos_requeridos);
    return `
      <article class="fidelity-reward">
        <div><h3>${escapeHtml(reward.nombre)}</h3><p>${escapeHtml(reward.descripcion || 'Beneficio del programa')}</p></div>
        <div class="fidelity-reward-action">
          <strong>${formatPoints(reward.puntos_requeridos)} pts</strong>
          <button class="fidelity-button ${enough ? 'fidelity-button-primary' : 'fidelity-button-quiet'}" data-create-redeem="${reward.id}" type="button" ${state.loading || !enough ? 'disabled' : ''}>${enough ? 'Canjear' : 'Saldo insuficiente'}</button>
        </div>
      </article>`;
  }).join('')}</div>`;
}

function renderMovements() {
  if (state.movements.length === 0) return '<p class="fidelity-empty-inline">Todavía no tenés movimientos confirmados.</p>';
  return `<div class="fidelity-movement-list">${state.movements.map((movement) => {
    const points = Number(movement.puntos);
    const reward = movement.operation?.reward;
    const rewardValue = Array.isArray(reward) ? reward[0] : reward;
    const label = rewardValue?.nombre || movement.descripcion || (points > 0 ? 'Acreditación' : 'Canje');
    return `
      <article class="fidelity-movement">
        <div><strong>${escapeHtml(label)}</strong><time datetime="${escapeHtml(movement.fecha)}">${formatDate(movement.fecha)}</time></div>
        <span class="${points >= 0 ? 'is-positive' : 'is-negative'}">${points >= 0 ? '+' : ''}${formatPoints(points)}</span>
      </article>`;
  }).join('')}</div>`;
}

function renderPendingRedeems() {
  const operations = pendingRedeems(state.operations);
  if (operations.length === 0) return '';
  return `
    <section class="fidelity-card fidelity-client-pending" aria-labelledby="pending-title">
      <div><p class="fidelity-step">Canjes en curso</p><h2 id="pending-title">Estado de tus canjes</h2></div>
      <div class="fidelity-operation-list">
        ${operations.map((operation) => `
          <article class="fidelity-operation">
            <div><span class="fidelity-badge fidelity-badge-${operation.estado === 'pending_staff' ? 'warning' : 'info'}">${operation.estado === 'pending_staff' ? 'Esperando al comercio' : 'Esperando QR'}</span><h3>${escapeHtml(rewardName(operation))}</h3><p>${escapeHtml(clientOperationText(operation))}</p></div>
            <strong>${formatPoints(operation.puntos)} pts</strong>
          </article>`).join('')}
      </div>
    </section>`;
}

function bindEvents() {
  root.querySelector('#logout').addEventListener('click', logout);
  root.querySelector('#refresh').addEventListener('click', refresh);
  root.querySelector('#change-program')?.addEventListener('click', renderProgramPicker);
  root.querySelectorAll('[data-confirm-earn]').forEach((button) => {
    button.addEventListener('click', () => confirmEarn(button.dataset.confirmEarn));
  });
  root.querySelectorAll('[data-create-redeem]').forEach((button) => {
    button.addEventListener('click', () => createRedeem(button.dataset.createRedeem));
  });
  root.querySelectorAll('[data-scan-redeem]').forEach((button) => {
    button.addEventListener('click', () => scanRedeem(button.dataset.scanRedeem));
  });
}

async function refreshSnapshot() {
  const [rewards, movements, operations, balance] = await Promise.all([
    listClientRewards(client, state.account.tenantId),
    listClientMovements(client, state.account.id),
    listClientOperations(client, state.account.id),
    getClientBalance(client, state.account.id),
  ]);
  state.rewards = rewards;
  state.movements = movements;
  state.operations = operations;
  state.balance = balance;
  const qrCode = activeQrCode(state.qrContext, state.account);
  state.pendingEarns = qrCode ? await getPendingEarns(client, qrCode) : [];
}

async function refresh() {
  await runAction(async () => {
    await refreshSnapshot();
    state.notice = { type: 'success', message: 'Información actualizada.' };
  });
}

async function confirmEarn(operationId) {
  await runAction(async () => {
    await confirmClientEarn(client, {
      qrCode: activeQrCode(state.qrContext, state.account), operationId,
    });
    await refreshSnapshot();
    state.notice = { type: 'success', message: 'Puntos acreditados. Tu saldo ya está actualizado.' };
  });
}

async function createRedeem(rewardId) {
  const signature = `${state.account.id}:${rewardId}`;
  await runAction(async () => {
    const idempotencyKey = redeemAttempts.get(signature);
    let created = false;
    try {
      await createClientRedeem(client, { rewardId, idempotencyKey });
      created = true;
      await refreshSnapshot();
      redeemAttempts.clear(signature);
      state.notice = { type: 'success', message: 'Canje iniciado. Escaneá el QR del comercio para continuar.' };
    } catch (error) {
      if (created) {
        state.notice = { type: 'success', message: 'El canje fue iniciado, pero no pudimos actualizar la vista. Actualizá antes de volver a intentarlo.' };
        return;
      }
      throw error;
    }
  });
}

async function scanRedeem(operationId) {
  await runAction(async () => {
    await scanClientRedeem(client, {
      qrCode: activeQrCode(state.qrContext, state.account), operationId,
    });
    await refreshSnapshot();
    state.notice = { type: 'success', message: 'Canje enviado. Ahora el comercio debe confirmarlo.' };
  });
}

async function runAction(action) {
  await lock.run(async () => {
    state.loading = true;
    state.notice = null;
    render();
    try {
      await action();
    } catch (error) {
      state.notice = { type: 'error', message: error.message };
    } finally {
      state.loading = false;
      render();
    }
  });
}

async function logout() {
  try { await signOutFidelizacion(client); } finally { window.location.assign(loginUrl()); }
}

function discardQrContext() {
  state.qrContext = null;
  state.pendingEarns = [];
  sessionStorage.removeItem('nexar-fidelizacion-qr');
  window.history.replaceState(null, '', urlWithoutQr(window.location.href));
}

async function start() {
  addFavicon();
  renderLoading();
  const qrCode = qrCodeFromLocation(window.location);
  state.qrContext = qrCode ? { qrCode, tenantId: null } : null;
  try {
    client = getSupabaseClient();
    state.user = await getSessionUser(client);
    if (!state.user) return window.location.assign(loginUrl());

    const access = await loadClientAccess(client, { userId: state.user.id, qrCode });
    state.accounts = access.accounts;
    state.qrContext = access.qrContext;
    if (state.qrContext) {
      sessionStorage.removeItem('nexar-fidelizacion-qr');
    } else if (access.associationError) {
      discardQrContext();
      state.notice = { type: 'error', message: access.associationError.message };
    }
    state.account = state.accounts.find((account) => account.tenantId === state.qrContext?.tenantId)
      ?? state.accounts[0]
      ?? null;
    if (!state.account) return render();
    await refreshSnapshot();
    render();
  } catch (error) {
    state.notice = { type: 'error', message: error.message };
    if (state.account) return render();
    root.innerHTML = `<main class="fidelity-centered"><section class="fidelity-message-card"><h1>No pudimos cargar tu programa</h1><p class="fidelity-muted">${escapeHtml(error.message)}</p><a class="fidelity-button fidelity-button-primary" href="${loginUrl()}">Volver al ingreso</a></section></main>`;
  }
}

function rewardName(operation) {
  const reward = Array.isArray(operation.reward) ? operation.reward[0] : operation.reward;
  return reward?.nombre || 'Recompensa seleccionada';
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
