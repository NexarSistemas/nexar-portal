const CLIENT_FIELDS = 'id,nombre_completo,email,telefono,tipo_documento,numero_documento,created_at';
const SALE_FIELDS = 'id,fecha_venta,moneda,estado,importe_total';
const PAYMENT_FIELDS = 'id,venta_id,monto,moneda,proveedor_origen,estado_proveedor,decision_administrativa,created_at';
const CLIENT_LIST_LIMIT = 50;

function cleanOptional(value) {
  const cleaned = String(value ?? '').trim();
  return cleaned || null;
}

export function clientValues(values = {}) {
  return {
    nombre_completo: String(values.nombre_completo ?? '').trim(),
    email: cleanOptional(values.email),
    telefono: cleanOptional(values.telefono),
    tipo_documento: cleanOptional(values.tipo_documento),
    numero_documento: cleanOptional(values.numero_documento),
  };
}

export function validateClient(values) {
  const client = clientValues(values);
  if (!client.nombre_completo) return { client, error: 'Indicá el nombre completo del cliente.' };
  if (Boolean(client.tipo_documento) !== Boolean(client.numero_documento)) return { client, error: 'Completá tipo y número de documento, o dejá ambos vacíos.' };
  return { client, error: '' };
}

export function createRequestGuard() {
  let current = 0;
  return {
    next() { current += 1; return current; },
    isCurrent(request) { return request === current; },
  };
}

export function clearClienteDetail(clientes) {
  return clientes ? { ...clientes, selected: null, detail: null } : clientes;
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

export async function saveCliente(client, clienteId, values) {
  const { client: payload, error: validationError } = validateClient(values);
  if (validationError) throw new Error(validationError);
  const request = clienteId ? client.from('clientes').update(payload).eq('id', clienteId) : client.from('clientes').insert(payload);
  const { data, error } = await request.select(CLIENT_FIELDS).single();
  if (error) throw error;
  return data;
}
