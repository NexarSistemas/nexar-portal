import { NEXAR_FAVICON_DATA_URI, NEXAR_LOGO_DATA_URI } from '../brand/assets.js';
import { getSupabaseClient } from '../supabase/client.js';
import {
  getSessionUser,
  resolveStaffAccess,
  signInFidelizacion,
  signOutFidelizacion,
} from './api.js';
import { UnauthorizedStaffError } from './contracts.js';
import './styles.css';

const root = document.querySelector('#app');
let client;

function operatorUrl() {
  return new URL('../operador/', window.location.href);
}

function addFavicon() {
  const favicon = document.createElement('link');
  favicon.rel = 'icon';
  favicon.type = 'image/png';
  favicon.href = NEXAR_FAVICON_DATA_URI;
  document.head.append(favicon);
}

function renderLoading() {
  root.innerHTML = '<main class="fidelity-loading" role="status">Validando sesión…</main>';
}

function renderLogin(message = '') {
  root.innerHTML = `
    <main class="fidelity-auth-layout">
      <section class="fidelity-auth-card" aria-labelledby="login-title">
        <img class="fidelity-logo" src="${NEXAR_LOGO_DATA_URI}" alt="Nexar Sistemas" />
        <p class="fidelity-eyebrow">Nexar Fidelización</p>
        <h1 id="login-title">Panel operador</h1>
        <p class="fidelity-muted">Ingresá con la cuenta habilitada por tu comercio.</p>
        <form id="fidelity-login-form">
          <label for="email">Email</label>
          <input id="email" name="email" type="email" autocomplete="username" required />
          <label for="password">Contraseña</label>
          <input id="password" name="password" type="password" autocomplete="current-password" required />
          <p class="fidelity-status" role="status" aria-live="polite" ${message ? '' : 'hidden'}>${escapeHtml(message)}</p>
          <button class="fidelity-button fidelity-button-primary" type="submit">Ingresar</button>
        </form>
      </section>
      <aside class="fidelity-auth-aside" aria-hidden="true">
        <span>Programa de puntos</span>
        <p>Una experiencia simple para acompañar a cada cliente.</p>
      </aside>
    </main>`;

  const form = root.querySelector('#fidelity-login-form');
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = form.querySelector('button');
    const status = form.querySelector('.fidelity-status');
    const values = new FormData(form);
    button.disabled = true;
    button.textContent = 'Ingresando…';
    status.hidden = true;
    try {
      const user = await signInFidelizacion(client, values.get('email'), values.get('password'));
      await resolveStaffAccess(client, user.id);
      window.location.assign(operatorUrl());
    } catch (error) {
      if (error instanceof UnauthorizedStaffError) await client.auth.signOut({ scope: 'local' });
      status.textContent = error.message;
      status.hidden = false;
      button.disabled = false;
      button.textContent = 'Ingresar';
    }
  });
}

function renderUnauthorized() {
  root.innerHTML = `
    <main class="fidelity-centered">
      <section class="fidelity-message-card">
        <p class="fidelity-eyebrow">Acceso no autorizado</p>
        <h1>No podés ingresar al panel</h1>
        <p class="fidelity-muted">Tu cuenta no tiene acceso habilitado a Nexar Fidelización.</p>
        <button class="fidelity-button fidelity-button-primary" id="logout" type="button">Cerrar sesión</button>
      </section>
    </main>`;
  root.querySelector('#logout').addEventListener('click', async () => {
    await signOutFidelizacion(client);
    renderLogin();
  });
}

async function start() {
  addFavicon();
  renderLoading();
  try {
    client = getSupabaseClient();
    const user = await getSessionUser(client);
    if (!user) return renderLogin();
    await resolveStaffAccess(client, user.id);
    window.location.assign(operatorUrl());
  } catch (error) {
    if (error instanceof UnauthorizedStaffError) return renderUnauthorized();
    renderLogin(error.message.includes('configuración')
      ? 'Configurá las variables públicas de Supabase para iniciar.'
      : error.message);
  }
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char]);
}

void start();
