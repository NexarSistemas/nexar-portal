import test from 'node:test';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';

const required = [
  'E2E_FIDELIZACION_URL',
  'E2E_FIDELIZACION_ANON_KEY',
  'E2E_FIDELIZACION_OPERATOR_EMAIL',
  'E2E_FIDELIZACION_OPERATOR_PASSWORD',
  'E2E_FIDELIZACION_LOOKUP_EMAIL',
  'E2E_FIDELIZACION_CUSTOMER_EMAIL',
  'E2E_FIDELIZACION_CUSTOMER_PASSWORD',
  'E2E_FIDELIZACION_CUSTOMER_ACCOUNT_ID',
  'E2E_FIDELIZACION_OTHER_CUSTOMER_EMAIL',
  'E2E_FIDELIZACION_OTHER_CUSTOMER_PASSWORD',
];
const missing = required.filter((name) => !process.env[name]);

function clientFor(url, anonKey) {
  return createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

async function tokenFor(client, email, password) {
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  assert.equal(error, null, 'la sesión E2E debe poder autenticarse');
  assert.ok(data.session?.access_token, 'la sesión E2E debe devolver un access token');
  return data.session.access_token;
}

async function dataApi(url, anonKey, token, path, options = {}) {
  const response = await fetch(new URL(path, url), {
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

test('PostgREST ejecuta los RPC de operador y cliente con aislamiento', {
  skip: missing.length && !process.env.REQUIRE_FIDELIZACION_E2E
    ? `requiere variables E2E autorizadas: ${missing.join(', ')}`
    : false,
}, async () => {
  assert.equal(missing.length, 0, `requiere variables E2E autorizadas: ${missing.join(', ')}`);
  const url = process.env.E2E_FIDELIZACION_URL;
  const anonKey = process.env.E2E_FIDELIZACION_ANON_KEY;
  const operatorToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_OPERATOR_EMAIL,
    process.env.E2E_FIDELIZACION_OPERATOR_PASSWORD,
  );
  const customerToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_CUSTOMER_EMAIL,
    process.env.E2E_FIDELIZACION_CUSTOMER_PASSWORD,
  );
  const otherCustomerToken = await tokenFor(
    clientFor(url, anonKey),
    process.env.E2E_FIDELIZACION_OTHER_CUSTOMER_EMAIL,
    process.env.E2E_FIDELIZACION_OTHER_CUSTOMER_PASSWORD,
  );

  const operatorSearch = await dataApi(url, anonKey, operatorToken,
    'rest/v1/rpc/fidelizacion_buscar_cuenta_staff', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_email: process.env.E2E_FIDELIZACION_LOOKUP_EMAIL }),
    });
  assert.equal(operatorSearch.response.status, 200, 'el operador debe poder buscar su cliente');
  assert.ok(Array.isArray(operatorSearch.body) && operatorSearch.body.length === 1,
    'la búsqueda del operador debe devolver una cuenta de su tenant');

  const customerBalance = await dataApi(url, anonKey, customerToken,
    'rest/v1/rpc/fidelizacion_obtener_saldo_cliente', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_account_id: process.env.E2E_FIDELIZACION_CUSTOMER_ACCOUNT_ID }),
    });
  assert.equal(customerBalance.response.status, 200, 'el cliente debe poder consultar su saldo');
  assert.ok(Number.isFinite(Number(customerBalance.body)), 'el saldo debe ser numérico');

  const rewards = await dataApi(url, anonKey, customerToken,
    'rest/v1/fidelizacion_rewards?select=id&activa=eq.true');
  assert.equal(rewards.response.status, 200, 'el cliente debe poder cargar las recompensas de su programa');

  const otherCustomerBalance = await dataApi(url, anonKey, otherCustomerToken,
    'rest/v1/rpc/fidelizacion_obtener_saldo_cliente', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_account_id: process.env.E2E_FIDELIZACION_CUSTOMER_ACCOUNT_ID }),
    });
  assert.equal(otherCustomerBalance.response.status, 403,
    'otro cliente no puede consultar una cuenta ajena');
  assert.equal(otherCustomerBalance.body?.code, '42501');

  for (const [rpc, body] of [
    ['fidelizacion_buscar_cuenta_staff', { p_email: process.env.E2E_FIDELIZACION_LOOKUP_EMAIL }],
    ['fidelizacion_obtener_saldo_cliente', { p_account_id: process.env.E2E_FIDELIZACION_CUSTOMER_ACCOUNT_ID }],
  ]) {
    const anonymous = await dataApi(url, anonKey, null, `rest/v1/rpc/${rpc}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    assert.equal(anonymous.response.ok, false, `anon no puede ejecutar ${rpc}`);
  }
});
