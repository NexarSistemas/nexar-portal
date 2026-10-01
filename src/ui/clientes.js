function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function date(value) {
  return value ? new Intl.DateTimeFormat('es-AR', { dateStyle: 'medium' }).format(new Date(value)) : '—';
}

function money(value, currency) {
  return new Intl.NumberFormat('es-AR', { style: 'currency', currency: currency || 'ARS' }).format(value ?? 0);
}

function clientDocument(cliente) {
  return cliente.numero_documento ? `${cliente.tipo_documento ? `${cliente.tipo_documento} ` : ''}${cliente.numero_documento}` : '—';
}

function renderStatus(state, loading, empty, error, retryId) {
  if (state?.status === 'loading') return `<section class="dashboard-status" role="status" aria-live="polite"><p>${loading}</p></section>`;
  if (state?.status === 'error') return `<section class="dashboard-status dashboard-error" role="alert"><p>${error}</p><button class="button secondary" id="${retryId}" type="button">Reintentar</button></section>`;
  if (state?.status === 'empty') return `<section class="dashboard-status" aria-live="polite"><p>${empty}</p></section>`;
  return '';
}

export function renderClientes(clientes, detail) {
  const listing = clientes ?? { status: 'loading', items: [] };
  const listStatus = renderStatus(listing, 'Cargando clientes…', 'No encontramos clientes para esta búsqueda.', 'No pudimos cargar los clientes.', 'retry-clientes');
  const list = listing.status === 'ready' ? `
    <div class="clients-list" aria-label="Resultados de clientes">
      ${listing.items.map((cliente) => `<button class="client-row" type="button" data-client-id="${escapeHtml(cliente.id)}"><strong>${escapeHtml(cliente.nombre_completo)}</strong><span>${escapeHtml(cliente.email || 'Sin email')}</span><span>${escapeHtml(clientDocument(cliente))}</span></button>`).join('')}
    </div>` : listStatus;
  const detailContent = detail?.status === 'ready' ? renderClientDetail(detail.data) : renderStatus(detail, 'Cargando detalle del cliente…', '', 'No pudimos cargar el detalle del cliente.', 'retry-client-detail');

  return `
    <section class="clients-page">
      <div class="clients-header"><div><p class="eyebrow">Administración</p><h1>Clientes</h1><p class="muted">Consultá información operativa de clientes y sus relaciones canónicas.</p></div></div>
      <form class="client-search" id="client-search"><label for="client-query">Buscar clientes</label><div><input id="client-query" name="query" type="search" value="${escapeHtml(listing.query || '')}" placeholder="Nombre, email o documento" /><button class="button secondary" type="submit">Buscar</button></div></form>
      <div class="clients-layout"><section class="clients-panel"><h2>Resultados</h2>${list}</section><section class="clients-detail" aria-live="polite">${detailContent || '<div class="dashboard-status"><p>Seleccioná un cliente para ver su detalle.</p></div>'}</section></div>
    </section>`;
}

function renderClientDetail({ cliente, ventas, pagos, licencias }) {
  const paymentsBySale = new Map(ventas.map(({ id }) => [id, []]));
  pagos.forEach((pago) => paymentsBySale.get(pago.venta_id)?.push(pago));
  return `<div class="client-detail-content"><div class="client-detail-title"><div><p class="eyebrow">Cliente</p><h2>${escapeHtml(cliente.nombre_completo)}</h2></div><button class="button quiet" id="close-client-detail" type="button">Cerrar</button></div>
    <dl class="client-data"><div><dt>Email</dt><dd>${escapeHtml(cliente.email || '—')}</dd></div><div><dt>Teléfono</dt><dd>${escapeHtml(cliente.telefono || '—')}</dd></div><div><dt>Documento</dt><dd>${escapeHtml(clientDocument(cliente))}</dd></div><div><dt>Alta</dt><dd>${date(cliente.created_at)}</dd></div></dl>
    <section class="relationship-section"><h3>Ventas</h3>${ventas.length ? ventas.map((venta) => `<article class="sale-card"><p><strong>${date(venta.fecha_venta)}</strong> · ${escapeHtml(venta.estado)}</p><p>${money(venta.importe_total, venta.moneda)}</p><h4>Pagos</h4>${renderPayments(paymentsBySale.get(venta.id))}</article>`).join('') : '<p class="muted">No hay ventas vinculadas.</p>'}</section>
    <section class="relationship-section"><h3>Licencias</h3>${licencias.length ? `<ul class="license-list">${licencias.map((licencia) => `<li><code>${escapeHtml(licencia.license_key)}</code></li>`).join('')}</ul>` : '<p class="muted">No hay licencias vinculadas.</p>'}</section>
  </div>`;
}

function renderPayments(pagos = []) {
  if (!pagos.length) return '<p class="muted">No hay pagos asociados.</p>';
  return `<ul class="payment-list">${pagos.map((pago) => `<li>${money(pago.monto, pago.moneda)} · ${escapeHtml(pago.decision_administrativa || pago.estado_proveedor || 'Sin decisión')}<small>${escapeHtml(pago.proveedor_origen || 'Sin proveedor')} · ${date(pago.created_at)}</small></li>`).join('')}</ul>`;
}
