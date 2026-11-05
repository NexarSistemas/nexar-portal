import test from 'node:test';
import assert from 'node:assert/strict';
import { listCheckIns } from '../src/fidelizacion/api.js';
import { loadCheckIns } from '../src/fidelizacion/check-in.js';

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
