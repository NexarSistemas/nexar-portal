import test from 'node:test';
import assert from 'node:assert/strict';
import { signUpFidelizacion } from '../src/fidelizacion/api.js';
import {
  confirmClientEarn,
  createClientRedeem,
  getClientBalance,
  getPendingEarns,
  loadClientAccess,
  listClientAccounts,
  listClientMovements,
  registerClientAccount,
  scanClientRedeem,
} from '../src/fidelizacion/client-api.js';
import {
  activeQrCode,
  calculateBalance,
  clientOperationText,
  createAttemptStore,
  createQrContext,
  normalizeClientAccounts,
  normalizeQrCode,
  normalizeRpcRow,
  pendingRedeems,
  qrCodeFromLocation,
  reconcileQrState,
  urlWithoutQr,
} from '../src/fidelizacion/client-contracts.js';

const QR_CODE = 'AbCdEfGhIjKlMnOpQrStUvWxYz012345';

test('normaliza el QR desde query o ruta pública y rechaza payloads inválidos', () => {
  assert.equal(normalizeQrCode(` ${QR_CODE} `), QR_CODE);
  assert.equal(normalizeQrCode('qr-invalido'), null);
  assert.equal(qrCodeFromLocation({ href: `https://demo.test/fidelizacion/cliente/?qr=${QR_CODE}` }), QR_CODE);
  assert.equal(qrCodeFromLocation({ href: `https://demo.test/nexar-portal/q/${QR_CODE}` }), QR_CODE);
  assert.equal(qrCodeFromLocation({ href: 'https://demo.test/q/no-valido' }), null);
  assert.equal(
    urlWithoutQr(`https://demo.test/fidelizacion/cliente/?qr=${QR_CODE}&code=${QR_CODE}`).href,
    'https://demo.test/fidelizacion/cliente/',
  );
});

test('normaliza respuestas RPC y cuentas sin exponer contratos inconsistentes', () => {
  assert.deepEqual(normalizeRpcRow([{ operation_id: 'op-1' }]), { operation_id: 'op-1' });
  assert.deepEqual(normalizeRpcRow({ operation_id: 'op-2' }), { operation_id: 'op-2' });
  assert.equal(normalizeRpcRow([]), null);
  assert.deepEqual(normalizeClientAccounts([{
    id: 'account-id',
    tenant_id: 'tenant-id',
    tenant: [{ nombre: 'Comercio demo', activo: true }],
  }, {
    id: 'inactiva',
    tenant_id: 'tenant-2',
    tenant: { nombre: 'Otro comercio', activo: false },
  }]), [{ id: 'account-id', tenantId: 'tenant-id', tenantName: 'Comercio demo' }]);
});

test('deriva el saldo exclusivamente desde movimientos confirmados', () => {
  assert.equal(calculateBalance([{ puntos: 180 }, { puntos: '-60' }, { puntos: 'inválido' }]), 120);
  assert.equal(calculateBalance([]), 0);
});

test('calcula el saldo completo aunque el historial visible supere 50 movimientos', async () => {
  const movements = Array.from({ length: 120 }, (_, index) => ({ id: index + 1, puntos: 1 }));
  const ranges = [];
  const query = {
    select() { return this; },
    eq() { return this; },
    order() { return this; },
    range(from, to) {
      ranges.push([from, to]);
      return Promise.resolve({ data: movements.slice(from, to + 1), error: null });
    },
  };
  const client = { from: () => query };
  assert.equal(await getClientBalance(client, 'account-id'), 120);
  assert.deepEqual(ranges, [[0, 99], [100, 199]]);
});

test('el QR sólo queda activo para la cuenta del mismo tenant', () => {
  const qrContext = createQrContext(QR_CODE, 'tenant-a');
  assert.equal(activeQrCode(qrContext, { tenantId: 'tenant-a' }), QR_CODE);
  assert.equal(activeQrCode(qrContext, { tenantId: 'tenant-b' }), null);
  assert.deepEqual(
    reconcileQrState(qrContext, { tenantId: 'tenant-b' }, [{ operation_id: 'earn-a' }]),
    { qrContext: null, pendingEarns: [] },
  );
});

test('filtra canjes pendientes vigentes y presenta su próximo paso', () => {
  const now = new Date('2026-09-23T12:00:00Z');
  const operations = [
    { tipo: 'redeem', estado: 'pending_customer', expires_at: null },
    { tipo: 'redeem', estado: 'pending_staff', expires_at: '2026-09-24T12:00:00Z' },
    { tipo: 'redeem', estado: 'pending_customer', expires_at: '2026-09-22T12:00:00Z' },
    { tipo: 'earn', estado: 'pending_customer', expires_at: null },
  ];
  assert.equal(pendingRedeems(operations, now).length, 2);
  assert.match(clientOperationText(operations[0]), /QR del comercio/i);
  assert.match(clientOperationText(operations[1]), /confirmar el canje/i);
});

test('el registro Auth contempla confirmación de email sin inventar sesión', async () => {
  let credentials;
  const client = { auth: { signUp: async (value) => {
    credentials = value;
    return { data: { user: { id: 'user-id' }, session: null }, error: null };
  } } };
  const result = await signUpFidelizacion(
    client,
    ' Cliente@Example.com ',
    'secreto-seguro',
    'https://demo.test/fidelizacion/cliente/login/?qr=code',
  );
  assert.deepEqual(credentials, {
    email: 'cliente@example.com',
    password: 'secreto-seguro',
    options: { emailRedirectTo: 'https://demo.test/fidelizacion/cliente/login/?qr=code' },
  });
  assert.equal(result.confirmationRequired, true);
  assert.equal(result.session, null);
});

test('el registro Auth oculta errores técnicos', async () => {
  const client = { auth: { signUp: async () => ({
    data: null,
    error: { message: 'detalle privado de auth.users' },
  }) } };
  await assert.rejects(
    () => signUpFidelizacion(client, 'cliente@example.com', 'secreto'),
    { message: 'No pudimos crear la cuenta. Revisá tus datos e intentá nuevamente.' },
  );
});

test('la asociación inicial usa únicamente el RPC seguro y el QR público', async () => {
  let call;
  const client = { rpc: async (name, args) => {
    call = { name, args };
    return { data: [{ account_id: 'account-id', tenant_id: 'tenant-id' }], error: null };
  } };
  assert.deepEqual(await registerClientAccount(client, QR_CODE), {
    account_id: 'account-id', tenant_id: 'tenant-id',
  });
  assert.deepEqual(call, {
    name: 'fidelizacion_registrar_cuenta_cliente',
    args: { p_public_qr_code: QR_CODE },
  });
});

test('las cuentas cliente se leen por Auth/RLS sin consultar perfiles', async () => {
  const calls = [];
  const query = {
    select(value) { calls.push(['select', value]); return this; },
    eq(field, value) { calls.push(['eq', field, value]); return this; },
    order(field, options) {
      calls.push(['order', field, options]);
      return Promise.resolve({ data: [{
        id: 'account-id', tenant_id: 'tenant-id', tenant: { nombre: 'Demo', activo: true },
      }], error: null });
    },
  };
  const client = { from(table) { calls.push(['from', table]); return query; } };
  assert.equal((await listClientAccounts(client, 'auth-user-id'))[0].tenantName, 'Demo');
  assert.equal(calls[0][1], 'fidelizacion_accounts');
  assert.equal(calls.some((call) => String(call).includes('perfiles')), false);
  assert.equal(calls.some((call) => call[0] === 'eq' && call[1] === 'user_id' && call[2] === 'auth-user-id'), true);
});

test('un QR rechazado no impide cargar las cuentas existentes del usuario autenticado', async () => {
  const query = {
    select() { return this; },
    eq() { return this; },
    order() {
      return Promise.resolve({ data: [{
        id: 'account-id', tenant_id: 'tenant-b', tenant: { nombre: 'Programa B', activo: true },
      }], error: null });
    },
  };
  const client = {
    rpc: async () => ({ data: null, error: { message: 'QR inactivo' } }),
    from: () => query,
  };
  const access = await loadClientAccess(client, { userId: 'user-id', qrCode: QR_CODE });
  assert.equal(access.qrContext, null);
  assert.equal(access.associationError.message, 'No pudimos vincular tu cuenta con este comercio.');
  assert.deepEqual(access.accounts, [{
    id: 'account-id', tenantId: 'tenant-b', tenantName: 'Programa B',
  }]);
});

test('el historial se limita a movimientos propios y conserva el orden reciente', async () => {
  const calls = [];
  const query = {
    select(value) { calls.push(['select', value]); return this; },
    eq(field, value) { calls.push(['eq', field, value]); return this; },
    order(field, options) { calls.push(['order', field, options]); return this; },
    limit(value) {
      calls.push(['limit', value]);
      return Promise.resolve({ data: [{ tipo: 'earn', puntos: 180 }], error: null });
    },
  };
  const client = { from(table) { calls.push(['from', table]); return query; } };
  assert.deepEqual(await listClientMovements(client, 'account-id'), [{ tipo: 'earn', puntos: 180 }]);
  assert.equal(calls[0][1], 'fidelizacion_point_movements');
  assert.equal(calls.some((call) => call[0] === 'eq' && call[1] === 'account_id' && call[2] === 'account-id'), true);
  assert.equal(calls.some((call) => call[0] === 'order' && call[1] === 'fecha' && call[2].ascending === false), true);
  assert.equal(calls.some((call) => call[0] === 'limit' && call[1] === 50), true);
});

test('consulta y confirma earn mediante los RPC existentes sin crear movimientos directos', async () => {
  const calls = [];
  const client = { rpc: async (name, args) => {
    calls.push({ name, args });
    if (name.includes('obtener')) return { data: [], error: null };
    return { data: [{ operation_id: 'operation-id', estado: 'confirmed', saldo: 180 }], error: null };
  } };
  assert.deepEqual(await getPendingEarns(client, QR_CODE), []);
  assert.equal((await confirmClientEarn(client, {
    qrCode: QR_CODE, operationId: 'operation-id',
  })).saldo, 180);
  assert.deepEqual(calls, [
    { name: 'fidelizacion_obtener_earn_pendientes', args: { p_public_qr_code: QR_CODE } },
    { name: 'fidelizacion_confirmar_earn', args: {
      p_public_qr_code: QR_CODE, p_operation_id: 'operation-id',
    } },
  ]);
});

test('crea y continúa redeem con idempotencia y QR, sin confirmar como staff', async () => {
  const calls = [];
  const client = { rpc: async (name, args) => {
    calls.push({ name, args });
    return { data: [{ operation_id: 'operation-id', estado: name.includes('escanear') ? 'pending_staff' : 'pending_customer' }], error: null };
  } };
  assert.equal((await createClientRedeem(client, {
    rewardId: 'reward-id', idempotencyKey: 'attempt-id',
  })).estado, 'pending_customer');
  assert.equal((await scanClientRedeem(client, {
    qrCode: QR_CODE, operationId: 'operation-id',
  })).estado, 'pending_staff');
  assert.deepEqual(calls, [
    { name: 'fidelizacion_crear_redeem', args: {
      p_reward_id: 'reward-id', p_idempotency_key: 'attempt-id', p_expires_at: null,
    } },
    { name: 'fidelizacion_escanear_redeem', args: {
      p_public_qr_code: QR_CODE, p_operation_id: 'operation-id',
    } },
  ]);
  assert.equal(calls.some((call) => call.name === 'fidelizacion_confirmar_redeem'), false);
});

test('conserva la clave de intento hasta que el refresh posterior resulta exitoso', () => {
  const keys = ['attempt-1', 'attempt-2'];
  const attempts = createAttemptStore(() => keys.shift());
  assert.equal(attempts.get('account:reward'), 'attempt-1');
  assert.equal(attempts.get('account:reward'), 'attempt-1');
  attempts.clear('account:reward');
  assert.equal(attempts.get('account:reward'), 'attempt-2');
});

test('los errores RPC cliente no filtran detalles internos', async () => {
  const client = { rpc: async () => ({
    data: null,
    error: { message: 'relation auth.users denied for tenant uuid' },
  }) };
  await assert.rejects(() => registerClientAccount(client, QR_CODE), {
    message: 'No pudimos vincular tu cuenta con este comercio.',
  });
  await assert.rejects(() => createClientRedeem(client, {
    rewardId: 'reward-id', idempotencyKey: 'attempt-id',
  }), {
    message: 'No pudimos completar la acción. Intentá nuevamente.',
  });
});
