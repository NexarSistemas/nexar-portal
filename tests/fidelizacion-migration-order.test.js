import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import test from 'node:test';

const migrationsUrl = new URL('../supabase/migrations/', import.meta.url);
const phase6Expiry = [
  '20260914000699_fidelizacion_fase6_caducidad_operaciones.sql',
  '20260914000700_fidelizacion_fase6_corrige_coalesce_caducidad.sql',
];
const m07 = '20260914000701_m07_hardening_retiro_auth_legacy.sql';
const driftReconciliation = '20260924225227_fidelizacion_corrige_coalesce_crear_earn.sql';

test('el bootstrap corrige crear earn antes del gate M07', async () => {
  const files = (await readdir(migrationsUrl)).sort();
  const m07Index = files.indexOf(m07);

  assert.ok(m07Index >= 0, 'M07 debe permanecer en la cadena de migraciones');
  assert.ok(files.indexOf(driftReconciliation) > m07Index,
    'la reconciliación forward-only debe conservarse para bases existentes con drift');

  for (const migration of phase6Expiry) {
    assert.ok(files.indexOf(migration) >= 0 && files.indexOf(migration) < m07Index,
      `${migration} debe ejecutarse antes de M07 en una base limpia`);
    const source = await readFile(new URL(migration, migrationsUrl), 'utf8');
    assert.doesNotMatch(source, /pg_catalog\.coalesce\(/,
      `${migration} no puede reintroducir la llamada que produce 42883`);
    assert.match(source, /v_expires_at timestamptz := coalesce\(/,
      `${migration} debe asignar la expiración con COALESCE como sintaxis SQL`);
  }
});
