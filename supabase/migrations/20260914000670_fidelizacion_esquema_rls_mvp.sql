-- Fidelizacion Fase 1: esquema multi-tenant, integridad, RLS y grants del MVP.
-- No crea flujos de confirmacion ni modifica objetos legacy.

do $$
begin
  if to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception using
      message = 'Fidelizacion requiere extensions.gen_random_bytes(integer).',
      hint = 'Verifique que pgcrypto este habilitada en el schema extensions antes de aplicar la migracion.';
  end if;
end
$$;

create schema if not exists app_private;

create table public.fidelizacion_tenants (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  nombre text not null,
  activo boolean not null default true,
  logo_url text,
  color_primario text,
  public_qr_code text not null unique default
    pg_catalog.translate(
      pg_catalog.rtrim(pg_catalog.encode(extensions.gen_random_bytes(24), 'base64'), '='),
      '+/',
      '-_'
    ),
  configuracion jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fidelizacion_tenants_slug_check
    check (slug = pg_catalog.lower(pg_catalog.btrim(slug)) and slug <> ''),
  constraint fidelizacion_tenants_nombre_check
    check (pg_catalog.btrim(nombre) <> ''),
  constraint fidelizacion_tenants_public_qr_code_check
    check (public_qr_code ~ '^[A-Za-z0-9_-]{32}$'),
  constraint fidelizacion_tenants_configuracion_check
    check (pg_catalog.jsonb_typeof(configuracion) = 'object')
);

create table public.fidelizacion_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.fidelizacion_tenants (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint fidelizacion_accounts_tenant_user_key unique (tenant_id, user_id),
  constraint fidelizacion_accounts_tenant_id_id_key unique (tenant_id, id)
);

create table public.fidelizacion_staff (
  tenant_id uuid not null references public.fidelizacion_tenants (id) on delete restrict,
  user_id uuid not null references auth.users (id) on delete restrict,
  rol text not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  constraint fidelizacion_staff_pkey primary key (tenant_id, user_id),
  constraint fidelizacion_staff_rol_check check (rol in ('admin', 'operador'))
);

create table public.fidelizacion_rewards (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.fidelizacion_tenants (id) on delete restrict,
  nombre text not null,
  descripcion text,
  puntos_requeridos bigint not null,
  activa boolean not null default true,
  created_at timestamptz not null default now(),
  constraint fidelizacion_rewards_nombre_check check (pg_catalog.btrim(nombre) <> ''),
  constraint fidelizacion_rewards_puntos_requeridos_check check (puntos_requeridos > 0),
  constraint fidelizacion_rewards_tenant_id_id_key unique (tenant_id, id)
);

create table public.fidelizacion_operations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_id uuid not null,
  tipo text not null,
  puntos bigint not null,
  puntos_movimiento bigint generated always as (
    case when tipo = 'earn' then puntos else -puntos end
  ) stored not null,
  reward_id uuid,
  estado text not null,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  idempotency_key text not null,
  constraint fidelizacion_operations_tenant_account_fkey
    foreign key (tenant_id, account_id)
    references public.fidelizacion_accounts (tenant_id, id) on delete restrict,
  constraint fidelizacion_operations_tenant_reward_fkey
    foreign key (tenant_id, reward_id)
    references public.fidelizacion_rewards (tenant_id, id) on delete restrict,
  constraint fidelizacion_operations_tipo_check check (tipo in ('earn', 'redeem')),
  constraint fidelizacion_operations_puntos_check check (puntos > 0),
  constraint fidelizacion_operations_reward_check
    check ((tipo = 'earn' and reward_id is null) or (tipo = 'redeem' and reward_id is not null)),
  constraint fidelizacion_operations_estado_check
    check (estado in ('pending_customer', 'pending_staff', 'confirmed', 'cancelled', 'expired')),
  constraint fidelizacion_operations_confirmed_at_check
    check ((estado = 'confirmed') = (confirmed_at is not null)),
  constraint fidelizacion_operations_expires_at_check
    check (expires_at is null or expires_at > created_at),
  constraint fidelizacion_operations_idempotency_key_check
    check (pg_catalog.btrim(idempotency_key) <> ''),
  constraint fidelizacion_operations_tenant_idempotency_key_key
    unique (tenant_id, idempotency_key),
  constraint fidelizacion_operations_tenant_id_id_key unique (tenant_id, id),
  constraint fidelizacion_operations_tenant_id_account_tipo_puntos_key
    unique (tenant_id, id, account_id, tipo, puntos_movimiento),
  constraint fidelizacion_operations_tenant_id_account_reward_key
    unique (tenant_id, id, account_id, reward_id)
);

create table public.fidelizacion_point_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_id uuid not null,
  tipo text not null,
  puntos bigint not null,
  descripcion text,
  fecha timestamptz not null default now(),
  operation_id uuid not null,
  constraint fidelizacion_point_movements_operation_fkey
    foreign key (tenant_id, operation_id, account_id, tipo, puntos)
    references public.fidelizacion_operations
      (tenant_id, id, account_id, tipo, puntos_movimiento)
    on delete restrict,
  constraint fidelizacion_point_movements_tipo_check check (tipo in ('earn', 'redeem')),
  constraint fidelizacion_point_movements_puntos_check
    check ((tipo = 'earn' and puntos > 0) or (tipo = 'redeem' and puntos < 0)),
  constraint fidelizacion_point_movements_operation_id_key unique (operation_id)
);

create table public.fidelizacion_redemptions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_id uuid not null,
  reward_id uuid not null,
  operation_id uuid not null,
  puntos_requeridos bigint not null,
  estado text not null,
  created_at timestamptz not null default now(),
  constraint fidelizacion_redemptions_tenant_account_fkey
    foreign key (tenant_id, account_id)
    references public.fidelizacion_accounts (tenant_id, id) on delete restrict,
  constraint fidelizacion_redemptions_tenant_reward_fkey
    foreign key (tenant_id, reward_id)
    references public.fidelizacion_rewards (tenant_id, id) on delete restrict,
  constraint fidelizacion_redemptions_operation_fkey
    foreign key (tenant_id, operation_id, account_id, reward_id)
    references public.fidelizacion_operations (tenant_id, id, account_id, reward_id)
    on delete restrict,
  constraint fidelizacion_redemptions_puntos_requeridos_check check (puntos_requeridos > 0),
  constraint fidelizacion_redemptions_estado_check check (pg_catalog.btrim(estado) <> ''),
  constraint fidelizacion_redemptions_operation_id_key unique (operation_id)
);

create index fidelizacion_accounts_user_id_idx
  on public.fidelizacion_accounts (user_id, tenant_id);
create index fidelizacion_staff_user_id_idx
  on public.fidelizacion_staff (user_id, tenant_id);
create index fidelizacion_rewards_tenant_activa_idx
  on public.fidelizacion_rewards (tenant_id, activa);
create index fidelizacion_operations_account_created_at_idx
  on public.fidelizacion_operations (tenant_id, account_id, created_at desc);
create index fidelizacion_operations_tenant_reward_idx
  on public.fidelizacion_operations (tenant_id, reward_id) where reward_id is not null;
create index fidelizacion_operations_estado_expires_at_idx
  on public.fidelizacion_operations (tenant_id, estado, expires_at);
create index fidelizacion_point_movements_account_fecha_idx
  on public.fidelizacion_point_movements (tenant_id, account_id, fecha desc);
create index fidelizacion_redemptions_account_created_at_idx
  on public.fidelizacion_redemptions (tenant_id, account_id, created_at desc);
create index fidelizacion_redemptions_reward_id_idx
  on public.fidelizacion_redemptions (tenant_id, reward_id);

create or replace function app_private.fidelizacion_es_cliente(
  p_tenant_id uuid,
  p_account_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1
    from public.fidelizacion_accounts a
    join public.fidelizacion_tenants t on t.id = a.tenant_id
    where a.tenant_id = p_tenant_id
      and a.user_id = (select auth.uid())
      and a.activo
      and t.activo
      and (p_account_id is null or a.id = p_account_id)
  );
$$;

create or replace function app_private.fidelizacion_es_staff(
  p_tenant_id uuid,
  p_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1
    from public.fidelizacion_staff s
    join public.fidelizacion_tenants t on t.id = s.tenant_id
    where s.tenant_id = p_tenant_id
      and s.user_id = (select auth.uid())
      and s.activo
      and t.activo
      and s.rol = any (p_roles)
  );
$$;

revoke all on function app_private.fidelizacion_es_cliente(uuid, uuid) from public;
revoke all on function app_private.fidelizacion_es_staff(uuid, text[]) from public;
grant usage on schema app_private to authenticated;
grant execute on function app_private.fidelizacion_es_cliente(uuid, uuid) to authenticated;
grant execute on function app_private.fidelizacion_es_staff(uuid, text[]) to authenticated;

alter table public.fidelizacion_tenants enable row level security;
alter table public.fidelizacion_accounts enable row level security;
alter table public.fidelizacion_staff enable row level security;
alter table public.fidelizacion_rewards enable row level security;
alter table public.fidelizacion_operations enable row level security;
alter table public.fidelizacion_point_movements enable row level security;
alter table public.fidelizacion_redemptions enable row level security;

revoke all privileges on
  public.fidelizacion_tenants,
  public.fidelizacion_accounts,
  public.fidelizacion_staff,
  public.fidelizacion_rewards,
  public.fidelizacion_operations,
  public.fidelizacion_point_movements,
  public.fidelizacion_redemptions
from public, anon, authenticated;

grant select on
  public.fidelizacion_tenants,
  public.fidelizacion_accounts,
  public.fidelizacion_staff,
  public.fidelizacion_rewards,
  public.fidelizacion_operations,
  public.fidelizacion_point_movements,
  public.fidelizacion_redemptions
to authenticated;

grant select, insert, update, delete on
  public.fidelizacion_tenants,
  public.fidelizacion_accounts,
  public.fidelizacion_staff,
  public.fidelizacion_rewards,
  public.fidelizacion_operations,
  public.fidelizacion_point_movements,
  public.fidelizacion_redemptions
to service_role;

create policy fidelizacion_tenants_select_miembro
on public.fidelizacion_tenants for select to authenticated
using (
  (select app_private.fidelizacion_es_cliente(id, null))
  or (select app_private.fidelizacion_es_staff(id, array['admin', 'operador']))
);

create policy fidelizacion_accounts_select_propia_o_staff
on public.fidelizacion_accounts for select to authenticated
using (
  (select app_private.fidelizacion_es_cliente(tenant_id, id))
  or (select app_private.fidelizacion_es_staff(tenant_id, array['admin', 'operador']))
);

create policy fidelizacion_staff_select_propia_o_admin
on public.fidelizacion_staff for select to authenticated
using (
  (
    user_id = (select auth.uid())
    and (select app_private.fidelizacion_es_staff(tenant_id, array['admin', 'operador']))
  )
  or (select app_private.fidelizacion_es_staff(tenant_id, array['admin']))
);

create policy fidelizacion_rewards_select_cliente_o_staff
on public.fidelizacion_rewards for select to authenticated
using (
  ((select app_private.fidelizacion_es_cliente(tenant_id, null)) and activa)
  or (select app_private.fidelizacion_es_staff(tenant_id, array['admin', 'operador']))
);

create policy fidelizacion_operations_select_propia_o_staff
on public.fidelizacion_operations for select to authenticated
using (
  (select app_private.fidelizacion_es_cliente(tenant_id, account_id))
  or (select app_private.fidelizacion_es_staff(tenant_id, array['admin', 'operador']))
);

create policy fidelizacion_point_movements_select_propio_o_staff
on public.fidelizacion_point_movements for select to authenticated
using (
  (select app_private.fidelizacion_es_cliente(tenant_id, account_id))
  or (select app_private.fidelizacion_es_staff(tenant_id, array['admin', 'operador']))
);

create policy fidelizacion_redemptions_select_propia_o_staff
on public.fidelizacion_redemptions for select to authenticated
using (
  (select app_private.fidelizacion_es_cliente(tenant_id, account_id))
  or (select app_private.fidelizacion_es_staff(tenant_id, array['admin', 'operador']))
);

comment on table public.fidelizacion_point_movements is
  'Libro mayor y fuente de verdad del saldo de puntos; no mantener un saldo mutable paralelo.';
comment on column public.fidelizacion_operations.puntos_movimiento is
  'Impacto firmado de la operacion, usado por la FK del movimiento para garantizar la cantidad exacta de puntos.';
comment on column public.fidelizacion_tenants.public_qr_code is
  'Localizador publico opaco de 192 bits aleatorios, codificado como base64url sin padding; no es una credencial.';
comment on schema app_private is
  'Helpers de autorizacion no expuestos por la Data API. No usar metadata de usuario para autorizar.';
