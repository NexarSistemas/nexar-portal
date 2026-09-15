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

-- Supabase puede aplicar default privileges amplios a tablas nuevas de public.
-- M06 establece explicitamente el acceso minimo: anon sin privilegios directos
-- y authenticated solo con CRUD; RLS decide luego que filas puede operar.
revoke all privileges on public.perfiles, public.clientes, public.productos,
  public.planes, public.precios, public.ventas, public.venta_items
  from anon, authenticated;
grant select, insert, update, delete on public.perfiles, public.clientes,
  public.productos, public.planes, public.precios, public.ventas,
  public.venta_items to authenticated;

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

-- solicitudes_upgrade conserva el INSERT anonimo legacy para solicitudes
-- externas. Solo se reemplaza la lectura general de authenticated, sin tocar
-- las demas policies legacy mientras sus consumidores sigan activos.
do $$
declare
  policy_legacy record;
begin
  select policyname, cmd, roles, permissive, qual
  into policy_legacy
  from pg_policies
  where schemaname = 'public'
    and tablename = 'solicitudes_upgrade'
    and policyname = 'allow admin read';

  if not found
    or policy_legacy.cmd <> 'SELECT'
    or cardinality(policy_legacy.roles) <> 1
    or policy_legacy.roles[1] <> 'authenticated'::name
    or policy_legacy.permissive <> 'PERMISSIVE'
    or regexp_replace(coalesce(policy_legacy.qual, ''), '[[:space:]()]', '', 'g') <> 'true'
  then
    raise exception using
      message = 'M06 requiere la policy legacy "allow admin read" sin cambios materiales.',
      hint = 'Releve nuevamente public.solicitudes_upgrade antes de modificar sus policies.';
  end if;
end
$$;

drop policy "allow admin read" on public.solicitudes_upgrade;
drop policy if exists solicitudes_upgrade_admin_select on public.solicitudes_upgrade;
create policy solicitudes_upgrade_admin_select on public.solicitudes_upgrade for select to authenticated
  using ((select app_private.es_admin()));

comment on schema app_private is
  'Helpers de autorizacion no expuestos por la Data API. No usar metadata de usuario para autorizar.';
