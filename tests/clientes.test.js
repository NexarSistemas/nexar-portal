import test from 'node:test';
import assert from 'node:assert/strict';
import { clearClienteDetail, clientValues, createRequestGuard, loadClienteDetail, loadClientes, saveCliente, searchTerm, validateClient } from '../src/dashboard/clientes.js';
import { renderClientes } from '../src/ui/clientes.js';
import { renderShell } from '../src/ui/shell.js';

const customer = { id: 'cliente-1', nombre_completo: 'Ana Cliente', email: 'ana@example.com', telefono: '264-123', tipo_documento: 'DNI', numero_documento: '123', created_at: '2026-01-01T00:00:00Z' };

test('lista clientes con campos acotados y búsqueda por datos canónicos', async () => {
  const calls = [];
  const request = { order() { return this; }, limit() { return this; }, or(value) { calls.push(['or', value]); return Promise.resolve({ data: [customer], error: null }); } };
  const client = { from(table) { calls.push(['from', table]); return { select(fields) { calls.push(['select', fields]); return request; } }; } };
  const items = await loadClientes(client, ' ana@example.com ');
  assert.deepEqual(items, [customer]);
  assert.deepEqual(calls.slice(0, 2), [['from', 'clientes'], ['select', 'id,nombre_completo,email,telefono,tipo_documento,numero_documento,created_at']]);
  assert.equal(calls[2][1], 'nombre_completo.ilike.%ana@example.com%,email.ilike.%ana@example.com%,numero_documento.ilike.%ana@example.com%');
  assert.equal(searchTerm('a,%_()b'), 'ab');
});

test('representa búsqueda sin resultados, loading, error y reintento', () => {
  assert.match(renderClientes({ status: 'loading' }), /Cargando clientes/);
  assert.match(renderClientes({ status: 'empty', items: [], query: 'nadie' }), /No encontramos clientes/);
  assert.match(renderClientes({ status: 'error', items: [] }), /retry-clientes/);
  assert.match(renderClientes({ status: 'ready', items: [customer] }, { status: 'loading' }), /Cargando detalle del cliente/);
  assert.match(renderClientes({ status: 'ready', items: [customer] }, { status: 'error' }), /retry-client-detail/);
});

test('normaliza y valida únicamente los campos canónicos editables del cliente', () => {
  assert.deepEqual(clientValues({ nombre_completo: ' Ana ', email: ' ana@example.com ', telefono: ' 264 ', tipo_documento: ' DNI ', numero_documento: ' 123 ' }), {
    nombre_completo: 'Ana', email: 'ana@example.com', telefono: '264', tipo_documento: 'DNI', numero_documento: '123',
  });
  assert.equal(validateClient({ nombre_completo: ' ' }).error, 'Indicá el nombre completo del cliente.');
  assert.match(validateClient({ nombre_completo: 'Ana', tipo_documento: 'DNI' }).error, /tipo y número/i);
  assert.equal(validateClient({ nombre_completo: 'Ana', tipo_documento: '', numero_documento: '' }).error, '');
});

test('crea y edita clientes con el UUID estable y sin campos no permitidos', async () => {
  const calls = [];
  const saved = { ...customer, telefono: 'nuevo' };
  const query = {
    select(fields) { calls.push(['select', fields]); return this; },
    single() { return Promise.resolve({ data: saved, error: null }); },
    eq(field, value) { calls.push(['eq', field, value]); return this; },
  };
  const client = {
    from(table) {
      calls.push(['from', table]);
      return {
        insert(payload) { calls.push(['insert', payload]); return query; },
        update(payload) { calls.push(['update', payload]); return query; },
      };
    },
  };
  await saveCliente(client, null, { nombre_completo: 'Ana', email: '', telefono: '', tipo_documento: '', numero_documento: '' });
  await saveCliente(client, customer.id, { nombre_completo: 'Ana', email: '', telefono: 'nuevo', tipo_documento: '', numero_documento: '' });
  assert.deepEqual(calls.filter(([kind]) => kind === 'from'), [['from', 'clientes'], ['from', 'clientes']]);
  assert.deepEqual(calls.find(([kind]) => kind === 'insert')[1], { nombre_completo: 'Ana', email: null, telefono: null, tipo_documento: null, numero_documento: null });
  assert.deepEqual(calls.find(([kind]) => kind === 'update')[1], { nombre_completo: 'Ana', email: null, telefono: 'nuevo', tipo_documento: null, numero_documento: null });
  assert.deepEqual(calls.find(([kind]) => kind === 'eq'), ['eq', 'id', customer.id]);
  assert.doesNotMatch(JSON.stringify(calls.find(([kind]) => kind === 'insert')[1]), /id|created_at|updated_at/);
});

test('muestra formulario de alta y edición, errores y confirmación de guardado', () => {
  const create = renderClientes({ status: 'empty', items: [], form: { id: null, values: {}, status: 'ready', error: '' } });
  assert.match(create, /Nuevo cliente[\s\S]*client-form[\s\S]*Crear cliente/);
  assert.match(create, /nombre_completo[\s\S]*tipo_documento[\s\S]*numero_documento/);
  const edit = renderClientes({ status: 'ready', items: [customer], notice: 'Los cambios se guardaron correctamente.' }, { status: 'ready', data: { cliente: customer, ventas: [], pagos: [], licencias: [] } });
  assert.match(edit, /guardaron correctamente[\s\S]*Editar[\s\S]*Identidad estable[\s\S]*cliente-1/);
  const failure = renderClientes({ status: 'ready', items: [customer], form: { id: customer.id, values: customer, status: 'ready', error: 'Completá tipo y número de documento.' } });
  assert.match(failure, /Completá tipo y número de documento/);
});

test('ignora respuestas tardías de búsquedas y detalles invalidados', async () => {
  const deferred = () => {
    let resolve;
    return { promise: new Promise((done) => { resolve = done; }), resolve };
  };
  const searches = createRequestGuard();
  let searchState = null;
  const firstSearchResponse = deferred();
  const firstSearch = searches.next();
  const applySearch = async (request, response) => {
    const result = await response;
    if (searches.isCurrent(request)) searchState = result;
  };
  const firstSearchPending = applySearch(firstSearch, firstSearchResponse.promise);
  const secondSearch = searches.next();
  const secondSearchResponse = deferred();
  const secondSearchPending = applySearch(secondSearch, secondSearchResponse.promise);
  secondSearchResponse.resolve('nueva búsqueda');
  firstSearchResponse.resolve('búsqueda anterior');
  await Promise.all([firstSearchPending, secondSearchPending]);
  assert.equal(searchState, 'nueva búsqueda');

  const details = createRequestGuard();
  let detailState = null;
  const firstDetailResponse = deferred();
  const firstDetail = details.next();
  const applyDetail = async (request, response) => {
    const result = await response;
    if (details.isCurrent(request)) detailState = result;
  };
  const firstDetailPending = applyDetail(firstDetail, firstDetailResponse.promise);
  const secondDetail = details.next();
  details.next();
  firstDetailResponse.resolve('detalle anterior');
  await firstDetailPending;
  assert.equal(detailState, null);
  assert.equal(details.isCurrent(secondDetail), false);
});

test('invalida un listado pendiente al abrir o cambiar el formulario de cliente', async () => {
  let resolve;
  const pendingList = new Promise((done) => { resolve = done; });
  const listings = createRequestGuard();
  let state = { form: null, items: [] };
  const request = listings.next();
  const loading = pendingList.then((items) => {
    if (listings.isCurrent(request)) state = { form: null, items };
  });

  listings.next();
  state = { ...state, form: { id: null, values: { nombre_completo: 'Texto sin guardar' } } };
  resolve([customer]);
  await loading;

  assert.equal(state.form.values.nombre_completo, 'Texto sin guardar');
  assert.deepEqual(state.items, []);
});

test('ignora success y error de guardados que ya no corresponden al formulario activo', async () => {
  const saves = createRequestGuard();
  let state = { form: { id: null, values: { nombre_completo: 'Alta activa' }, status: 'saving' }, notice: '' };
  const firstSave = saves.next();
  const applySuccess = () => {
    if (saves.isCurrent(firstSave)) state = { form: null, notice: 'El cliente se creó correctamente.' };
  };
  const applyError = () => {
    if (saves.isCurrent(firstSave)) state = { ...state, form: { ...state.form, status: 'ready', error: 'No pudimos guardar el cliente.' } };
  };

  saves.next();
  state = { form: { id: customer.id, values: { nombre_completo: 'Edición nueva' }, status: 'ready' }, notice: '' };
  applySuccess();
  applyError();

  assert.deepEqual(state, { form: { id: customer.id, values: { nombre_completo: 'Edición nueva' }, status: 'ready' }, notice: '' });
});

test('limpia detalle pendiente al salir de Clientes y no lo restaura al volver', async () => {
  let resolve;
  const pendingDetail = new Promise((done) => { resolve = done; });
  const details = createRequestGuard();
  let state = { status: 'ready', items: [customer], selected: customer, detail: { status: 'loading' } };
  const request = details.next();
  const applyDetail = async () => {
    const data = await pendingDetail;
    if (details.isCurrent(request)) state = { ...state, detail: { status: 'ready', data } };
  };
  const loading = applyDetail();

  details.next();
  state = clearClienteDetail(state);
  resolve({ cliente: customer });
  await loading;

  assert.equal(state.selected, null);
  assert.equal(state.detail, null);
  const returnedToClients = renderClientes(state, state.detail);
  assert.doesNotMatch(returnedToClients, /Cargando detalle del cliente|Ana Cliente<\/h2>/);
});

test('carga detalle con ventas, pagos por venta_id y licencias exclusivamente por RPC', async () => {
  const calls = [];
  const sales = [{ id: 'venta-1', fecha_venta: '2026-01-02T00:00:00Z', moneda: 'ARS', estado: 'confirmada', importe_total: 100 }];
  const payments = [{ id: 'pago-1', venta_id: 'venta-1', monto: 100, moneda: 'ARS', proveedor_origen: 'mp', estado_proveedor: 'approved', decision_administrativa: 'aprobado', created_at: '2026-01-03T00:00:00Z' }];
  const client = {
    from(table) {
      calls.push(['from', table]);
      return {
        select(fields) { calls.push(['select', table, fields]); return this; },
        eq(column, value) { calls.push(['eq', table, column, value]); return this; },
        in(column, value) { calls.push(['in', table, column, value]); return this; },
        order() { return table === 'ventas' ? Promise.resolve({ data: sales, error: null }) : Promise.resolve({ data: payments, error: null }); },
      };
    },
    rpc(name, args) { calls.push(['rpc', name, args]); return Promise.resolve({ data: [{ cliente_id: customer.id, license_key: 'ABC-123' }], error: null }); },
  };
  const detail = await loadClienteDetail(client, customer);
  assert.deepEqual(detail.pagos, payments);
  assert.deepEqual(calls.find(([kind, table]) => kind === 'from' && table === 'ventas'), ['from', 'ventas']);
  assert.ok(calls.some((call) => call.join('|') === 'eq|ventas|cliente_id|cliente-1'));
  assert.deepEqual(calls.find(([kind, table]) => kind === 'in' && table === 'pagos'), ['in', 'pagos', 'venta_id', ['venta-1']]);
  assert.deepEqual(calls.find(([kind]) => kind === 'rpc'), ['rpc', 'licencias_admin_por_cliente', { p_cliente_id: 'cliente-1' }]);
  assert.doesNotMatch(JSON.stringify(calls), /external_reference|license_key.*select/i);
  assert.equal(calls.some(([kind, table]) => kind === 'from' && table === 'licencias'), false);
  const html = renderClientes({ status: 'ready', items: [customer] }, { status: 'ready', data: detail });
  assert.match(html, /Ventas[\s\S]*Pagos[\s\S]*ABC-123/);
});

test('muestra navegación administrativa también en mobile y no expone Clientes al vendedor', async () => {
  const root = { innerHTML: '', querySelector: () => ({ addEventListener() {} }), querySelectorAll: () => [] };
  renderShell(root, { rol: 'admin', nombre: 'Admin' }, async () => {}, null, null, 'clientes', { status: 'empty', items: [] }, {});
  assert.match(root.innerHTML, /data-admin-view="inicio"[\s\S]*Clientes/);
  assert.match(root.innerHTML, /No encontramos clientes/);
  renderShell(root, { rol: 'vendedor', nombre: 'Vendedor' }, async () => {});
  assert.doesNotMatch(root.innerHTML, /data-admin-view="clientes"|>Clientes</);
  const css = await import('node:fs/promises').then(({ readFile }) => readFile(new URL('../src/styles/main.css', import.meta.url), 'utf8'));
  assert.match(css, /@media\(max-width:760px\)[\s\S]*\.sidebar nav\{display:flex;gap:6px\}/);
  assert.doesNotMatch(css, /\.nav-label,\.sidebar nav\{\s*display:none/);
});
