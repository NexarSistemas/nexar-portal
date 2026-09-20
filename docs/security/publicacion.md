# Publicación segura

Esta checklist se aplica antes de hacer público el repositorio o habilitar GitHub Pages.

## Repositorio

- Verificar que no existan archivos `.env`, dumps, backups, logs, certificados, claves privadas o credenciales.
- Confirmar que `.env.example` contenga únicamente placeholders.
- Buscar referencias a `service_role`, secret keys, passwords, tokens privados, JWT reales y credenciales de proveedores.
- No versionar UUID, emails, teléfonos u otros datos personales reales cuando no sean necesarios para reproducir el sistema.
- Mantener los identificadores operativos reales fuera de la documentación pública siempre que no formen parte indispensable de una migración histórica ya aplicada.
- Revisar también el historial Git: borrar un secreto del árbol actual no lo elimina de commits previos.

## Frontend

El frontend de GitHub Pages se ejecuta en el navegador. Todo valor incluido mediante variables `VITE_*` termina siendo visible en el bundle final.

Solo se permiten allí valores públicos, por ejemplo:

- URL pública del proyecto Supabase.
- clave pública `anon` o publishable equivalente.

Nunca deben incluirse:

- `service_role`;
- secret keys;
- passwords;
- tokens privados;
- credenciales de backend;
- claves de proveedores que otorguen privilegios.

La autorización real depende de Supabase Auth, RLS y ownership. El frontend nunca es frontera de seguridad.

## GitHub Pages

El despliegue usa GitHub Actions y genera `dist/` con Vite.

Las variables públicas de build se cargan desde GitHub Actions Variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

No usar GitHub Secrets para valores que necesariamente serán públicos en el navegador.

Para dominio personalizado:

- dominio previsto: `portal.nexarsistemas.com.ar`;
- configurar el custom domain en GitHub Pages;
- crear un CNAME DNS `portal` hacia `nexarsistemas.github.io`;
- habilitar HTTPS cuando GitHub emita el certificado.

## Antes de pasar a público

1. Revisar el árbol actual.
2. Revisar el historial relevante.
3. Confirmar que no existan secretos reales.
4. Confirmar que las variables de Pages sean públicas por diseño.
5. Ejecutar tests y build.
6. Revisar la PR de saneamiento.
7. Recién entonces cambiar la visibilidad del repositorio.
