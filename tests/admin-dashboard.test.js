import test from 'node:test';
import assert from 'node:assert/strict';
import { hasDashboardData, loadAdminDashboard } from '../src/dashboard/admin.js';
import { renderAdminDashboard } from '../src/ui/admin-dashboard.js';
import { renderShell } from '../src/ui/shell.js';

const expectedMetrics = [
  ['clientes', 'id'], ['ventas', 'id'], ['licencias', 'license_key'], ['vendedores', 'id'], ['comisiones', 'tipo'],
];

test('carga los conteos visibles del dashboard administrativo', async () => {
  const calls = [];
  const client = {
    from(table) {
      return { select(column, options) {
        calls.push([table, column, options]);
        return Promise.resolve({ count: 2, error: null });
      } };
    },
  };

  const metrics = await loadAdminDashboard(client);

  assert.deepEqual(calls.map(([table, column]) => [table, column]), expectedMetrics);
  assert.ok(calls.every(([, , options]) => options.count === 'exact' && options.head === true));
  assert.deepEqual(metrics.map(({ key, value }) => [key, value]), expectedMetrics.map(([key]) => [key, 2]));
});

test('propaga errores de lectura para ofrecer reintento sin cerrar sesión', async () => {
  const client = { from: () => ({ select: () => Promise.resolve({ count: null, error: new Error('denied') }) }) };
  await assert.rejects(loadAdminDashboard(client), /denied/);
});

test('renderiza loading, métricas, vacío y error del dashboard', () => {
  assert.match(renderAdminDashboard({ status: 'loading' }), /Cargando resumen operativo/);
  assert.match(renderAdminDashboard({ status: 'ready', metrics: [{ label: 'Clientes', value: 3 }] }), /Clientes[\s\S]*3/);
  assert.match(renderAdminDashboard({ status: 'empty', metrics: [] }), /Aún no hay datos/);
  assert.match(renderAdminDashboard({ status: 'error' }), /Reintentar/);
  assert.equal(hasDashboardData([{ value: 0 }]), false);
  assert.equal(hasDashboardData([{ value: 1 }]), true);
});

test('conserva el inicio del vendedor sin dashboard ni consultas administrativas', () => {
  const root = {
    innerHTML: '',
    querySelector: () => ({ addEventListener() {} }),
  };

  renderShell(root, { rol: 'vendedor', nombre: 'Vendedor' }, async () => {});

  assert.match(root.innerHTML, /Portal Vendedor/);
  assert.match(root.innerHTML, /Disponible próximamente/);
  assert.doesNotMatch(root.innerHTML, /Resumen operativo/);
});
