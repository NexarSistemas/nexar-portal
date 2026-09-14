-- M03: evolucion aditiva y compatible de tablas legacy.
-- Las nuevas relaciones comienzan nullable para no invalidar consumidores ni datos existentes.

alter table public.pagos add column if not exists venta_id uuid;
alter table public.licencias add column if not exists cliente_id uuid;
alter table public.licencias add column if not exists venta_id uuid;
alter table public.licencias add column if not exists venta_item_id uuid;
alter table public.comisiones add column if not exists vendedor_id uuid;
alter table public.comisiones add column if not exists venta_id uuid;
alter table public.comisiones add column if not exists pago_id uuid;

do $$
begin
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
create index if not exists licencias_cliente_id_idx on public.licencias (cliente_id) where cliente_id is not null;
create index if not exists licencias_venta_id_idx on public.licencias (venta_id) where venta_id is not null;
create index if not exists licencias_venta_item_id_idx on public.licencias (venta_item_id)
  where venta_item_id is not null;
create index if not exists comisiones_vendedor_id_idx on public.comisiones (vendedor_id)
  where vendedor_id is not null;
create index if not exists comisiones_venta_id_idx on public.comisiones (venta_id) where venta_id is not null;
create index if not exists comisiones_pago_id_idx on public.comisiones (pago_id) where pago_id is not null;

comment on column public.pagos.venta_id is
  'Relacion canonica nullable durante coexistencia. external_reference conserva solo interoperabilidad.';
comment on column public.licencias.cliente_id is
  'Cliente canonico nullable hasta completar backfill y validacion de consumidores.';
comment on column public.comisiones.venta_id is
  'Relacion canonica nullable durante coexistencia; no reconstruir por heuristicas.';
