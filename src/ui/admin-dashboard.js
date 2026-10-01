export function renderAdminDashboard(dashboard) {
  if (dashboard.status === 'loading') {
    return '<section class="dashboard-status" role="status" aria-live="polite"><p>Cargando resumen operativo…</p></section>';
  }

  if (dashboard.status === 'error') {
    return `
      <section class="dashboard-status dashboard-error" role="alert">
        <p>No pudimos cargar el resumen operativo.</p>
        <button class="button secondary" id="retry-dashboard" type="button">Reintentar</button>
      </section>`;
  }

  if (dashboard.status === 'empty') {
    return '<section class="dashboard-status" aria-live="polite"><p>Aún no hay datos disponibles para el resumen operativo.</p></section>';
  }

  return `
    <section class="dashboard-grid" aria-label="Resumen operativo">
      ${dashboard.metrics.map((metric) => `
        <article class="metric-card">
          <p class="metric-label">${metric.label}</p>
          <p class="metric-value">${metric.value}</p>
        </article>`).join('')}
    </section>`;
}
