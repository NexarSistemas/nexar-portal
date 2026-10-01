import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { clearVentaDetail, createRequestGuard, loadVentaDetail, loadVentas } from '../src/dashboard/ventas.js';
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
