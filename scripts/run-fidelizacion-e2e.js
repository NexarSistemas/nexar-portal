import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

async function localEnvironment() {
  try {
    const source = await readFile(resolve('.env.e2e.local'), 'utf8');
    return Object.fromEntries(source.split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith('#'))
      .map((line) => {
        const separator = line.indexOf('=');
        return separator < 0
          ? null
          : [line.slice(0, separator).trim(), line.slice(separator + 1)];
      })
      .filter(Boolean));
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    throw error;
  }
}

const localEnv = await localEnvironment();
const child = spawn(process.execPath, ['--test', 'tests/fidelizacion-postgrest-e2e.test.js'], {
  stdio: 'inherit',
  env: { ...localEnv, ...process.env, REQUIRE_FIDELIZACION_E2E: '1' },
});

child.once('error', (error) => {
  console.error(`No se pudo iniciar la prueba E2E de Fidelización: ${error.message}`);
  process.exitCode = 1;
});

child.once('exit', (code, signal) => {
  if (signal) {
    console.error(`La prueba E2E de Fidelización terminó por la señal ${signal}.`);
    process.exitCode = 1;
    return;
  }
  process.exitCode = code ?? 1;
});
