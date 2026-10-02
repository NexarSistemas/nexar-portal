import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { clearVentaDetail, createRequestGuard, currentPrices, eligibleSaleCatalog, loadVentaDetail, loadVentaFormData, loadVentas, newSaleItem, restoreSaleFormAfterSaveFailure, saleMatchesFilters, saveVenta, saleValues, searchVentaClientes, selectedSaleClient, validateSale, localDayStart, nextLocalDayStart } from '../src/dashboard/ventas.js';
import { renderVentas } from '../src/ui/ventas.js';
import { renderShell } from '../src/ui/shell.js';

const sale = { id: 'venta-1', cliente_id: 'cliente-1', vendedor_id: 'vendedor-1', fecha_venta: '2026-10-01T10:00:00Z', moneda: 'ARS', estado: 'confirmada', importe_total: 1500 };

test('lista ventas con filtros canónicos de estado y fecha', async () => {
  const calls = [];
  const request = {
    order(column, options) { calls.push(['order', column, options]); return this; },
    limit(value) { calls.push(['limit', value]); return this; },
    eq(column, value) { calls.push(['eq', column, value]); return this; },
    gte(column, value) { calls.push(['gte', column, value]); return this; },
    lt(column, value) { calls.push(['lt', column, value]); return Promise.resolve({ data: [sale], error: null }); },
  };
  const client = { from(table) { calls.push(['from', table]); return { select(fields) { calls.push(['select', fields]); return request; } }; } };

  const sales = await loadVentas(client, { estado: 'confirmada', desde: '2026-10-01', hasta: '2026-10-31' });

  assert.deepEqual(sales, [sale]);
  assert.equal(calls[0][1], 'ventas');
  assert.match(calls[1][1], /cliente_id,vendedor_id/);
  assert.ok(calls.some((call) => call.join('|') === 'eq|estado|confirmada'));
  assert.ok(calls.some(([kind, column]) => kind === 'gte' && column === 'fecha_venta'));
  assert.ok(calls.some(([kind, column]) => kind === 'lt' && column === 'fecha_venta'));
});

test('interpreta Desde y Hasta como días locales completos, incluso cerca del cambio UTC', () => {
  const previousTimeZone = process.env.TZ;
  process.env.TZ = 'America/Argentina/Buenos_Aires';
  const result = {
    desde: localDayStart('2026-10-01').toISOString(),
    hasta: nextLocalDayStart('2026-10-01').toISOString(),
    hastaSeptiembre: nextLocalDayStart('2026-09-30').toISOString(),
  };
  process.env.TZ = previousTimeZone;

  assert.deepEqual(result, {
    desde: '2026-10-01T03:00:00.000Z',
    hasta: '2026-10-02T03:00:00.000Z',
    hastaSeptiembre: '2026-10-01T03:00:00.000Z',
  });
  assert.ok(new Date('2026-10-01T01:00:00.000Z') < new Date(result.desde));
  assert.ok(new Date('2026-10-01T01:00:00.000Z') < new Date(result.hastaSeptiembre));
});

test('valida la venta manual y conserva vendedor opcional e ítems normalizados', () => {
  assert.match(validateSale({ cliente_id: '', fecha_venta: '2026-10-02T10:00', moneda: 'ARS', items: [{}] }).error, /cliente/i);
  assert.match(validateSale({ cliente_id: 'cliente-1', fecha_venta: '2026-10-02T10:00', moneda: 'ARS', items: [] }).error, /al menos un ítem/i);
  const values = saleValues({ cliente_id: ' cliente-1 ', vendedor_id: '', fecha_venta: '2026-10-02T10:00', moneda: 'ars', items: [{ producto_id: ' producto-1 ', plan_id: ' plan-1 ', cantidad: '2' }] });
  assert.deepEqual(values, { cliente_id: 'cliente-1', vendedor_id: null, fecha_venta: '2026-10-02T10:00', moneda: 'ARS', items: [{ producto_id: 'producto-1', plan_id: 'plan-1', cantidad: 2 }] });
  assert.equal(validateSale(values).error, '');
  assert.match(validateSale({ ...values, items: [{ producto_id: 'producto-1', plan_id: null, cantidad: 1 }] }).error, /producto, un plan/i);
  assert.match(validateSale({ ...values, items: [{ producto_id: 'producto-1', plan_id: 'plan-1', cantidad: 0 }] }).error, /cantidad mayor a cero/i);
  assert.match(validateSale({ ...values, items: [{ producto_id: 'producto-1', plan_id: 'plan-1', cantidad: -1 }] }).error, /cantidad mayor a cero/i);
});

test('inicializa cada ítem con cantidad real y valida sin editarla al seleccionar catálogo', () => {
  assert.deepEqual(newSaleItem(), { cantidad: 1 });
  const values = {
    cliente_id: 'cliente-1', fecha_venta: '2026-10-02T10:00', moneda: 'ARS',
    items: [{ ...newSaleItem(), producto_id: 'producto-1', plan_id: 'plan-1' }],
  };
  assert.equal(validateSale(values).error, '');
});

test('muestra solo el precio activo y vigente para la fecha de venta', () => {
  const prices = [
    { id: 'anterior', estado: 'activo', vigente_desde: '2026-01-01T00:00:00Z', vigente_hasta: '2026-10-01T00:00:00Z' },
    { id: 'actual', estado: 'activo', vigente_desde: '2026-10-01T00:00:00Z', vigente_hasta: null },
    { id: 'inactivo', estado: 'inactivo', vigente_desde: '2026-01-01T00:00:00Z', vigente_hasta: null },
  ];
  assert.deepEqual(currentPrices(prices, '2026-10-02T00:00:00Z').map(({ id }) => id), ['actual']);
});

test('ofrece únicamente productos y planes con precio vigente en fecha y moneda normalizadas', () => {
  const catalogo = {
    productos: [{ id: 'producto-ars' }, { id: 'producto-usd' }, { id: 'producto-sin-precio' }],
    planes: [
      { id: 'plan-ars', producto_id: 'producto-ars' },
      { id: 'plan-usd', producto_id: 'producto-usd' },
      { id: 'plan-sin-precio', producto_id: 'producto-sin-precio' },
    ],
    precios: [
      { id: 'precio-ars', plan_id: 'plan-ars', moneda: 'ARS', estado: 'activo', vigente_desde: '2026-01-01T00:00:00Z', vigente_hasta: null },
      { id: 'precio-usd', plan_id: 'plan-usd', moneda: 'USD', estado: 'activo', vigente_desde: '2026-01-01T00:00:00Z', vigente_hasta: null },
      { id: 'precio-vencido', plan_id: 'plan-sin-precio', moneda: 'ARS', estado: 'activo', vigente_desde: '2026-01-01T00:00:00Z', vigente_hasta: '2026-10-01T00:00:00Z' },
    ],
  };

  const ars = eligibleSaleCatalog(catalogo, { fecha_venta: '2026-10-02T10:00:00Z', moneda: ' ars ' });
  assert.equal(ars.moneda, 'ARS');
  assert.deepEqual(ars.productos.map((product) => product.id), ['producto-ars']);
  assert.deepEqual(ars.planes.map((plan) => plan.id), ['plan-ars']);
  assert.deepEqual(ars.precios.map((price) => price.id), ['precio-ars']);

  const usd = eligibleSaleCatalog(catalogo, { fecha_venta: '2026-10-02T10:00:00Z', moneda: 'USD' });
  assert.deepEqual(usd.productos.map((product) => product.id), ['producto-usd']);
  assert.deepEqual(usd.planes.map((plan) => plan.id), ['plan-usd']);
});

test('incluye una venta creada solo cuando coincide con los filtros actuales', () => {
  const pending = { ...sale, estado: 'pendiente', fecha_venta: '2026-10-02T10:00:00Z' };
  assert.equal(saleMatchesFilters(pending, {}), true);
  assert.equal(saleMatchesFilters(pending, { estado: 'pendiente' }), true);
  assert.equal(saleMatchesFilters(pending, { estado: 'confirmada' }), false);
  assert.equal(saleMatchesFilters(pending, { desde: '2026-10-02', hasta: '2026-10-02' }), true);
  assert.equal(saleMatchesFilters(pending, { hasta: '2026-10-01' }), false);
});

test('crea la venta exclusivamente mediante la RPC atómica con clave de idempotencia', async () => {
  const calls = [];
  const client = { rpc(name, args) { calls.push([name, args]); return Promise.resolve({ data: [sale], error: null }); } };
  const created = await saveVenta(client, { cliente_id: 'cliente-1', vendedor_id: '', fecha_venta: '2026-10-02T10:00', moneda: 'ars', items: [{ producto_id: 'producto-1', plan_id: 'plan-1', cantidad: '2' }] }, '00000000-0000-4000-8000-000000000001');
  assert.equal(created, sale);
  assert.deepEqual(calls, [['crear_venta_manual', {
    p_cliente_id: 'cliente-1', p_vendedor_id: null, p_fecha_venta: '2026-10-02T10:00:00.000Z', p_moneda: 'ARS', p_items: [{ producto_id: 'producto-1', plan_id: 'plan-1', cantidad: 2 }], p_idempotency_key: '00000000-0000-4000-8000-000000000001',
  }]]);
});

test('rechaza una respuesta RPC vacía antes de intentar abrir el detalle', async () => {
  const client = { rpc() { return Promise.resolve({ data: [], error: null }); } };
  await assert.rejects(
    saveVenta(client, { cliente_id: 'cliente-1', fecha_venta: '2026-10-02T10:00', moneda: 'ARS', items: [{ producto_id: 'producto-1', plan_id: 'plan-1', cantidad: 1 }] }, '00000000-0000-4000-8000-000000000002'),
    /No se devolvió la venta creada/,
  );
});

test('invalida una búsqueda de cliente pendiente al guardar y conserva el detalle creado', () => {
  const searches = createRequestGuard();
  const pendingSearch = searches.next();
  const created = { ...sale, id: 'venta-creada' };
  let state = { form: { status: 'ready' }, selected: null, detail: null };

  searches.next();
  state = { ...state, form: null, selected: created, detail: { status: 'loading' } };

  const delayedResults = [{ id: 'cliente-51', nombre_completo: 'Zoe Cliente' }];
  if (searches.isCurrent(pendingSearch)) state = { ...state, form: { clientes: delayedResults } };

  assert.equal(state.form, null);
  assert.equal(state.selected, created);
  assert.deepEqual(state.detail, { status: 'loading' });

});

test('restablece el formulario sin resultados stale si falla el guardado y permite una nueva búsqueda', () => {
  const searches = createRequestGuard();
  const pendingSearch = searches.next();
  let form = { status: 'ready', clientSearchStatus: 'loading', clientSearchError: '', clientQuery: 'consulta nueva', clientes: [{ id: 'cliente-1', nombre_completo: 'Ana' }] };

  searches.next();
  form = restoreSaleFormAfterSaveFailure(form, { cliente_id: 'cliente-1', items: [] });

  if (searches.isCurrent(pendingSearch)) form = { ...form, clientes: [{ id: 'cliente-tardío' }], clientSearchStatus: 'ready' };
  assert.equal(form.clientSearchStatus, 'idle');
  assert.equal(form.clientQuery, '');
  assert.deepEqual(form.clientes, []);
  assert.equal(form.selectedClient.id, 'cliente-1');
  assert.match(form.error, /No pudimos guardar la venta/);

  const newSearch = searches.next();
  if (searches.isCurrent(newSearch)) form = { ...form, clientes: [{ id: 'cliente-nuevo' }], clientSearchStatus: 'ready' };
  assert.equal(form.clientes[0].id, 'cliente-nuevo');
});

test('conserva el cliente seleccionado al reintentar una venta después de un fallo', () => {
  const selected = { id: 'cliente-1', nombre_completo: 'Ana' };
  const other = { id: 'cliente-2', nombre_completo: 'Beto' };
  const values = { cliente_id: selected.id, items: [] };
  const restored = restoreSaleFormAfterSaveFailure({
    status: 'ready', clientes: [selected], selectedClient: selected, clientSearchStatus: 'loading',
  }, values);

  assert.deepEqual(restored.clientes, []);
  assert.equal(restored.selectedClient, selected);
  assert.equal(selectedSaleClient(restored, selected.id), selected);

  const restoredAgain = restoreSaleFormAfterSaveFailure(restored, values);
  assert.equal(restoredAgain.selectedClient, selected);
  assert.equal(restoredAgain.values.cliente_id, selected.id);
  assert.equal(selectedSaleClient({ ...restoredAgain, clientes: [other] }, other.id), other);
  assert.equal(selectedSaleClient(restoredAgain, ''), null);
  assert.equal(selectedSaleClient(restoredAgain, other.id), null);
});

test('busca clientes de venta en servidor sin precargar un slice fijo', async () => {
  const calls = [];
  const customerBeyondFirstSlice = { id: 'cliente-51', nombre_completo: 'Zoe Cliente', email: 'zoe@example.com', numero_documento: '51' };
  const request = {
    order() { return this; },
    limit(value) { calls.push(['limit', value]); return this; },
    or(value) { calls.push(['or', value]); return Promise.resolve({ data: [customerBeyondFirstSlice], error: null }); },
  };
  const client = { from(table) { calls.push(['from', table]); return { select() { return request; } }; } };
  const results = await searchVentaClientes(client, 'zoe@example.com');
  assert.deepEqual(results, [customerBeyondFirstSlice]);
  assert.equal(calls.find(([kind]) => kind === 'from')[1], 'clientes');
  assert.match(calls.find(([kind]) => kind === 'or')[1], /zoe@example.com/);

  const catalogCalls = [];
  const catalogClient = {
    from(table) {
      catalogCalls.push(table);
      const requestForTable = {
        select() { return this; },
        eq() { return this; },
        order() { return Promise.resolve({ data: [], error: null }); },
      };
      return requestForTable;
    },
  };
  await loadVentaFormData(catalogClient);
  assert.equal(catalogCalls.includes('clientes'), false);
});

test('carga el detalle por IDs/FK y conserva los snapshots de venta_items', async () => {
  const calls = [];
  const dataByTable = {
    clientes: [{ id: 'cliente-1', nombre_completo: 'Ana Cliente' }],
    vendedores: [{ id: 'vendedor-1', codigo_vendedor: 'VEN-1' }],
    venta_items: [{ id: 'item-1', venta_id: 'venta-1', producto_nombre: 'Producto histórico', plan_nombre: 'Plan histórico', descripcion: 'Descripción histórica', cantidad: 2, precio_unitario: 500, importe_total: 1000 }],
    pagos: [{ id: 'pago-1', venta_id: 'venta-1', monto: 1500, moneda: 'ARS' }],
  };
  const client = {
    from(table) {
      calls.push(['from', table]);
      return {
        select(fields) { calls.push(['select', table, fields]); return this; },
        eq(column, value) {
          calls.push(['eq', table, column, value]);
          if (table === 'clientes' || table === 'vendedores') return Promise.resolve({ data: dataByTable[table], error: null });
          return this;
        },
        order() { return Promise.resolve({ data: dataByTable[table], error: null }); },
      };
    },
    rpc(name, args) {
      calls.push(['rpc', name, args]);
      return Promise.resolve({ data: name.startsWith('licencias') ? [{ license_key: 'ABC' }] : [{ tipo: 'venta', monto: 10 }], error: null });
    },
  };

  const detail = await loadVentaDetail(client, sale);

  assert.equal(detail.items[0].producto_nombre, 'Producto histórico');
  assert.equal(detail.items[0].precio_unitario, 500);
  assert.ok(calls.some((call) => call.join('|') === 'eq|venta_items|venta_id|venta-1'));
  assert.ok(calls.some((call) => call.join('|') === 'eq|pagos|venta_id|venta-1'));
  assert.deepEqual(calls.filter(([kind]) => kind === 'rpc').map(([kind, name, args]) => [name, args]), [
    ['licencias_admin_por_venta', { p_venta_id: 'venta-1' }],
    ['comisiones_admin_por_venta', { p_venta_id: 'venta-1' }],
  ]);
  assert.doesNotMatch(JSON.stringify(calls), /external_reference/);
});

test('representa loading, vacío, error y snapshots históricos de ventas', () => {
  assert.match(renderVentas({ status: 'loading' }), /Cargando ventas/);
  assert.match(renderVentas({ status: 'empty', items: [], filters: {} }), /No encontramos ventas/);
  assert.match(renderVentas({ status: 'error', items: [], filters: {} }), /retry-ventas/);
  const html = renderVentas({ status: 'ready', items: [sale], filters: {} }, { status: 'ready', data: {
    venta: sale, cliente: { nombre_completo: 'Ana' }, vendedor: { codigo_vendedor: 'VEN-1' }, pagos: [], licencias: [], comisiones: [],
    items: [{ producto_nombre: 'Producto histórico', plan_nombre: 'Plan histórico', descripcion: 'Descripción histórica', cantidad: 2, precio_unitario: 500, importe_total: 1000 }],
  } });
  assert.match(html, /Producto histórico[\s\S]*Plan histórico[\s\S]*500/);
  assert.match(renderVentas({ status: 'ready', items: [sale], filters: {} }, { status: 'error' }), /retry-venta-detail/);
  const form = renderVentas({ status: 'ready', items: [], filters: {}, form: { status: 'ready', values: { fecha_venta: '2026-10-02T10:00:00Z', moneda: 'ars', items: [{ producto_id: 'producto-1', plan_id: 'plan-1', cantidad: 2 }] }, clientes: [{ id: 'cliente-51', nombre_completo: 'Zoe Cliente' }], catalogo: { vendedores: [], productos: [{ id: 'producto-1', nombre: 'Comercio' }, { id: 'producto-sin-plan', nombre: 'Sin plan' }], planes: [{ id: 'plan-1', producto_id: 'producto-1', nombre: 'Mensual' }, { id: 'plan-sin-precio', producto_id: 'producto-sin-plan', nombre: 'Sin precio' }], precios: [{ id: 'precio-1', plan_id: 'plan-1', moneda: 'ARS', estado: 'activo', importe: 500, vigente_desde: '2026-01-01T00:00:00Z', vigente_hasta: null }] } } });
  assert.match(form, /Nueva venta[\s\S]*Buscar cliente[\s\S]*Zoe Cliente[\s\S]*Crear cliente[\s\S]*Precio vigente[\s\S]*500/);
  assert.doesNotMatch(form, /Sin plan/);
  assert.doesNotMatch(form, /Sin precio/);
});

test('mantiene el detalle cancelable y la navegación de ventas solo para administración', async () => {
  const guard = createRequestGuard();
  const first = guard.next();
  guard.next();
  assert.equal(guard.isCurrent(first), false);
  assert.deepEqual(clearVentaDetail({ selected: sale, detail: { status: 'loading' } }), { selected: null, detail: null });

  const root = { innerHTML: '', querySelector: () => ({ addEventListener() {} }), querySelectorAll: () => [] };
  renderShell(root, { rol: 'admin', nombre: 'Admin' }, async () => {}, null, null, 'ventas', null, {}, { status: 'empty', items: [], filters: {} });
  assert.match(root.innerHTML, /data-admin-view="ventas"[\s\S]*Ventas/);
  renderShell(root, { rol: 'vendedor', nombre: 'Vendedor' }, async () => {});
  assert.doesNotMatch(root.innerHTML, /data-admin-view="ventas"/);
});

test('la migración limita las relaciones de licencias y comisiones a una venta canónica', async () => {
  const source = await readFile(new URL('../supabase/migrations/20261001000000_issue_28_lectura_admin_ventas.sql', import.meta.url), 'utf8');
  assert.match(source, /app_private\.es_admin\(\)/);
  assert.match(source, /vi\.id = l\.venta_item_id and vi\.venta_id = p_venta_id/);
  assert.match(source, /p\.id = c\.pago_id and p\.venta_id = p_venta_id/);
  assert.doesNotMatch(source, /external_reference/);
  assert.match(source, /security invoker/);
});

test('la migración de alta manual usa una RPC invoker, snapshots e idempotencia sin external_reference', async () => {
  const source = await readFile(new URL('../supabase/migrations/20261002000000_issue_43_alta_manual_ventas.sql', import.meta.url), 'utf8');
  const validation = await readFile(new URL('../supabase/validation/20261002000000_issue_43_alta_manual_ventas.sql', import.meta.url), 'utf8');
  assert.match(source, /security invoker/);
  assert.match(source, /app_private\.es_admin\(\)/);
  assert.match(source, /manual_idempotency_key/);
  assert.match(source, /insert into public\.ventas[\s\S]*insert into public\.venta_items/);
  assert.match(source, /precio_id, descripcion, producto_nombre, plan_nombre, cantidad, precio_unitario, importe_total/);
  assert.doesNotMatch(source, /external_reference/);
  assert.match(validation, /authenticated_con_execute[\s\S]*anon_sin_execute/);
  assert.match(source, /p_items is null[\s\S]*jsonb_typeof\(p_items\) <> 'array'[\s\S]*jsonb_array_length\(p_items\) = 0/);
  assert.match(validation, /rechaza_items_sql_null[\s\S]*rechaza_json_no_array[\s\S]*rechaza_array_vacio/);
  assert.match(validation, /precio_resuelto_una_vez_por_item[\s\S]*snapshots_reutilizados_para_insertar/);
});
