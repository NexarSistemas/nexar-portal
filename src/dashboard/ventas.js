const SALE_FIELDS = 'id,cliente_id,vendedor_id,fecha_venta,moneda,estado,importe_total';
const CLIENT_FIELDS = 'id,nombre_completo,email,telefono,tipo_documento,numero_documento';
const SELLER_FIELDS = 'id,codigo_vendedor,email,telefono';
const ITEM_FIELDS = 'id,venta_id,producto_id,plan_id,precio_id,descripcion,producto_nombre,plan_nombre,cantidad,precio_unitario,importe_total';
const PAYMENT_FIELDS = 'id,venta_id,monto,moneda,proveedor_origen,estado_proveedor,decision_administrativa,created_at';
const SALE_LIST_LIMIT = 50;

export function createRequestGuard() {
  let current = 0;
  return {
    next() { current += 1; return current; },
    isCurrent(request) { return request === current; },
  };
}

export function clearVentaDetail(ventas) {
  return ventas ? { ...ventas, selected: null, detail: null } : ventas;
}

export function localDayStart(value) {
  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day);
}

export function nextLocalDayStart(value) {
  const nextDay = localDayStart(value);
  nextDay.setDate(nextDay.getDate() + 1);
  return nextDay;
}

export async function loadVentas(client, filters = {}) {
  let request = client
    .from('ventas')
    .select(SALE_FIELDS)
    .order('fecha_venta', { ascending: false })
    .limit(SALE_LIST_LIMIT);

  if (filters.estado) request = request.eq('estado', filters.estado);
  if (filters.desde) request = request.gte('fecha_venta', localDayStart(filters.desde).toISOString());
  if (filters.hasta) request = request.lt('fecha_venta', nextLocalDayStart(filters.hasta).toISOString());

  const { data, error } = await request;
  if (error) throw error;
  return data ?? [];
}

async function loadOne(client, table, fields, id) {
  const { data, error } = await client.from(table).select(fields).eq('id', id);
  if (error) throw error;
  return data?.[0] ?? null;
}

export async function loadVentaDetail(client, venta) {
  const clientRequest = loadOne(client, 'clientes', CLIENT_FIELDS, venta.cliente_id);
  const sellerRequest = venta.vendedor_id
    ? loadOne(client, 'vendedores', SELLER_FIELDS, venta.vendedor_id)
    : Promise.resolve(null);
  const itemsRequest = client
    .from('venta_items')
    .select(ITEM_FIELDS)
    .eq('venta_id', venta.id)
    .order('created_at', { ascending: true });
  const paymentsRequest = client
    .from('pagos')
    .select(PAYMENT_FIELDS)
    .eq('venta_id', venta.id)
    .order('created_at', { ascending: false });
  const licensesRequest = client.rpc('licencias_admin_por_venta', { p_venta_id: venta.id });
  const commissionsRequest = client.rpc('comisiones_admin_por_venta', { p_venta_id: venta.id });

  const [cliente, vendedor, itemsResult, pagosResult, licenciasResult, comisionesResult] = await Promise.all([
    clientRequest, sellerRequest, itemsRequest, paymentsRequest, licensesRequest, commissionsRequest,
  ]);
  for (const result of [itemsResult, pagosResult, licenciasResult, comisionesResult]) {
    if (result.error) throw result.error;
  }

  return {
    venta,
    cliente,
    vendedor,
    items: itemsResult.data ?? [],
    pagos: pagosResult.data ?? [],
    licencias: licenciasResult.data ?? [],
    comisiones: comisionesResult.data ?? [],
  };
}
