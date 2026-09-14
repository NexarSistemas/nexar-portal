-- M01: entidades canonicas de clientes y catalogo. precios_planes permanece intacta.

create table public.clientes (
  id uuid primary key default gen_random_uuid(),
  nombre_completo text not null check (btrim(nombre_completo) <> ''),
  email text,
  telefono text,
  tipo_documento text,
  numero_documento text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (tipo_documento is null and numero_documento is null)
    or (tipo_documento is not null and numero_documento is not null)
  )
);

-- El email no es unico: no se fusionan clientes por coincidencia de email.
create index clientes_email_idx on public.clientes (email) where email is not null;
create index clientes_documento_idx on public.clientes (tipo_documento, numero_documento)
  where tipo_documento is not null;

create table public.productos (
  id uuid primary key default gen_random_uuid(),
  codigo text not null check (btrim(codigo) <> ''),
  nombre text not null check (btrim(nombre) <> ''),
  descripcion text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (codigo)
);

create table public.planes (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos (id) on delete restrict,
  codigo text not null check (btrim(codigo) <> ''),
  nombre text not null check (btrim(nombre) <> ''),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (producto_id, codigo),
  constraint planes_id_producto_id_key unique (id, producto_id)
);
create index planes_producto_id_idx on public.planes (producto_id);

create table public.precios (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.planes (id) on delete restrict,
  moneda text not null check (moneda ~ '^[A-Z]{3}$'),
  importe numeric(14,2) not null check (importe >= 0),
  modalidad_cobro text not null check (btrim(modalidad_cobro) <> ''),
  estado text not null default 'activo' check (btrim(estado) <> ''),
  vigente_desde timestamptz not null,
  vigente_hasta timestamptz,
  created_at timestamptz not null default now(),
  check (vigente_hasta is null or vigente_hasta > vigente_desde),
  unique (plan_id, vigente_desde),
  constraint precios_id_plan_id_key unique (id, plan_id)
);
create index precios_plan_vigencia_idx on public.precios (plan_id, vigente_desde desc);

comment on table public.precios is
  'Precios versionados con modalidad y estado. Las ventas conservan su propio snapshot y no se reconstruyen desde esta tabla.';
