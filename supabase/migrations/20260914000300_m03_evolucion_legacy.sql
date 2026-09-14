-- M03: evolucion aditiva y compatible de tablas legacy.
-- Las nuevas relaciones comienzan nullable para no invalidar consumidores ni datos existentes.

alter table public.pagos add column if not exists venta_id uuid;
alter table public.pagos add column if not exists proveedor_origen text;
alter table public.pagos add column if not exists estado_proveedor text;
alter table public.pagos add column if not exists decision_administrativa text;
alter table public.pagos add column if not exists idempotency_key text;
alter table public.pagos add column if not exists correlation_id uuid;
alter table public.licencias add column if not exists cliente_id uuid;
alter table public.licencias add column if not exists venta_id uuid;
alter table public.licencias add column if not exists venta_item_id uuid;
alter table public.licencias add column if not exists producto_id uuid;
alter table public.licencias add column if not exists plan_id uuid;
alter table public.comisiones add column if not exists vendedor_id uuid;
alter table public.comisiones add column if not exists venta_id uuid;
alter table public.comisiones add column if not exists pago_id uuid;
alter table public.comisiones add column if not exists importe_historico numeric(14,2);

do $$
declare
  esperado record;
begin
  for esperado in
    select * from (values
      ('pagos', 'venta_id', 'uuid'), ('pagos', 'proveedor_origen', 'text'),
      ('pagos', 'estado_proveedor', 'text'), ('pagos', 'decision_administrativa', 'text'),
      ('pagos', 'idempotency_key', 'text'), ('pagos', 'correlation_id', 'uuid'),
      ('licencias', 'cliente_id', 'uuid'), ('licencias', 'venta_id', 'uuid'),
      ('licencias', 'venta_item_id', 'uuid'), ('licencias', 'producto_id', 'uuid'),
      ('licencias', 'plan_id', 'uuid'), ('comisiones', 'vendedor_id', 'uuid'),
      ('comisiones', 'venta_id', 'uuid'), ('comisiones', 'pago_id', 'uuid'),
      ('comisiones', 'importe_historico', 'numeric')
    ) as campos(tabla, columna, tipo)
  loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = esperado.tabla
        and column_name = esperado.columna and data_type = esperado.tipo
    ) then
      raise exception using
        message = format('M03 requiere public.%I.%I de tipo %s.', esperado.tabla, esperado.columna, esperado.tipo),
        hint = 'La columna legacy existente es incompatible con el contrato canonico; revise el schema antes de continuar.';
    end if;
  end loop;

  if not exists (select 1 from pg_constraint where conname = 'pagos_venta_id_fkey') then
    alter table public.pagos
      add constraint pagos_venta_id_fkey
      foreign key (venta_id) references public.ventas (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'licencias_cliente_id_fkey') then
    alter table public.licencias
      add constraint licencias_cliente_id_fkey
      foreign key (cliente_id) references public.clientes (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'licencias_venta_id_fkey') then
    alter table public.licencias
      add constraint licencias_venta_id_fkey
      foreign key (venta_id) references public.ventas (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'licencias_venta_item_id_fkey') then
    alter table public.licencias
      add constraint licencias_venta_item_id_fkey
      foreign key (venta_item_id) references public.venta_items (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'licencias_producto_id_fkey') then
    alter table public.licencias
      add constraint licencias_producto_id_fkey
      foreign key (producto_id) references public.productos (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'licencias_plan_id_fkey') then
    alter table public.licencias
      add constraint licencias_plan_id_fkey
      foreign key (plan_id) references public.planes (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'comisiones_vendedor_id_fkey') then
    alter table public.comisiones
      add constraint comisiones_vendedor_id_fkey
      foreign key (vendedor_id) references public.vendedores (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'comisiones_venta_id_fkey') then
    alter table public.comisiones
      add constraint comisiones_venta_id_fkey
      foreign key (venta_id) references public.ventas (id) on delete restrict;
  end if;

  if not exists (select 1 from pg_constraint where conname = 'comisiones_pago_id_fkey') then
    alter table public.comisiones
      add constraint comisiones_pago_id_fkey
      foreign key (pago_id) references public.pagos (id) on delete restrict;
  end if;
end
$$;

create index if not exists pagos_venta_id_idx on public.pagos (venta_id) where venta_id is not null;
create unique index if not exists pagos_idempotency_key_uniq on public.pagos (idempotency_key)
  where idempotency_key is not null;
create index if not exists pagos_correlation_id_idx on public.pagos (correlation_id)
  where correlation_id is not null;
create index if not exists licencias_cliente_id_idx on public.licencias (cliente_id) where cliente_id is not null;
create index if not exists licencias_venta_id_idx on public.licencias (venta_id) where venta_id is not null;
create index if not exists licencias_venta_item_id_idx on public.licencias (venta_item_id)
  where venta_item_id is not null;
create index if not exists licencias_producto_id_idx on public.licencias (producto_id)
  where producto_id is not null;
create index if not exists licencias_plan_id_idx on public.licencias (plan_id) where plan_id is not null;
create index if not exists comisiones_vendedor_id_idx on public.comisiones (vendedor_id)
  where vendedor_id is not null;
create index if not exists comisiones_venta_id_idx on public.comisiones (venta_id) where venta_id is not null;
create index if not exists comisiones_pago_id_idx on public.comisiones (pago_id) where pago_id is not null;

comment on column public.pagos.venta_id is
  'Relacion canonica nullable durante coexistencia. external_reference conserva solo interoperabilidad.';
comment on column public.pagos.idempotency_key is
  'Clave de idempotencia nullable durante coexistencia; su unicidad evita duplicar una misma operacion nueva.';
comment on column public.licencias.cliente_id is
  'Cliente canonico nullable hasta completar backfill y validacion de consumidores.';
comment on column public.licencias.producto_id is
  'Producto canonico nullable hasta completar backfill y validacion de consumidores.';
comment on column public.comisiones.venta_id is
  'Relacion canonica nullable durante coexistencia; no reconstruir por heuristicas.';
