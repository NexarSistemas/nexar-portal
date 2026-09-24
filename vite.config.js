import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    rollupOptions: {
      input: {
        portal: new URL('./index.html', import.meta.url).pathname,
        fidelizacionLogin: new URL('./fidelizacion/login/index.html', import.meta.url).pathname,
        fidelizacionOperador: new URL('./fidelizacion/operador/index.html', import.meta.url).pathname,
        fidelizacionCliente: new URL('./fidelizacion/cliente/index.html', import.meta.url).pathname,
        fidelizacionClienteLogin: new URL('./fidelizacion/cliente/login/index.html', import.meta.url).pathname,
      },
    },
  },
});
