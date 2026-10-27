import { spawn } from 'node:child_process';

const child = spawn(process.execPath, ['--test', 'tests/fidelizacion-postgrest-e2e.test.js'], {
  stdio: 'inherit',
  env: { ...process.env, REQUIRE_FIDELIZACION_E2E: '1' },
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
