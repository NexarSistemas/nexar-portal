function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
}

function date(value, withTime = false) {
  return value ? new Intl.DateTimeFormat('es-AR', withTime ? { dateStyle: 'medium', timeStyle: 'short' } : { dateStyle: 'medium' }).format(new Date(value)) : '—';
}

function money(value, currency) {
  return new Intl.NumberFormat('es-AR', { style: 'currency', currency: currency || 'ARS' }).format(value ?? 0);
}

function renderStatus(state, loading, empty, error, retryId) {
  if (state?.status === 'loading') return `<section class="dashboard-status" role="status" aria-live="polite"><p>${loading}</p></section>`;
  if (state?.status === 'error') return `<section class="dashboard-status dashboard-error" role="alert"><p>${error}</p><button class="button secondary" id="${retryId}" type="button">Reintentar</button></section>`;
  if (state?.status === 'empty') return `<section class="dashboard-status" aria-live="polite"><p>${empty}</p></section>`;
  return '';
}

export function renderVentas(ventas, detail) {
  const listing = ventas ?? { status: 'loading', items: [], filters: {} };
  const filters = listing.filters ?? {};
  const list = listing.status === 'ready' ? `<div class="sales-list" aria-label="Resultados de ventas">${listing.items.map((venta) => `
    <button class="sale-row" type="button" data-sale-id="${escapeHtml(venta.id)}"><strong>${date(venta.fecha_venta)}</strong><span>${escapeHtml(venta.estado)}</span><span>${money(venta.importe_total, venta.moneda)}</span></button>`).join('')}</div>` : renderStatus(listing, 'Cargando ventas…', 'No encontramos ventas con los filtros seleccionados.', 'No pudimos cargar las ventas.', 'retry-ventas');
  const detailContent = detail?.status === 'ready' ? renderVentaDetail(detail.data) : renderStatus(detail, 'Cargando detalle de la venta…', '', 'No pudimos cargar el detalle de la venta.', 'retry-venta-detail');

  return `<section class="sales-page">
    <div class="sales-header"><p class="eyebrow">Administración</p><h1>Ventas</h1><p class="muted">Consultá ventas e ítems desde sus relaciones canónicas.</p></div>
    <form class="sale-filters" id="sale-filters"><label>Estado<select name="estado"><option value="">Todos</option>${['pendiente', 'confirmada', 'cancelada'].map((estado) => `<option value="${estado}" ${filters.estado === estado ? 'selected' : ''}>${estado}</option>`).join('')}</select></label><label>Desde<input name="desde" type="date" value="${escapeHtml(filters.desde || '')}" /></label><label>Hasta<input name="hasta" type="date" value="${escapeHtml(filters.hasta || '')}" /></label><button class="button secondary" type="submit">Filtrar</button></form>
    <div class="sales-layout"><section class="sales-panel"><h2>Resultados</h2>${list}</section><section class="sales-detail" aria-live="polite">${detailContent || '<div class="dashboard-status"><p>Seleccioná una venta para ver su detalle.</p></div>'}</section></div>
  </section>`;
}

function renderVentaDetail({ venta, cliente, vendedor, items, pagos, licencias, comisiones }) {
  return `<div class="sale-detail-content"><div class="sale-detail-title"><div><p class="eyebrow">Venta</p><h2>${date(venta.fecha_venta, true)}</h2></div><button class="button quiet" id="close-venta-detail" type="button">Cerrar</button></div>
    <dl class="sale-data"><div><dt>Estado</dt><dd>${escapeHtml(venta.estado)}</dd></div><div><dt>Total</dt><dd>${money(venta.importe_total, venta.moneda)}</dd></div><div><dt>Cliente</dt><dd>${escapeHtml(cliente?.nombre_completo || 'No disponible')}</dd></div><div><dt>Vendedor</dt><dd>${escapeHtml(vendedor?.codigo_vendedor || 'Sin vendedor asociado')}</dd></div></dl>
    <section class="relationship-section"><h3>Ítems de la venta</h3>${items.length ? `<div class="sale-items">${items.map((item) => `<article><strong>${escapeHtml(item.producto_nombre)}</strong>${item.plan_nombre ? `<span>${escapeHtml(item.plan_nombre)}</span>` : ''}<span>${escapeHtml(item.descripcion)}</span><small>${escapeHtml(item.cantidad)} × ${money(item.precio_unitario, venta.moneda)} · ${money(item.importe_total, venta.moneda)}</small></article>`).join('')}</div>` : '<p class="muted">No hay ítems vinculados.</p>'}</section>
    <section class="relationship-section"><h3>Pagos</h3>${pagos.length ? `<ul class="payment-list">${pagos.map((pago) => `<li>${money(pago.monto, pago.moneda)} · ${escapeHtml(pago.decision_administrativa || pago.estado_proveedor || 'Sin decisión')}<small>${escapeHtml(pago.proveedor_origen || 'Sin proveedor')} · ${date(pago.created_at)}</small></li>`).join('')}</ul>` : '<p class="muted">No hay pagos vinculados.</p>'}</section>
    <section class="relationship-section"><h3>Licencias</h3>${licencias.length ? `<ul class="license-list">${licencias.map((licencia) => `<li><code>${escapeHtml(licencia.license_key)}</code><small>${escapeHtml(licencia.producto || 'Sin producto')} · ${escapeHtml(licencia.plan_vendido || licencia.plan || 'Sin plan')} · vence ${date(licencia.expira)}</small></li>`).join('')}</ul>` : '<p class="muted">No hay licencias vinculadas.</p>'}</section>
    <section class="relationship-section"><h3>Comisiones</h3>${comisiones.length ? `<ul class="commission-list">${comisiones.map((comision) => `<li>${escapeHtml(comision.tipo || 'Comisión')} · ${money(comision.monto, venta.moneda)} · ${escapeHtml(comision.estado || 'Sin estado')}<small>${escapeHtml(comision.producto || 'Sin producto')} · ${date(comision.paid_at || comision.created_at)}</small></li>`).join('')}</ul>` : '<p class="muted">No hay comisiones vinculadas.</p>'}</section>
  </div>`;
}
