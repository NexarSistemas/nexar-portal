const ADMIN_METRICS = [
  { key: 'clientes', label: 'Clientes', table: 'clientes', column: 'id' },
  { key: 'ventas', label: 'Ventas', table: 'ventas', column: 'id' },
  { key: 'pagos', label: 'Pagos', table: 'pagos', column: 'id' },
  { key: 'licencias', label: 'Licencias', table: 'licencias', column: 'license_key' },
  { key: 'vendedores', label: 'Vendedores', table: 'vendedores', column: 'id' },
  { key: 'comisiones', label: 'Comisiones', table: 'comisiones', column: 'tipo' },
];

export async function loadAdminDashboard(client) {
  const results = await Promise.all(ADMIN_METRICS.map(async (metric) => {
    const { count, error } = await client
      .from(metric.table)
      .select(metric.column, { count: 'exact', head: true });

    if (error) throw error;
    return { key: metric.key, label: metric.label, value: count ?? 0 };
  }));

  return results;
}

export function hasDashboardData(metrics) {
  return metrics.some((metric) => metric.value > 0);
}
