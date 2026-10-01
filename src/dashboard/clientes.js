const CLIENT_FIELDS = 'id,nombre_completo,email,telefono,tipo_documento,numero_documento,created_at';
const SALE_FIELDS = 'id,fecha_venta,moneda,estado,importe_total';
const PAYMENT_FIELDS = 'id,venta_id,monto,moneda,proveedor_origen,estado_proveedor,decision_administrativa,created_at';
const CLIENT_LIST_LIMIT = 50;

export function createRequestGuard() {
  let current = 0;
  return {
    next() { current += 1; return current; },
    isCurrent(request) { return request === current; },
  };
}

export function searchTerm(value) {
  return String(value ?? '').trim().replace(/[,%_()]/g, '');
}

export async function loadClientes(client, query = '') {
  let request = client
    .from('clientes')
    .select(CLIENT_FIELDS)
    .order('created_at', { ascending: false })
    .limit(CLIENT_LIST_LIMIT);
  const term = searchTerm(query);
  if (term) request = request.or(`nombre_completo.ilike.%${term}%,email.ilike.%${term}%,numero_documento.ilike.%${term}%`);

  const { data, error } = await request;
  if (error) throw error;
  return data ?? [];
}

export async function loadClienteDetail(client, cliente) {
  const salesRequest = client
    .from('ventas')
    .select(SALE_FIELDS)
    .eq('cliente_id', cliente.id)
    .order('fecha_venta', { ascending: false });
  const licensesRequest = client.rpc('licencias_admin_por_cliente', { p_cliente_id: cliente.id });
  const [{ data: ventas, error: ventasError }, { data: licencias, error: licenciasError }] = await Promise.all([salesRequest, licensesRequest]);
  if (ventasError) throw ventasError;
  if (licenciasError) throw licenciasError;

  const ventaIds = (ventas ?? []).map(({ id }) => id);
  let pagos = [];
  if (ventaIds.length) {
    const { data, error } = await client
      .from('pagos')
      .select(PAYMENT_FIELDS)
      .in('venta_id', ventaIds)
      .order('created_at', { ascending: false });
    if (error) throw error;
    pagos = data ?? [];
  }

  return { cliente, ventas: ventas ?? [], pagos, licencias: licencias ?? [] };
}
