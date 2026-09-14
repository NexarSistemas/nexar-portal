-- M02: operacion comercial y snapshot historico de sus items.

create table public.ventas (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes (id) on delete restrict,
  vendedor_id uuid references public.vendedores (id) on delete restrict,
  external_reference text,
  fecha_venta timestamptz not null default now(),
  moneda text not null check (moneda ~ '^[A-Z]{3}$'),
  estado text not null default 'pendiente'
    check (estado in ('pendiente', 'confirmada', 'cancelada')),
  importe_total numeric(14,2) not null check (importe_total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ventas_cliente_id_idx on public.ventas (cliente_id);
create index ventas_vendedor_id_idx on public.ventas (vendedor_id) where vendedor_id is not null;
create index ventas_external_reference_idx on public.ventas (external_reference)
  where external_reference is not null;

create table public.venta_items (
  id uuid primary key default gen_random_uuid(),
  venta_id uuid not null references public.ventas (id) on delete restrict,
  producto_id uuid not null references public.productos (id) on delete restrict,
  plan_id uuid references public.planes (id) on delete restrict,
  precio_id uuid references public.precios (id) on delete restrict,
  descripcion text not null check (btrim(descripcion) <> ''),
  producto_nombre text not null check (btrim(producto_nombre) <> ''),
  plan_nombre text,
  cantidad numeric(12,3) not null check (cantidad > 0),
  precio_unitario numeric(14,2) not null check (precio_unitario >= 0),
  importe_total numeric(14,2) not null check (importe_total >= 0),
  created_at timestamptz not null default now()
);
create index venta_items_venta_id_idx on public.venta_items (venta_id);
create index venta_items_producto_id_idx on public.venta_items (producto_id) where producto_id is not null;

comment on table public.ventas is
  'Relacion canonica cliente a venta. external_reference es interoperabilidad, no relacion canonica.';
comment on table public.venta_items is
  'Snapshot historico de descripcion, producto, plan, cantidad y precio aplicados; plan y precio de catalogo son opcionales.';
