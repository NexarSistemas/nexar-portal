import { normalizeEmail, parseStaffAccess } from './contracts.js';

const AUTH_ERROR = 'No pudimos iniciar sesión. Verificá tus datos e intentá nuevamente.';
const READ_ERROR = 'No pudimos cargar la información. Intentá nuevamente.';
const ACTION_ERROR = 'No pudimos completar la acción. Intentá nuevamente.';

export async function signInFidelizacion(client, email, password) {
  const { data, error } = await client.auth.signInWithPassword({
    email: normalizeEmail(email),
    password,
  });
  if (error || !data?.user) throw new Error(AUTH_ERROR);
  return data.user;
}

export async function getSessionUser(client) {
  const { data, error } = await client.auth.getSession();
  if (error) throw new Error(READ_ERROR);
  return data.session?.user ?? null;
}

export async function signOutFidelizacion(client) {
  const { error } = await client.auth.signOut();
  if (error) throw new Error('No pudimos cerrar la sesión. Intentá nuevamente.');
}

export async function resolveStaffAccess(client, userId) {
  const { data, error } = await client
    .from('fidelizacion_staff')
    .select('rol,tenant:fidelizacion_tenants!inner(nombre,activo)')
    .eq('user_id', userId)
    .eq('activo', true)
    .eq('tenant.activo', true)
    .in('rol', ['admin', 'operador'])
    .limit(2);
  if (error) throw new Error(READ_ERROR);
  return parseStaffAccess(data);
}

export async function searchAccount(client, email) {
  const normalized = normalizeEmail(email);
  if (!normalized) throw new Error('Ingresá un email válido.');
  const { data, error } = await client.rpc('fidelizacion_buscar_cuenta_staff', {
    p_email: normalized,
  });
  if (error) throw new Error(READ_ERROR);
  return data?.[0] ?? null;
}

export async function listPendingOperations(client, accountId) {
  const { data, error } = await client
    .from('fidelizacion_operations')
    .select('id,tipo,estado,puntos,expires_at,created_at,reward:fidelizacion_rewards(nombre)')
    .eq('account_id', accountId)
    .in('estado', ['pending_customer', 'pending_staff'])
    .order('created_at', { ascending: false });
  if (error) throw new Error(READ_ERROR);
  return data ?? [];
}

export async function createEarn(client, { accountId, points, idempotencyKey }) {
  const { data, error } = await client.rpc('fidelizacion_crear_earn', {
    p_account_id: accountId,
    p_puntos: points,
    p_idempotency_key: idempotencyKey,
    p_expires_at: null,
  });
  if (error) throw new Error(ACTION_ERROR);
  return data?.[0] ?? null;
}

export async function confirmRedeem(client, operationId) {
  const { data, error } = await client.rpc('fidelizacion_confirmar_redeem', {
    p_operation_id: operationId,
  });
  if (error) throw new Error(ACTION_ERROR);
  return data?.[0] ?? null;
}

export async function cancelRedeem(client, operationId) {
  const { data, error } = await client.rpc('fidelizacion_cancelar_redeem', {
    p_operation_id: operationId,
  });
  if (error) throw new Error(ACTION_ERROR);
  return data?.[0] ?? null;
}
