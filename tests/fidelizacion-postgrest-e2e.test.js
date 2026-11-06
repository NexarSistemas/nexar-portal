import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { guardedFetch, validateConfiguration } from '../scripts/fidelizacion-e2e-safety.js';

const required = [
  'E2E_FIDELIZACION_URL',
  'E2E_FIDELIZACION_ANON_KEY',
  'E2E_FIDELIZACION_OPERATOR_A_EMAIL',
  'E2E_FIDELIZACION_OPERATOR_A_PASSWORD',
  'E2E_FIDELIZACION_OPERATOR_B_EMAIL',
  'E2E_FIDELIZACION_OPERATOR_B_PASSWORD',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_EMAIL',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_PASSWORD',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_REWARD_ID',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_EMAIL',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_PASSWORD',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_ACCOUNT_ID',
  'E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_REWARD_ID',
  'E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_EMAIL',
  'E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_PASSWORD',
  'E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_A_ACCOUNT_ID',
  'E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_B_ACCOUNT_ID',
];
const missing = required.filter((name) => !process.env[name]);

function clientFor(url, anonKey) {
  return createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: guardedFetch(url) },
  });
}

async function tokenFor(client, email, password) {
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  assert.ok(!error, 'la sesión E2E debe poder autenticarse');
  assert.ok(data.session?.access_token, 'la sesión E2E debe devolver un access token');
  return data.session.access_token;
}

async function dataApi(url, anonKey, token, path, options = {}) {
  const response = await guardedFetch(url)(new URL(path, url), {
    ...options,
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${token ?? anonKey}`,
      ...(options.headers ?? {}),
    },
  });
  const body = await response.json().catch(() => null);
  return { response, body };
}

function rpc(url, anonKey, token, name, body) {
  return dataApi(url, anonKey, token, `rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

function rewardPath(rewardId) {
  return `rest/v1/fidelizacion_rewards?select=id&id=eq.${encodeURIComponent(rewardId)}`;
}

function assertForbidden(result, message) {
  assert.equal(result.response.status, 403, message);
  assert.equal(result.body?.code, '42501', message);
}

test('PostgREST preserva el aislamiento de Fidelización sin mutar fixtures', {
  skip: missing.length && !process.env.REQUIRE_FIDELIZACION_E2E
    ? `requiere variables E2E autorizadas: ${missing.join(', ')}`
    : false,
}, async () => {
  assert.equal(missing.length, 0, `requiere variables E2E autorizadas: ${missing.join(', ')}`);
  const url = validateConfiguration(process.env, required).href;
  const anonKey = process.env.E2E_FIDELIZACION_ANON_KEY;
  const operatorAToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_OPERATOR_A_EMAIL,
    process.env.E2E_FIDELIZACION_OPERATOR_A_PASSWORD,
  );
  const operatorBToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_OPERATOR_B_EMAIL,
    process.env.E2E_FIDELIZACION_OPERATOR_B_PASSWORD,
  );
  const exclusiveCustomerAToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_EMAIL,
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_PASSWORD,
  );
  const exclusiveCustomerBToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_EMAIL,
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_PASSWORD,
  );
  const multiTenantCustomerToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_EMAIL,
    process.env.E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_PASSWORD,
  );

  const operatorSearch = await rpc(url, anonKey, operatorAToken,
    'fidelizacion_buscar_cuenta_staff', {
      p_email: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_EMAIL,
    });
  assert.equal(operatorSearch.response.status, 200, 'el operador debe poder buscar su cliente');
  assert.ok(Array.isArray(operatorSearch.body) && operatorSearch.body.length === 1,
    'la búsqueda del operador debe devolver una cuenta de su tenant');

  const otherOperatorSearch = await rpc(url, anonKey, operatorBToken,
    'fidelizacion_buscar_cuenta_staff', {
      p_email: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_EMAIL,
    });
  assert.equal(otherOperatorSearch.response.status, 200,
    'el staff del otro tenant recibe una respuesta de búsqueda válida');
  assert.deepEqual(otherOperatorSearch.body, [],
    'el staff del otro tenant no puede encontrar un cliente ajeno');

  const customerBalance = await rpc(url, anonKey, exclusiveCustomerAToken,
    'fidelizacion_obtener_saldo_cliente', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID,
    });
  assert.equal(customerBalance.response.status, 200, 'el cliente debe poder consultar su saldo');
  assert.ok(Number.isFinite(Number(customerBalance.body)), 'el saldo debe ser numérico');

  const otherCustomerBalance = await rpc(url, anonKey, exclusiveCustomerBToken,
    'fidelizacion_obtener_saldo_cliente', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_ACCOUNT_ID,
    });
  assert.equal(otherCustomerBalance.response.status, 200,
    'el otro cliente debe poder consultar únicamente su propio saldo');
  assert.ok(Number.isFinite(Number(otherCustomerBalance.body)),
    'el saldo del otro cliente debe ser numérico');

  const customerOperations = await rpc(url, anonKey, exclusiveCustomerAToken,
    'fidelizacion_obtener_operaciones_pendientes', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID,
    });
  const otherCustomerOperations = await rpc(url, anonKey, exclusiveCustomerBToken,
    'fidelizacion_obtener_operaciones_pendientes', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_ACCOUNT_ID,
    });
  assert.equal(customerOperations.response.status, 200,
    'el cliente debe poder leer únicamente sus operaciones pendientes');
  assert.ok(Array.isArray(customerOperations.body), 'las operaciones propias deben ser una lista');
  assert.equal(otherCustomerOperations.response.status, 200,
    'el otro cliente debe poder leer únicamente sus operaciones pendientes');
  assert.ok(Array.isArray(otherCustomerOperations.body),
    'las operaciones propias del otro cliente deben ser una lista');

  const crossCustomerBalance = await rpc(url, anonKey, exclusiveCustomerAToken,
    'fidelizacion_obtener_saldo_cliente', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_ACCOUNT_ID,
    });
  assertForbidden(crossCustomerBalance, 'un cliente no puede consultar el saldo de otro tenant');

  const crossCustomerOperations = await rpc(url, anonKey, exclusiveCustomerAToken,
    'fidelizacion_obtener_operaciones_pendientes', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_ACCOUNT_ID,
    });
  assertForbidden(crossCustomerOperations,
    'un cliente no puede consultar las operaciones de otro tenant');

  const reverseCrossCustomerBalance = await rpc(url, anonKey, exclusiveCustomerBToken,
    'fidelizacion_obtener_saldo_cliente', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID,
    });
  assertForbidden(reverseCrossCustomerBalance, 'el aislamiento de saldo debe ser bidireccional');

  const reverseCrossCustomerOperations = await rpc(url, anonKey, exclusiveCustomerBToken,
    'fidelizacion_obtener_operaciones_pendientes', {
      p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID,
    });
  assertForbidden(reverseCrossCustomerOperations,
    'el aislamiento de operaciones debe ser bidireccional');

  const ownReward = await dataApi(url, anonKey, exclusiveCustomerAToken,
    rewardPath(process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_REWARD_ID));
  const otherReward = await dataApi(url, anonKey, exclusiveCustomerBToken,
    rewardPath(process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_REWARD_ID));
  const crossReward = await dataApi(url, anonKey, exclusiveCustomerAToken,
    rewardPath(process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_REWARD_ID));
  const reverseCrossReward = await dataApi(url, anonKey, exclusiveCustomerBToken,
    rewardPath(process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_REWARD_ID));
  assert.equal(ownReward.response.status, 200, 'el cliente debe poder leer una recompensa de su tenant');
  assert.deepEqual(ownReward.body, [{ id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_REWARD_ID }],
    'la recompensa propia debe resolverse de forma determinista');
  assert.equal(otherReward.response.status, 200,
    'el otro cliente debe poder leer una recompensa de su tenant');
  assert.deepEqual(otherReward.body, [{ id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_REWARD_ID }],
    'la recompensa del otro tenant debe resolverse de forma determinista');
  assert.deepEqual(crossReward.body, [], 'un cliente no puede leer recompensas de otro tenant');
  assert.deepEqual(reverseCrossReward.body, [],
    'el aislamiento de recompensas debe ser bidireccional');

  const customerStaffRpc = await rpc(url, anonKey, exclusiveCustomerAToken,
    'fidelizacion_buscar_cuenta_staff', {
      p_email: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_EMAIL,
    });
  assertForbidden(customerStaffRpc, 'un cliente no puede invocar el RPC administrativo de staff');

  for (const [rpcName, body] of [
    ['fidelizacion_buscar_cuenta_staff', { p_email: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_EMAIL }],
    ['fidelizacion_obtener_saldo_cliente', { p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID }],
    ['fidelizacion_obtener_operaciones_pendientes', { p_account_id: process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID }],
  ]) {
    const anonymous = await rpc(url, anonKey, null, rpcName, body);
    assert.equal(anonymous.response.ok, false, `anon no puede ejecutar ${rpcName}`);
  }

  for (const accountId of [
    process.env.E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_A_ACCOUNT_ID,
    process.env.E2E_FIDELIZACION_MULTI_TENANT_CUSTOMER_B_ACCOUNT_ID,
  ]) {
    const balance = await rpc(url, anonKey, multiTenantCustomerToken,
      'fidelizacion_obtener_saldo_cliente', { p_account_id: accountId });
    const operations = await rpc(url, anonKey, multiTenantCustomerToken,
      'fidelizacion_obtener_operaciones_pendientes', { p_account_id: accountId });
    assert.equal(balance.response.status, 200,
      'el cliente asociado a ambos tenants debe poder consultar cada saldo propio');
    assert.equal(operations.response.status, 200,
      'el cliente asociado a ambos tenants debe poder consultar cada operación propia');
  }

  for (const rewardId of [
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_REWARD_ID,
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_REWARD_ID,
  ]) {
    const reward = await dataApi(url, anonKey, multiTenantCustomerToken, rewardPath(rewardId));
    assert.equal(reward.response.status, 200,
      'el cliente asociado a ambos tenants debe poder consultar cada recompensa activa');
    assert.deepEqual(reward.body, [{ id: rewardId }],
      'el cliente asociado a ambos tenants debe poder leer recompensas activas de ambos');
  }
});

test('B2: acreditación y canje autorizados con fixtures descartables', {
  skip: process.env.E2E_FIDELIZACION_DISPOSABLE !== '1'
    ? 'requiere fixtures locales descartables explícitos' : false,
}, async () => {
  const url = validateConfiguration(process.env, [...required, 'E2E_FIDELIZACION_TENANT_A_QR']).href;
  const key = process.env.E2E_FIDELIZACION_ANON_KEY;
  const accountA = process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID;
  const accountB = process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_ACCOUNT_ID;
  const reward = process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_REWARD_ID;
  const qr = process.env.E2E_FIDELIZACION_TENANT_A_QR;
  const operator = await tokenFor(clientFor(url, key), process.env.E2E_FIDELIZACION_OPERATOR_A_EMAIL,
    process.env.E2E_FIDELIZACION_OPERATOR_A_PASSWORD);
  const otherOperator = await tokenFor(clientFor(url, key), process.env.E2E_FIDELIZACION_OPERATOR_B_EMAIL,
    process.env.E2E_FIDELIZACION_OPERATOR_B_PASSWORD);
  const customer = await tokenFor(clientFor(url, key), process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_EMAIL,
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_PASSWORD);
  const otherCustomer = await tokenFor(clientFor(url, key), process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_EMAIL,
    process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_PASSWORD);
  const invoke = (token, name, args) => rpc(url, key, token, name, args);
  const one = (result, label) => {
    assert.equal(result.response.status, 200, label);
    assert.equal(result.body?.length, 1, label);
    return result.body[0];
  };
  const balance = async (token, account) => {
    const result = await invoke(token, 'fidelizacion_obtener_saldo_cliente', { p_account_id: account });
    assert.equal(result.response.status, 200);
    return Number(result.body);
  };
  const movements = async (token, account) => {
    const result = await dataApi(url, key, token,
      `rest/v1/fidelizacion_point_movements?select=tipo,puntos,operation_id&account_id=eq.${encodeURIComponent(account)}`);
    assert.equal(result.response.status, 200);
    return result.body;
  };
  const unauthorizedEarnArgs = (accountId, key) => ({
    p_account_id: accountId, p_puntos: 10, p_idempotency_key: key,
  });
  for (const [token, accountId, idempotencyKey] of [
    [operator, process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_B_ACCOUNT_ID, 'b2-cross-a'],
    [otherOperator, process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID, 'b2-cross-b'],
    [customer, process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID, 'b2-customer'],
  ]) {
    assertForbidden(await invoke(token, 'fidelizacion_crear_earn',
      unauthorizedEarnArgs(accountId, idempotencyKey)), 'la creación de puntos no autorizada debe rechazarse');
  }
  const anonymousEarn = await rpc(url, key, null, 'fidelizacion_crear_earn',
    unauthorizedEarnArgs(process.env.E2E_FIDELIZACION_EXCLUSIVE_CUSTOMER_A_ACCOUNT_ID, 'b2-anon'));
  assert.equal(anonymousEarn.response.ok, false, 'anon no puede crear puntos');

  assert.equal(await balance(customer, accountA), 0);
  assert.equal(await balance(otherCustomer, accountB), 0);
  const earnArgs = { p_account_id: accountA, p_puntos: 10, p_idempotency_key: 'b2-earn-autorizado' };
  const earn = one(await invoke(operator, 'fidelizacion_crear_earn', earnArgs), 'crear acreditación');
  assert.equal(earn.estado, 'pending_customer');
  assert.equal(one(await invoke(operator, 'fidelizacion_crear_earn', earnArgs), 'reintentar creación').operation_id,
    earn.operation_id);
  const confirmEarn = { p_public_qr_code: qr, p_operation_id: earn.operation_id };
  assertForbidden(await invoke(operator, 'fidelizacion_confirmar_earn', confirmEarn),
    'la acreditación se confirma por el cliente');
  const earned = one(await invoke(customer, 'fidelizacion_confirmar_earn', confirmEarn), 'confirmar acreditación');
  assert.equal(earned.estado, 'confirmed');
  assert.equal(Number(earned.saldo), 10);
  assert.equal(one(await invoke(customer, 'fidelizacion_confirmar_earn', confirmEarn), 'reintentar confirmación').operation_id,
    earn.operation_id);
  assert.deepEqual(await movements(customer, accountA), [{ tipo: 'earn', puntos: 10, operation_id: earn.operation_id }]);
  console.log('B2 PASS acreditación: +10, saldo 10, un movimiento tras reintentos');

  const createRedeem = (idempotencyKey) => ({ p_reward_id: reward, p_idempotency_key: idempotencyKey });
  const pending = one(await invoke(customer, 'fidelizacion_crear_redeem', createRedeem('b2-reserva')), 'solicitar canje');
  assert.equal(pending.estado, 'pending_customer');
  assert.equal(one(await invoke(customer, 'fidelizacion_crear_redeem', createRedeem('b2-reserva')), 'reintentar canje').operation_id,
    pending.operation_id);
  const insufficient = await invoke(customer, 'fidelizacion_crear_redeem', createRedeem('b2-sin-disponible'));
  assert.equal(insufficient.body?.code, '23514', 'la reserva impide gastar el saldo dos veces');
  assert.equal(await balance(customer, accountA), 10, 'la reserva no modifica el saldo contable');
  assert.equal((await movements(customer, accountA)).length, 1);
  assert.equal(one(await invoke(customer, 'fidelizacion_cancelar_redeem', { p_operation_id: pending.operation_id }),
    'cancelar y liberar reserva').estado, 'cancelled');
  const redeem = one(await invoke(customer, 'fidelizacion_crear_redeem', createRedeem('b2-canje-final')), 'usar reserva liberada');
  assert.equal(redeem.estado, 'pending_customer');
  assert.equal(one(await invoke(customer, 'fidelizacion_escanear_redeem',
    { p_public_qr_code: qr, p_operation_id: redeem.operation_id }), 'escanear QR').estado, 'pending_staff');
  assert.equal(await balance(customer, accountA), 10, 'el escaneo todavía no descuenta puntos');
  assertForbidden(await invoke(otherOperator, 'fidelizacion_confirmar_redeem', { p_operation_id: redeem.operation_id }),
    'el operador del otro comercio no confirma el canje');
  const confirmed = one(await invoke(operator, 'fidelizacion_confirmar_redeem', { p_operation_id: redeem.operation_id }), 'confirmar canje');
  assert.equal(confirmed.estado, 'confirmed');
  assert.equal(Number(confirmed.saldo), 0);
  const retry = one(await invoke(operator, 'fidelizacion_confirmar_redeem', { p_operation_id: redeem.operation_id }), 'reintentar canje');
  assert.equal(retry.redemption_id, confirmed.redemption_id);
  const ledger = await movements(customer, accountA);
  assert.equal(ledger.length, 2);
  assert.deepEqual(ledger.find((row) => row.tipo === 'earn'), { tipo: 'earn', puntos: 10, operation_id: earn.operation_id });
  assert.deepEqual(ledger.find((row) => row.tipo === 'redeem'), { tipo: 'redeem', puntos: -10, operation_id: redeem.operation_id });
  assert.equal(await balance(customer, accountA), 0);
  assert.equal(await balance(otherCustomer, accountB), 0);
  assert.deepEqual(await movements(otherCustomer, accountB), []);
  console.log('B2 PASS reserva y liberación; canje -10, saldo 0, otro comercio sin movimientos');
});
