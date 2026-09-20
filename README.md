# Nexar Portal

Frontend base estático para Nexar Portal, construido con Vite, JavaScript ES Modules y CSS propio.

La base SQL versionada se documenta en [supabase/](supabase/README.md).

## Desarrollo

Requiere Node.js y npm. Instalá dependencias y ejecutá Vite:

```sh
npm ci
npm run dev
```

Para generar y previsualizar la versión de producción:

```sh
npm run build
npm run preview
```

## Configuración

Copiá `.env.example` a `.env` y completá únicamente variables públicas del proyecto Supabase:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY` (o la clave pública publishable equivalente)

Todo valor expuesto mediante `VITE_*` queda incorporado al bundle del navegador y debe considerarse público. Nunca usar `service_role`, secret keys, passwords, tokens privados ni credenciales de backend en GitHub Pages.

## Acceso

El login utiliza Supabase Auth con email y contraseña. Tras iniciar sesión, el frontend obtiene el perfil propio desde `public.perfiles` y exige que esté activo y tenga rol `admin` o `vendedor`; el rol vendedor también requiere `vendedor_id`. La sesión se restaura desde Supabase Auth. RLS sigue siendo la frontera de autorización.

## Publicación

Antes de publicar el repositorio o desplegar GitHub Pages, seguir la checklist de [seguridad previa a publicación](docs/security/publicacion.md).

```sh
npm test
```
