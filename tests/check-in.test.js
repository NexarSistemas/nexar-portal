import test from 'node:test';
import assert from 'node:assert/strict';
import { listCheckIns } from '../src/fidelizacion/api.js';
import { loadCheckIns, startCheckInPolling } from '../src/fidelizacion/check-in.js';

test('consulta RPC y resuelve cuentas vigentes sin email obligatorio', async () => {
  const calls = [];
  const client = { rpc: async name => { calls.push(name); return { data: [
    { account_id: 'a', expires_at: '2030-01-01T00:00:00Z' },
    { account_id: 'a', expires_at: '2030-01-01T00:00:00Z' },
    { account_id: 'b', expires_at: '2020-01-01T00:00:00Z' },
  ], error: null }; } };
  const ids = [];
  const accounts = async (_client, _search, _offset, _limit, id) => { ids.push(id); return [{ account_id: id, cliente_email: null }]; };
  const result = await loadCheckIns(client, listCheckIns, accounts, Date.parse('2029-01-01T00:00:00Z'));
  assert.deepEqual(calls, ['fidelizacion_listar_check_in_staff']);
  assert.deepEqual(ids, ['a']);
  assert.equal(result[0].cliente_email, null);
  await assert.rejects(() => listCheckIns({ rpc: async () => ({ error: { message: 'privado' } }) }), /No pudimos cargar/);
});

test('restaura el polling al volver desde BFCache sin duplicar intervalos', () => {
  const listeners = new Map();
  const timers = new Map();
  let nextId = 0;
  let refreshes = 0;
  const win = {
    addEventListener(name, listener) { listeners.set(name, listener); },
    setInterval(callback, delay) { assert.equal(delay, 30000); timers.set(++nextId, callback); return nextId; },
    clearInterval(id) { timers.delete(id); },
  };
  const doc = { hidden: false, addEventListener(name, listener) { listeners.set(name, listener); } };
  startCheckInPolling(win, doc, () => { refreshes++; });
  assert.equal(refreshes, 1);
  assert.equal(timers.size, 1);
  listeners.get('pagehide')();
  assert.equal(timers.size, 0);
  listeners.get('pageshow')({ persisted: true });
  listeners.get('pageshow')({ persisted: true });
  assert.equal(timers.size, 1);
  assert.equal(refreshes, 2);
  doc.hidden = true;
  [...timers.values()][0]();
  listeners.get('visibilitychange')();
  assert.equal(refreshes, 2);
  doc.hidden = false;
  listeners.get('visibilitychange')();
  assert.equal(refreshes, 3);
  listeners.get('pagehide')();
  listeners.get('pageshow')({ persisted: true });
  assert.equal(timers.size, 1);
  assert.equal(refreshes, 4);
  assert.equal(listeners.size, 3);
});
