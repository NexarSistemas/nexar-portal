import {
  calculateBalance,
  createQrContext,
  normalizeClientAccounts,
  normalizeRpcRow,
} from './client-contracts.js';

const READ_ERROR = 'No pudimos cargar tu programa de puntos. Intentá nuevamente.';
const ACTION_ERROR = 'No pudimos completar la acción. Intentá nuevamente.';
const ASSOCIATION_ERROR = 'No pudimos vincular tu cuenta con este comercio.';

export async function registerClientAccount(client, qrCode) {
  const { data, error } = await client.rpc('fidelizacion_registrar_cuenta_cliente', {
    p_public_qr_code: qrCode,
  });
  if (error) throw new Error(ASSOCIATION_ERROR);
  const account = normalizeRpcRow(data);
  if (!account?.account_id || !account?.tenant_id) throw new Error(ASSOCIATION_ERROR);
  return account;
}

export async function listClientAccounts(client, userId) {
  const { data, error } = await client
    .from('fidelizacion_accounts')
    .select('id,tenant_id,tenant:fidelizacion_tenants!inner(nombre,activo)')
    .eq('user_id', userId)
    .eq('activo', true)
    .eq('tenant.activo', true)
    .order('created_at', { ascending: true });
  if (error) throw new Error(READ_ERROR);
  return normalizeClientAccounts(data);
}

export async function loadClientAccess(client, { userId, qrCode }) {
  let qrContext = null;
  let associationError = null;
  if (qrCode) {
    try {
      const association = await registerClientAccount(client, qrCode);
      qrContext = createQrContext(qrCode, association.tenant_id);
    } catch (error) {
      associationError = error;
    }
  }
  const accounts = await listClientAccounts(client, userId);
  return { accounts, qrContext, associationError };
}

export async function listClientRewards(client, tenantId) {
  const { data, error } = await client
    .from('fidelizacion_rewards')
    .select('id,nombre,descripcion,puntos_requeridos')
    .eq('tenant_id', tenantId)
    .eq('activa', true)
    .order('puntos_requeridos', { ascending: true });
  if (error) throw new Error(READ_ERROR);
  return data ?? [];
}

export async function listClientMovements(client, accountId) {
  const { data, error } = await client
    .from('fidelizacion_point_movements')
    .select('tipo,puntos,descripcion,fecha,operation:fidelizacion_operations(reward:fidelizacion_rewards(nombre))')
    .eq('account_id', accountId)
    .order('fecha', { ascending: false })
    .limit(50);
  if (error) throw new Error(READ_ERROR);
  return data ?? [];
}

export async function getClientBalance(client, accountId) {
  const pageSize = 100;
  let from = 0;
  let balance = 0;
  while (true) {
    const { data, error } = await client
      .from('fidelizacion_point_movements')
      .select('id,puntos')
      .eq('account_id', accountId)
      .order('id', { ascending: true })
      .range(from, from + pageSize - 1);
    if (error) throw new Error(READ_ERROR);
    const movements = data ?? [];
    balance += calculateBalance(movements);
    if (movements.length < pageSize) return balance;
    from += pageSize;
  }
}

export async function listClientOperations(client, accountId) {
  const { data, error } = await client
    .from('fidelizacion_operations')
    .select('id,tipo,estado,puntos,expires_at,created_at,reward:fidelizacion_rewards(nombre)')
    .eq('account_id', accountId)
    .in('estado', ['pending_customer', 'pending_staff'])
    .order('created_at', { ascending: false });
  if (error) throw new Error(READ_ERROR);
  return data ?? [];
}

export async function getPendingEarns(client, qrCode) {
  const { data, error } = await client.rpc('fidelizacion_obtener_earn_pendientes', {
    p_public_qr_code: qrCode,
  });
  if (error) throw new Error(READ_ERROR);
  return Array.isArray(data) ? data : [];
}

export async function confirmClientEarn(client, { qrCode, operationId }) {
  const { data, error } = await client.rpc('fidelizacion_confirmar_earn', {
    p_public_qr_code: qrCode,
    p_operation_id: operationId,
  });
  if (error) throw new Error(ACTION_ERROR);
  const operation = normalizeRpcRow(data);
  if (!operation?.operation_id) throw new Error(ACTION_ERROR);
  return operation;
}

export async function createClientRedeem(client, { rewardId, idempotencyKey }) {
  const { data, error } = await client.rpc('fidelizacion_crear_redeem', {
    p_reward_id: rewardId,
    p_idempotency_key: idempotencyKey,
    p_expires_at: null,
  });
  if (error) throw new Error(ACTION_ERROR);
  const operation = normalizeRpcRow(data);
  if (!operation?.operation_id) throw new Error(ACTION_ERROR);
  return operation;
}

export async function scanClientRedeem(client, { qrCode, operationId }) {
  const { data, error } = await client.rpc('fidelizacion_escanear_redeem', {
    p_public_qr_code: qrCode,
    p_operation_id: operationId,
  });
  if (error) throw new Error(ACTION_ERROR);
  const operation = normalizeRpcRow(data);
  if (!operation?.operation_id) throw new Error(ACTION_ERROR);
  return operation;
}
