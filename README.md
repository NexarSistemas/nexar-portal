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

Copiá `.env.example` a `.env` y completá las variables públicas del proyecto Supabase:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY` (o la clave pública publishable del proyecto)

No agregues claves secretas ni `service_role` al frontend.

## Acceso

El login utiliza Supabase Auth con email y contraseña. Tras iniciar sesión, el frontend obtiene el perfil propio desde `public.perfiles` y exige que esté activo y tenga rol `admin` o `vendedor`; el rol vendedor también requiere `vendedor_id`. La sesión se restaura desde Supabase Auth. RLS sigue siendo la frontera de autorización.

```sh
npm test
```
