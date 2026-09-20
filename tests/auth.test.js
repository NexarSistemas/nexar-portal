import test from 'node:test';
import assert from 'node:assert/strict';
import { isValidProfile, viewForRole } from '../src/auth/auth.js';

test('acepta un perfil admin activo sin vendedor vinculado', () => {
  assert.equal(isValidProfile({ rol: 'admin', activo: true, vendedor_id: null }), true);
});

test('acepta un perfil vendedor activo con vendedor vinculado', () => {
  assert.equal(isValidProfile({ rol: 'vendedor', activo: true, vendedor_id: 'uuid' }), true);
});

test('rechaza perfil ausente, inactivo o con rol inválido', () => {
  assert.equal(isValidProfile(null), false);
  assert.equal(isValidProfile({ rol: 'admin', activo: false }), false);
  assert.equal(isValidProfile({ rol: 'owner', activo: true }), false);
});

test('rechaza vendedor sin vendedor_id', () => {
  assert.equal(isValidProfile({ rol: 'vendedor', activo: true, vendedor_id: null }), false);
});

test('resuelve solo las vistas previstas para roles válidos', () => {
  assert.equal(viewForRole('admin'), 'admin');
  assert.equal(viewForRole('vendedor'), 'vendedor');
  assert.equal(viewForRole('owner'), null);
});
