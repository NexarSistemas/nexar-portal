import test from 'node:test';
import assert from 'node:assert/strict';
import {
  cancelRedeem,
  confirmRedeem,
  createEarn,
  listPendingOperations,
  resolveStaffAccess,
  searchAccount,
  signInFidelizacion,
} from '../src/fidelizacion/api.js';
import {
  createActionLock,
  normalizeEmail,
  operationPresentation,
  panelStateText,
  parseStaffAccess,
  UnauthorizedStaffError,
} from '../src/fidelizacion/contracts.js';
import {
  createEarnAttemptStore,
  earnFlowNotice,
  runEarnCreation,
  runSuccessfulRefresh,
} from '../src/fidelizacion/earn-flow.js';

test('normaliza el email y acepta exclusivamente un staff activo de Fidelización', () => {
  assert.equal(normalizeEmail('  Operador@Ejemplo.COM '), 'operador@ejemplo.com');
  assert.deepEqual(parseStaffAccess([{
    rol: 'operador',
    tenant: { nombre: 'Comercio demo', activo: true },
  }]), { role: 'operador', tenantName: 'Comercio demo' });
});

test('rechaza usuario sin staff, rol inválido o membresía ambigua', () => {
  assert.throws(() => parseStaffAccess([]), UnauthorizedStaffError);
  assert.throws(() => parseStaffAccess([{ rol: 'vendedor', tenant: { nombre: 'A', activo: true } }]), UnauthorizedStaffError);
  assert.throws(() => parseStaffAccess([
    { rol: 'operador', tenant: { nombre: 'A', activo: true } },
    { rol: 'admin', tenant: { nombre: 'B', activo: true } },
  ]), UnauthorizedStaffError);
});

test('resuelve autorización únicamente desde fidelizacion_staff y el tenant activo', async () => {
  const calls = [];
  const result = { data: [{
    rol: 'admin', tenant: { nombre: 'Comercio demo', activo: true },
  }], error: null };
  const query = {
    select(value) { calls.push(['select', value]); return this; },
    eq(field, value) { calls.push(['eq', field, value]); return this; },
    in(field, value) { calls.push(['in', field, value]); return this; },
    limit(value) { calls.push(['limit', value]); return Promise.resolve(result); },
  };
  const client = { from(table) { calls.push(['from', table]); return query; } };
  assert.deepEqual(await resolveStaffAccess(client, 'auth-user-id'), {
    role: 'admin', tenantName: 'Comercio demo',
  });
  assert.equal(calls[0][1], 'fidelizacion_staff');
  assert.equal(calls.some((call) => String(call).includes('perfiles')), false);
  assert.equal(calls.some((call) => call[0] === 'eq' && call[1] === 'user_id' && call[2] === 'auth-user-id'), true);
});

test('el login usa Supabase Auth y oculta el error técnico', async () => {
  let credentials;
  const successClient = { auth: { signInWithPassword: async (value) => {
    credentials = value;
    return { data: { user: { id: 'staff-id' } }, error: null };
  } } };
  assert.deepEqual(await signInFidelizacion(successClient, ' Staff@Example.com ', 'secreto'), { id: 'staff-id' });
  assert.deepEqual(credentials, { email: 'staff@example.com', password: 'secreto' });

  const failureClient = { auth: { signInWithPassword: async () => ({
    data: {}, error: { message: 'detalle SQL privado' },
  }) } };
  await assert.rejects(() => signInFidelizacion(failureClient, 'a@b.com', 'x'), {
    message: 'No pudimos iniciar sesión. Verificá tus datos e intentá nuevamente.',
  });
});

test('la búsqueda usa el RPC exacto y muestra el saldo retornado por backend', async () => {
  let call;
  const client = { rpc: async (name, args) => {
    call = { name, args };
    return { data: [{ account_id: 'interno', cliente_email: 'cliente@example.com', saldo: 70 }], error: null };
  } };
  const result = await searchAccount(client, ' Cliente@Example.com ');
  assert.deepEqual(call, {
    name: 'fidelizacion_buscar_cuenta_staff',
    args: { p_email: 'cliente@example.com' },
  });
  assert.equal(result.saldo, 70);
  assert.equal(result.account_id, 'interno');
});

test('la búsqueda representa cliente inexistente sin inventar datos', async () => {
  const client = { rpc: async () => ({ data: [], error: null }) };
  assert.equal(await searchAccount(client, 'nadie@example.com'), null);
});

test('earn conserva el contrato e idempotency_key de Fase 2', async () => {
  let call;
  const client = { rpc: async (name, args) => {
    call = { name, args };
    return { data: [{ estado: 'pending_customer' }], error: null };
  } };
  const result = await createEarn(client, { accountId: 'account-id', points: 180, idempotencyKey: 'attempt-id' });
  assert.deepEqual(call, { name: 'fidelizacion_crear_earn', args: {
    p_account_id: 'account-id', p_puntos: 180, p_idempotency_key: 'attempt-id', p_expires_at: null,
  } });
  assert.equal(result.estado, 'pending_customer');
});

test('conserva la idempotency key si createEarn tuvo éxito pero falla el refresh', async () => {
  const keys = ['attempt-1', 'attempt-2'];
  const attempts = createEarnAttemptStore(() => keys.shift());
  const signature = 'account-id:180';
  const firstAttempt = attempts.get(signature);
  const calls = [];

  const firstResult = await runEarnCreation({
    create: async () => { calls.push(firstAttempt.key); },
    refresh: () => runSuccessfulRefresh({
      refresh: async () => { throw new Error('lectura temporalmente no disponible'); },
      onSuccess: () => attempts.clear(),
    }),
  });

  assert.deepEqual(firstResult, {
    created: true,
    refreshed: false,
    error: new Error('lectura temporalmente no disponible'),
  });
  assert.equal(attempts.get(signature).key, 'attempt-1');

  const retryAttempt = attempts.get(signature);
  const retryResult = await runEarnCreation({
    create: async () => { calls.push(retryAttempt.key); },
    refresh: () => runSuccessfulRefresh({
      refresh: async () => {},
      onSuccess: () => attempts.clear(),
    }),
  });
  assert.deepEqual(retryResult, { created: true, refreshed: true });
  assert.deepEqual(calls, ['attempt-1', 'attempt-1']);
  assert.match(earnFlowNotice(firstResult).message, /fue creada, pero no se pudo actualizar la vista/i);
  assert.equal(attempts.get(signature).key, 'attempt-2');
});

test('un refresco exitoso posterior invalida el intento earn ambiguo', async () => {
  const keys = ['attempt-1', 'attempt-2'];
  const attempts = createEarnAttemptStore(() => keys.shift());
  const signature = 'account-id:180';
  const firstAttempt = attempts.get(signature);
  const calls = [];

  const firstResult = await runEarnCreation({
    create: async () => { calls.push(firstAttempt.key); },
    refresh: () => runSuccessfulRefresh({
      refresh: async () => { throw new Error('lectura temporalmente no disponible'); },
      onSuccess: () => attempts.clear(),
    }),
  });
  assert.equal(firstResult.created, true);
  assert.equal(firstResult.refreshed, false);
  assert.equal(attempts.get(signature).key, 'attempt-1');

  await runSuccessfulRefresh({
    refresh: async () => {},
    onSuccess: () => attempts.clear(),
  });
  const nextAttempt = attempts.get(signature);
  assert.equal(nextAttempt.key, 'attempt-2');

  await runEarnCreation({
    create: async () => { calls.push(nextAttempt.key); },
    refresh: async () => {},
  });
  assert.deepEqual(calls, ['attempt-1', 'attempt-2']);
});

test('distingue una creación fallida de una creación exitosa con refresh fallido', async () => {
  const creationFailure = await runEarnCreation({
    create: async () => { throw new Error('no creada'); },
    refresh: async () => { throw new Error('no debe ejecutarse'); },
  });
  assert.equal(creationFailure.created, false);
  assert.deepEqual(earnFlowNotice(creationFailure), { type: 'error', message: 'no creada' });

  const refreshFailure = await runEarnCreation({
    create: async () => {},
    refresh: async () => { throw new Error('vista no actualizada'); },
  });
  assert.equal(refreshFailure.created, true);
  assert.equal(refreshFailure.refreshed, false);
  assert.equal(earnFlowNotice(refreshFailure).type, 'success');
});

test('las operaciones pendientes se limitan a la cuenta resuelta y a estados permitidos', async () => {
  const calls = [];
  const query = {
    select(value) { calls.push(['select', value]); return this; },
    eq(field, value) { calls.push(['eq', field, value]); return this; },
    in(field, value) { calls.push(['in', field, value]); return this; },
    order(field, options) { calls.push(['order', field, options]); return Promise.resolve({ data: [], error: null }); },
  };
  const client = { from(table) { calls.push(['from', table]); return query; } };
  assert.deepEqual(await listPendingOperations(client, 'account-id'), []);
  assert.equal(calls.some((call) => call[0] === 'eq' && call[1] === 'account_id' && call[2] === 'account-id'), true);
  assert.equal(calls.some((call) => call[0] === 'in' && call[1] === 'estado'
    && call[2].join(',') === 'pending_customer,pending_staff'), true);
});

test('confirmación y cancelación usan exclusivamente los RPC de Fase 3', async () => {
  const calls = [];
  const client = { rpc: async (name, args) => {
    calls.push({ name, args });
    return { data: [{ estado: name.includes('confirmar') ? 'confirmed' : 'cancelled' }], error: null };
  } };
  assert.equal((await confirmRedeem(client, 'operation-id')).estado, 'confirmed');
  assert.equal((await cancelRedeem(client, 'operation-id')).estado, 'cancelled');
  assert.deepEqual(calls, [
    { name: 'fidelizacion_confirmar_redeem', args: { p_operation_id: 'operation-id' } },
    { name: 'fidelizacion_cancelar_redeem', args: { p_operation_id: 'operation-id' } },
  ]);
});

test('solo un redeem pending_staff vigente habilita confirmar y cancelar', () => {
  const pending = operationPresentation({ tipo: 'redeem', estado: 'pending_staff', expires_at: null });
  assert.deepEqual(pending.actions, ['confirm', 'cancel']);
  assert.deepEqual(operationPresentation({ tipo: 'redeem', estado: 'pending_customer', expires_at: null }).actions, []);
  assert.deepEqual(operationPresentation({
    tipo: 'redeem', estado: 'pending_staff', expires_at: '2020-01-01T00:00:00Z',
  }, new Date('2021-01-01T00:00:00Z')).actions, []);
});

test('expone estados seguros de loading, vacío y error', () => {
  assert.equal(panelStateText('loading'), 'Cargando información…');
  assert.match(panelStateText('empty'), /no hay operaciones pendientes/i);
  assert.doesNotMatch(panelStateText('error'), /sql|postgres|uuid/i);
});

test('el lock ignora un doble submit mientras la primera acción sigue en curso', async () => {
  const lock = createActionLock();
  let release;
  const first = lock.run(() => new Promise((resolve) => { release = resolve; }));
  const second = await lock.run(async () => 'duplicada');
  assert.deepEqual(second, { ignored: true });
  release('completada');
  assert.equal(await first, 'completada');
  assert.equal(await lock.run(async () => 'nuevo intento'), 'nuevo intento');
});

test('los errores de mutación no filtran mensajes del backend', async () => {
  const client = { rpc: async () => ({ data: null, error: { message: 'relation auth.users denied' } }) };
  await assert.rejects(() => confirmRedeem(client, 'operation-id'), {
    message: 'No pudimos completar la acción. Intentá nuevamente.',
  });
});
