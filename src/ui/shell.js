const roleNames = { admin: 'Administración', vendedor: 'Vendedor' };

export function renderLogin(root, { message = '', onSubmit }) {
  root.innerHTML = `
    <main class="login-layout">
      <section class="login-card" aria-labelledby="login-title">
        <a class="wordmark" href="/" aria-label="Nexar Sistemas, inicio">NEXAR<span>SISTEMAS</span></a>
        <p class="eyebrow">Portal seguro</p>
        <h1 id="login-title">Ingresar</h1>
        <p class="muted">Accedé con las credenciales de tu cuenta.</p>
        <form id="login-form">
          <label for="email">Email</label>
          <input id="email" name="email" type="email" autocomplete="username" required />
          <label for="password">Contraseña</label>
          <input id="password" name="password" type="password" autocomplete="current-password" required />
          <p id="form-status" class="status" role="status" aria-live="polite" ${message ? '' : 'hidden'}>${message}</p>
          <button class="button primary" type="submit">Ingresar</button>
        </form>
      </section>
      <aside class="login-aside" aria-hidden="true"><div class="orb"></div><p>Una plataforma para acompañar el crecimiento de tu negocio.</p></aside>
    </main>`;

  const form = root.querySelector('#login-form');
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    const button = form.querySelector('button');
    const status = form.querySelector('#form-status');
    button.disabled = true;
    button.textContent = 'Ingresando…';
    status.hidden = true;
    try {
      await onSubmit(new FormData(form).get('email').trim(), new FormData(form).get('password'));
    } catch (error) {
      status.textContent = error.message;
      status.hidden = false;
      status.dataset.type = 'error';
      button.disabled = false;
      button.textContent = 'Ingresar';
    }
  });
}

export function renderShell(root, profile, onLogout) {
  const admin = profile.rol === 'admin';
  const title = admin ? 'Nexar Portal — Administración' : 'Portal Vendedor';
  const sections = admin ? ['Vendedores', 'Clientes', 'Ventas', 'Licencias', 'Comisiones'] : ['Inicio'];
  root.innerHTML = `
    <div class="portal-layout">
      <aside class="sidebar">
        <a class="wordmark" href="#inicio">NEXAR<span>SISTEMAS</span></a>
        <p class="nav-label">ESPACIO DE TRABAJO</p>
        <nav aria-label="Navegación principal"><a class="nav-item active" href="#inicio">Inicio</a></nav>
        <div class="sidebar-bottom"><span class="role-pill">${roleNames[profile.rol]}</span></div>
      </aside>
      <main class="portal-main" id="inicio">
        <header class="topbar"><span class="topbar-role">${roleNames[profile.rol]}</span><div class="user-menu"><span>${escapeHtml(profile.nombre)}</span><button class="button quiet" id="logout" type="button">Cerrar sesión</button></div></header>
        <section class="welcome"><p class="eyebrow">${roleNames[profile.rol]}</p><h1>${title}</h1><p class="muted">Bienvenido/a, ${escapeHtml(profile.nombre)}.</p></section>
        <section class="module-grid" aria-label="Secciones del portal">
          ${sections.map((section, index) => `<article class="module-card"><span class="module-index">0${index + 1}</span><h2>${section}</h2><p>Disponible próximamente</p></article>`).join('')}
        </section>
      </main>
    </div>`;
  root.querySelector('#logout').addEventListener('click', async (event) => {
    const button = event.currentTarget;
    button.disabled = true;
    try { await onLogout(); } catch { button.disabled = false; }
  });
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}
