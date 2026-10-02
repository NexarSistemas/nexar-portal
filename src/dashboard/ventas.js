const SALE_FIELDS = 'id,cliente_id,vendedor_id,fecha_venta,moneda,estado,importe_total';
const CLIENT_FIELDS = 'id,nombre_completo,email,telefono,tipo_documento,numero_documento';
const SELLER_FIELDS = 'id,codigo_vendedor,email,telefono';
const ITEM_FIELDS = 'id,venta_id,producto_id,plan_id,precio_id,descripcion,producto_nombre,plan_nombre,cantidad,precio_unitario,importe_total';
const PAYMENT_FIELDS = 'id,venta_id,monto,moneda,proveedor_origen,estado_proveedor,decision_administrativa,created_at';
const SALE_LIST_LIMIT = 50;
const FORM_CLIENT_FIELDS = 'id,nombre_completo,email,numero_documento';
const FORM_SELLER_FIELDS = 'id,codigo_vendedor';
const PRODUCT_FIELDS = 'id,nombre';
const PLAN_FIELDS = 'id,producto_id,nombre';
const PRICE_FIELDS = 'id,plan_id,moneda,importe,estado,vigente_desde,vigente_hasta';

function cleanOptional(value) {
  const cleaned = String(value ?? '').trim();
  return cleaned || null;
}

export function saleValues(values = {}) {
  return {
    cliente_id: cleanOptional(values.cliente_id),
    vendedor_id: cleanOptional(values.vendedor_id),
    fecha_venta: cleanOptional(values.fecha_venta),
    moneda: String(values.moneda ?? 'ARS').trim().toUpperCase(),
    items: (values.items ?? []).map((item) => ({
      producto_id: cleanOptional(item.producto_id),
      plan_id: cleanOptional(item.plan_id),
      cantidad: Number(item.cantidad),
    })),
  };
}

export function validateSale(values) {
  const sale = saleValues(values);
  if (!sale.cliente_id) return { sale, error: 'Seleccioná un cliente.' };
  if (!sale.fecha_venta) return { sale, error: 'Indicá la fecha de la venta.' };
  if (!/^[A-Z]{3}$/.test(sale.moneda)) return { sale, error: 'Indicá una moneda válida.' };
  if (!sale.items.length) return { sale, error: 'Agregá al menos un ítem.' };
  if (sale.items.some((item) => !item.producto_id || !Number.isFinite(item.cantidad) || item.cantidad <= 0)) return { sale, error: 'Cada ítem requiere un producto y una cantidad mayor a cero.' };
  return { sale, error: '' };
}

export function currentPrices(prices, at) {
  const when = new Date(at).getTime();
  return (prices ?? []).filter((price) => price.estado === 'activo'
    && new Date(price.vigente_desde).getTime() <= when
    && (!price.vigente_hasta || new Date(price.vigente_hasta).getTime() > when));
}

export async function loadVentaFormData(client) {
  const clientsRequest = client.from('clientes').select(FORM_CLIENT_FIELDS).order('nombre_completo', { ascending: true }).limit(SALE_LIST_LIMIT);
  const sellersRequest = client.from('vendedores').select(FORM_SELLER_FIELDS).order('codigo_vendedor', { ascending: true });
  const productsRequest = client.from('productos').select(PRODUCT_FIELDS).eq('activo', true).order('nombre', { ascending: true });
  const plansRequest = client.from('planes').select(PLAN_FIELDS).eq('activo', true).order('nombre', { ascending: true });
  const pricesRequest = client.from('precios').select(PRICE_FIELDS).eq('estado', 'activo').order('vigente_desde', { ascending: false });
  const results = await Promise.all([clientsRequest, sellersRequest, productsRequest, plansRequest, pricesRequest]);
  for (const result of results) if (result.error) throw result.error;
  return {
    clientes: results[0].data ?? [], vendedores: results[1].data ?? [], productos: results[2].data ?? [], planes: results[3].data ?? [], precios: results[4].data ?? [],
  };
}

export async function saveVenta(client, values, idempotencyKey) {
  const { sale, error } = validateSale(values);
  if (error) throw new Error(error);
  const { data, error: rpcError } = await client.rpc('crear_venta_manual', {
    p_cliente_id: sale.cliente_id,
    p_vendedor_id: sale.vendedor_id,
    p_fecha_venta: new Date(sale.fecha_venta).toISOString(),
    p_moneda: sale.moneda,
    p_items: sale.items,
    p_idempotency_key: idempotencyKey,
  });
  if (rpcError) throw rpcError;
  return data;
}

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
