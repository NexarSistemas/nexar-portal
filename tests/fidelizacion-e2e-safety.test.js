import test from 'node:test';
import assert from 'node:assert/strict';
import { guardedFetch, localUrl, validateConfiguration, validatePublicKey } from '../scripts/fidelizacion-e2e-safety.js';

test('solo acepta origen local explícito y puerto autorizado', () => {
  assert.doesNotThrow(() => localUrl('http://127.0.0.1:54331', true));
  for (const value of ['http://localhost:54331', 'http://[::1]:54331', 'http://127.0.0.1:54321', 'https://127.0.0.1:54331', 'http://localhost:54322',
    'http://example.com:54331', 'http://127.0.0.2:54331', 'http://127.1:54331', 'http://2130706433:54331',
    'http://localhost.example.com:54331', 'http://user@127.0.0.1:54331',
    'http://127.0.0.1:54331/path', 'http://127.0.0.1:54331/?x=1', 'invalid']) {
    assert.throws(() => localUrl(value, true));
  }
});

test('rechaza configuración incompleta sin exponer valores', () => {
  assert.throws(() => validateConfiguration({ E2E_FIDELIZACION_URL: 'http://127.0.0.1:54331' },
    ['E2E_FIDELIZACION_URL', 'E2E_FIDELIZACION_ANON_KEY']), /Falta configuración/);
});

test('valida cada destino y rechaza redirecciones sin seguirlas', async () => {
  let calls = 0;
  const safeFetch = guardedFetch('http://127.0.0.1:54331', async (url, options) => {
    calls++;
    assert.equal(new URL(url).hostname, '127.0.0.1');
    assert.equal(options.redirect, 'manual');
    return { status: 302 };
  });
  await assert.rejects(safeFetch('http://example.com:54331/auth/v1/token'));
  assert.equal(calls, 0);
  await assert.rejects(safeFetch('http://127.0.0.1:54331/auth/v1/token'), /Redirección/);
  assert.equal(calls, 1);
  await assert.rejects(safeFetch('http://[::1]:54331/rest/v1/rpc/x'));
  assert.equal(calls, 1);
});

test('acepta solo formatos públicos y claims anon sin verificar firmas', () => {
  const segment = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const jwt = (role, alg = 'HS256') => `${segment({ alg, typ: 'JWT' })}.${segment({ role })}.c2ln`;
  const publicKey = 'sb_publishable_0123456789abcdef';
  assert.doesNotThrow(() => validatePublicKey(publicKey));
  assert.doesNotThrow(() => validatePublicKey(jwt('anon')));
  for (const key of ['', 'sb_secret_0123456789abcdef', 'sb_publishable_', 'unknown',
    jwt('service_role'), jwt('authenticated'), jwt('anon', 'none'), `${jwt('anon')}!`]) {
    assert.throws(() => validatePublicKey(key));
  }
  assert.throws(() => validatePublicKey(publicKey, [publicKey]));
  assert.throws(() => validateConfiguration({ E2E_FIDELIZACION_URL: 'http://127.0.0.1:54331',
    E2E_FIDELIZACION_ANON_KEY: publicKey, SUPABASE_SERVICE_ROLE_KEY: publicKey },
  ['E2E_FIDELIZACION_URL', 'E2E_FIDELIZACION_ANON_KEY']));
});
