import { NEXAR_FAVICON_DATA_URI, NEXAR_LOGO_DATA_URI } from '../brand/assets.js';
import { getSupabaseClient } from '../supabase/client.js';
import {
  getSessionUser,
  signInFidelizacion,
  signUpFidelizacion,
} from './api.js';
import { createActionLock } from './contracts.js';
import { qrCodeFromLocation } from './client-contracts.js';
import './styles.css';

const root = document.querySelector('#app');
const lock = createActionLock();
const QR_STORAGE_KEY = 'nexar-fidelizacion-qr';
let client;
let mode = 'login';
let message = '';
let messageType = 'error';

function addFavicon() {
  const favicon = document.createElement('link');
  favicon.rel = 'icon';
  favicon.type = 'image/png';
  favicon.href = NEXAR_FAVICON_DATA_URI;
  document.head.append(favicon);
}

function currentQrCode() {
  const fromUrl = qrCodeFromLocation(window.location);
  if (fromUrl) sessionStorage.setItem(QR_STORAGE_KEY, fromUrl);
  return fromUrl ?? sessionStorage.getItem(QR_STORAGE_KEY);
}

function clientUrl(qrCode) {
  const url = new URL('../', window.location.href);
  if (qrCode) url.searchParams.set('qr', qrCode);
  return url;
}

function confirmationUrl(qrCode) {
  const url = new URL(window.location.href);
  url.search = '';
  if (qrCode) url.searchParams.set('qr', qrCode);
  return url.href;
}

function render() {
  const qrCode = currentQrCode();
  const isRegister = mode === 'register';
  root.innerHTML = `
    <main class="fidelity-auth-layout">
      <section class="fidelity-auth-card" aria-labelledby="client-login-title">
        <img class="fidelity-logo" src="${NEXAR_LOGO_DATA_URI}" alt="Nexar Sistemas" />
        <p class="fidelity-eyebrow">Nexar Fidelización</p>
        <h1 id="client-login-title">${isRegister ? 'Creá tu cuenta' : 'Tu programa de puntos'}</h1>
        <p class="fidelity-muted">${isRegister
    ? 'Registrate para asociarte de forma segura al comercio.'
    : 'Ingresá para consultar tu saldo, beneficios y movimientos.'}</p>
        <div class="fidelity-auth-switch" role="group" aria-label="Elegir acceso">
          <button type="button" data-mode="login" class="${isRegister ? '' : 'is-active'}">Ingresar</button>
          <button type="button" data-mode="register" class="${isRegister ? 'is-active' : ''}" ${qrCode ? '' : 'disabled'}>Crear cuenta</button>
        </div>
        ${!qrCode && isRegister ? '<p class="fidelity-notice fidelity-notice-error">Escaneá el QR del comercio para crear tu cuenta.</p>' : ''}
        <form id="client-auth-form">
          <label for="email">Email</label>
          <input id="email" name="email" type="email" autocomplete="username" required />
          <label for="password">Contraseña</label>
          <input id="password" name="password" type="password" autocomplete="${isRegister ? 'new-password' : 'current-password'}" minlength="6" required />
          <p class="fidelity-status ${messageType === 'success' ? 'fidelity-status-success' : ''}" role="status" aria-live="polite" ${message ? '' : 'hidden'}>${escapeHtml(message)}</p>
          <button class="fidelity-button fidelity-button-primary" type="submit" ${isRegister && !qrCode ? 'disabled' : ''}>${isRegister ? 'Crear cuenta' : 'Ingresar'}</button>
        </form>
      </section>
      <aside class="fidelity-auth-aside" aria-hidden="true">
        <span>Experiencia cliente</span>
        <p>Tus puntos y recompensas, simples y siempre a mano.</p>
      </aside>
    </main>`;

  root.querySelectorAll('[data-mode]').forEach((button) => {
    button.addEventListener('click', () => {
      mode = button.dataset.mode;
      message = '';
      render();
    });
  });
  root.querySelector('#client-auth-form').addEventListener('submit', handleSubmit);
}

async function handleSubmit(event) {
  event.preventDefault();
  await lock.run(async () => {
    const form = event.currentTarget;
    const button = form.querySelector('button[type="submit"]');
    const values = new FormData(form);
    const qrCode = currentQrCode();
    button.disabled = true;
    button.textContent = mode === 'register' ? 'Creando…' : 'Ingresando…';
    message = '';
    try {
      if (mode === 'register') {
        const result = await signUpFidelizacion(
          client,
          values.get('email'),
          values.get('password'),
          confirmationUrl(qrCode),
        );
        if (result.confirmationRequired) {
          messageType = 'success';
          message = 'Revisá tu email para confirmar la cuenta. Después volvé a ingresar desde el QR del comercio.';
          return render();
        }
      } else {
        await signInFidelizacion(client, values.get('email'), values.get('password'));
      }
      window.location.assign(clientUrl(qrCode));
    } catch (error) {
      messageType = 'error';
      message = error.message;
      render();
    }
  });
}

async function start() {
  addFavicon();
  try {
    client = getSupabaseClient();
    const user = await getSessionUser(client);
    const qrCode = currentQrCode();
    if (user) {
      return window.location.assign(clientUrl(qrCode));
    }
    render();
  } catch (error) {
    messageType = 'error';
    message = error.message.includes('configuración')
      ? 'Configurá las variables públicas de Supabase para iniciar.'
      : error.message;
    render();
  }
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

void start();
