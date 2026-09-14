-- M05: infraestructura futura de Auth. No crea usuarios ni migra passwords legacy.

create schema if not exists app_private;

create table public.perfiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  nombre text not null check (btrim(nombre) <> ''),
  rol text not null check (rol in ('admin', 'vendedor')),
  vendedor_id uuid references public.vendedores (id) on delete restrict,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((rol = 'admin' and vendedor_id is null) or rol = 'vendedor')
);
create index perfiles_vendedor_id_idx on public.perfiles (vendedor_id) where vendedor_id is not null;

create or replace function app_private.es_admin()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.perfiles
    where user_id = (select auth.uid())
      and rol = 'admin'
      and activo
  );
$$;

create or replace function app_private.vendedor_actual_id()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select vendedor_id
  from public.perfiles
  where user_id = (select auth.uid())
    and rol = 'vendedor'
    and activo;
$$;

create or replace function app_private.es_vendedor_de_venta(p_venta_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.ventas
    where id = p_venta_id
      and vendedor_id = (select app_private.vendedor_actual_id())
  );
$$;

revoke all on function app_private.es_admin() from public;
revoke all on function app_private.vendedor_actual_id() from public;
revoke all on function app_private.es_vendedor_de_venta(uuid) from public;
grant usage on schema app_private to authenticated;
grant execute on function app_private.es_admin() to authenticated;
grant execute on function app_private.vendedor_actual_id() to authenticated;
grant execute on function app_private.es_vendedor_de_venta(uuid) to authenticated;

comment on table public.perfiles is
  'Autorizacion futura: auth.users a perfiles a rol/vendedor_id. Nunca se usa metadata editable del usuario.';
