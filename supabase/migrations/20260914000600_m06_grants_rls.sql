-- M06: RLS y grants explicitos de las estructuras nuevas canonicas.
-- El hardening de pagos, licencias y comisiones legacy queda condicionado al
-- inventario de consumidores, grants y policies existentes.

alter table public.perfiles enable row level security;
alter table public.clientes enable row level security;
alter table public.productos enable row level security;
alter table public.planes enable row level security;
alter table public.precios enable row level security;
alter table public.ventas enable row level security;
alter table public.venta_items enable row level security;

grant select on public.perfiles, public.clientes, public.productos, public.planes,
  public.precios, public.ventas, public.venta_items to authenticated;
grant insert, update, delete on public.perfiles, public.clientes, public.productos,
  public.planes, public.precios, public.ventas, public.venta_items to authenticated;

create policy perfiles_select_propio on public.perfiles for select to authenticated
  using (user_id = (select auth.uid()));
create policy perfiles_admin_total on public.perfiles for all to authenticated
  using ((select app_private.es_admin()))
  with check ((select app_private.es_admin()));

create policy clientes_admin_total on public.clientes for all to authenticated
  using ((select app_private.es_admin()))
  with check ((select app_private.es_admin()));
create policy clientes_select_vendedor_propietario on public.clientes for select to authenticated
  using (exists (
    select 1 from public.ventas v
    where v.cliente_id = clientes.id
      and v.vendedor_id = (select app_private.vendedor_actual_id())
  ));

create policy productos_select_autenticado on public.productos for select to authenticated using (true);
create policy productos_admin_total on public.productos for all to authenticated
  using ((select app_private.es_admin())) with check ((select app_private.es_admin()));
create policy planes_select_autenticado on public.planes for select to authenticated using (true);
create policy planes_admin_total on public.planes for all to authenticated
  using ((select app_private.es_admin())) with check ((select app_private.es_admin()));
create policy precios_select_autenticado on public.precios for select to authenticated using (true);
create policy precios_admin_total on public.precios for all to authenticated
  using ((select app_private.es_admin())) with check ((select app_private.es_admin()));

create policy ventas_admin_total on public.ventas for all to authenticated
  using ((select app_private.es_admin())) with check ((select app_private.es_admin()));
create policy ventas_select_vendedor_propietario on public.ventas for select to authenticated
  using (vendedor_id = (select app_private.vendedor_actual_id()));

create policy venta_items_admin_total on public.venta_items for all to authenticated
  using ((select app_private.es_admin())) with check ((select app_private.es_admin()));
create policy venta_items_select_vendedor_propietario on public.venta_items for select to authenticated
  using ((select app_private.es_vendedor_de_venta(venta_id)));

comment on schema app_private is
  'Helpers de autorizacion no expuestos por la Data API. No usar metadata de usuario para autorizar.';
