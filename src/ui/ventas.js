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
  const detailContent = listing.form ? renderVentaForm(listing.form) : detail?.status === 'ready' ? renderVentaDetail(detail.data) : renderStatus(detail, 'Cargando detalle de la venta…', '', 'No pudimos cargar el detalle de la venta.', 'retry-venta-detail');

  return `<section class="sales-page">
    <div class="sales-header"><div><p class="eyebrow">Administración</p><h1>Ventas</h1><p class="muted">Consultá ventas e ítems desde sus relaciones canónicas.</p></div><button class="button primary" id="new-sale" type="button">Nueva venta</button></div>
    ${listing.notice ? `<p class="client-notice" role="status" aria-live="polite">${escapeHtml(listing.notice)}</p>` : ''}
    <form class="sale-filters" id="sale-filters"><label>Estado<select name="estado"><option value="">Todos</option>${['pendiente', 'confirmada', 'cancelada'].map((estado) => `<option value="${estado}" ${filters.estado === estado ? 'selected' : ''}>${estado}</option>`).join('')}</select></label><label>Desde<input name="desde" type="date" value="${escapeHtml(filters.desde || '')}" /></label><label>Hasta<input name="hasta" type="date" value="${escapeHtml(filters.hasta || '')}" /></label><button class="button secondary" type="submit">Filtrar</button></form>
    <div class="sales-layout"><section class="sales-panel"><h2>Resultados</h2>${list}</section><section class="sales-detail" aria-live="polite">${detailContent || '<div class="dashboard-status"><p>Seleccioná una venta para ver su detalle.</p></div>'}</section></div>
  </section>`;
}

function localDateTime(value) {
  const dateValue = value ? new Date(value) : new Date();
  const offset = dateValue.getTimezoneOffset() * 60000;
  return new Date(dateValue.getTime() - offset).toISOString().slice(0, 16);
}

function itemPrice(form, item) {
  if (!item.plan_id) return null;
  const at = new Date(form.values.fecha_venta).getTime();
  return (form.catalogo?.precios ?? []).find((price) => price.plan_id === item.plan_id
    && price.moneda === form.values.moneda
    && new Date(price.vigente_desde).getTime() <= at
    && (!price.vigente_hasta || new Date(price.vigente_hasta).getTime() > at));
}

function renderVentaForm(form) {
  const values = form.values ?? {};
  const catalogo = form.catalogo ?? {};
  const saving = form.status !== 'ready';
  const items = values.items?.length ? values.items : [{}];
  const clients = form.selectedClient && !(form.clientes ?? []).some((client) => client.id === form.selectedClient.id)
    ? [form.selectedClient, ...(form.clientes ?? [])]
    : form.clientes ?? [];
  return `<div class="sale-detail-content"><div class="sale-detail-title"><div><p class="eyebrow">Ventas</p><h2>Nueva venta</h2></div><button class="button quiet" id="cancel-sale-form" type="button" ${saving ? 'disabled' : ''}>Cancelar</button></div>
    <form id="sale-form" class="sale-form">
      <div class="sale-client-search"><label for="sale-client-query">Buscar cliente</label><div><input id="sale-client-query" type="search" value="${escapeHtml(form.clientQuery || '')}" placeholder="Nombre, email o documento" ${saving ? 'disabled' : ''} /><button class="button secondary" id="search-sale-clients" type="button" ${saving ? 'disabled' : ''}>Buscar</button></div>${form.clientSearchStatus === 'loading' ? '<p class="muted">Buscando clientes…</p>' : form.clientSearchStatus === 'empty' ? '<p class="muted">No encontramos clientes para esta búsqueda.</p>' : form.clientSearchError ? `<p class="client-form-error" role="alert">${escapeHtml(form.clientSearchError)}</p>` : ''}</div>
      <label for="sale-client">Cliente<select id="sale-client" name="cliente_id" required ${saving ? 'disabled' : ''}><option value="">Seleccioná un cliente</option>${clients.map((client) => `<option value="${escapeHtml(client.id)}" ${values.cliente_id === client.id ? 'selected' : ''}>${escapeHtml(client.nombre_completo)}${client.numero_documento ? ` · ${escapeHtml(client.numero_documento)}` : ''}</option>`).join('')}</select></label>
      <button class="button secondary sale-client-link" id="create-client-from-sale" type="button" ${saving ? 'disabled' : ''}>Crear cliente</button>
      <label for="sale-seller">Vendedor (opcional)<select id="sale-seller" name="vendedor_id" ${saving ? 'disabled' : ''}><option value="">Sin vendedor asociado</option>${(catalogo.vendedores ?? []).map((seller) => `<option value="${escapeHtml(seller.id)}" ${values.vendedor_id === seller.id ? 'selected' : ''}>${escapeHtml(seller.codigo_vendedor)}</option>`).join('')}</select></label>
      <div class="sale-form-row"><label for="sale-date">Fecha<input id="sale-date" name="fecha_venta" type="datetime-local" value="${escapeHtml(localDateTime(values.fecha_venta))}" required ${saving ? 'disabled' : ''} /></label><label for="sale-currency">Moneda<input id="sale-currency" name="moneda" value="${escapeHtml(values.moneda || 'ARS')}" maxlength="3" required ${saving ? 'disabled' : ''} /></label></div>
      <section class="sale-form-items"><div><h3>Ítems</h3><button class="button secondary" id="add-sale-item" type="button" ${saving ? 'disabled' : ''}>Agregar ítem</button></div>${items.map((item, index) => renderSaleItem(form, item, index, saving)).join('')}</section>
      ${form.error ? `<p class="client-form-error" role="alert">${escapeHtml(form.error)}</p>` : ''}
      <button class="button primary" type="submit" ${saving ? 'disabled' : ''}>${form.status === 'saving' ? 'Guardando…' : form.status === 'loading' ? 'Cargando…' : 'Crear venta'}</button>
    </form>
  </div>`;
}

function renderSaleItem(form, item, index, saving) {
  const plans = (form.catalogo?.planes ?? []).filter((plan) => plan.producto_id === item.producto_id);
  const products = (form.catalogo?.productos ?? []).filter((product) => (form.catalogo?.planes ?? []).some((plan) => plan.producto_id === product.id));
  const price = itemPrice(form, item);
  return `<article class="sale-form-item" data-sale-item="${index}"><div class="sale-form-item-heading"><strong>Ítem ${index + 1}</strong>${index ? `<button class="button quiet remove-sale-item" type="button" data-remove-sale-item="${index}" ${saving ? 'disabled' : ''}>Quitar</button>` : ''}</div><label>Producto<select data-sale-item-field="producto_id" data-sale-item="${index}" required ${saving ? 'disabled' : ''}><option value="">Seleccioná un producto</option>${products.map((product) => `<option value="${escapeHtml(product.id)}" ${item.producto_id === product.id ? 'selected' : ''}>${escapeHtml(product.nombre)}</option>`).join('')}</select></label><label>Plan<select data-sale-item-field="plan_id" data-sale-item="${index}" required ${saving ? 'disabled' : ''}><option value="">Seleccioná un plan</option>${plans.map((plan) => `<option value="${escapeHtml(plan.id)}" ${item.plan_id === plan.id ? 'selected' : ''}>${escapeHtml(plan.nombre)}</option>`).join('')}</select></label><label>Cantidad<input data-sale-item-field="cantidad" data-sale-item="${index}" type="number" min="0.001" step="0.001" value="${escapeHtml(item.cantidad || 1)}" required ${saving ? 'disabled' : ''} /></label><p class="sale-price">${price ? `Precio vigente: <strong>${money(price.importe, price.moneda)}</strong>` : item.plan_id ? 'No hay un precio vigente para ese plan y moneda.' : 'Seleccioná un plan para resolver el precio vigente.'}</p></article>`;
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
