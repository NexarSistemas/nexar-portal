-- M06.5: acceso Auth+RLS transicional para Portal Vendedor.
-- No modifica consumidores, secretos ni objetos de autenticacion legacy; M07 sigue bloqueada.

do $$
declare
  esperado record;
begin
  for esperado in
    select * from (values
      ('vendedores', 'id'), ('vendedores', 'codigo_vendedor'),
      ('vendedores', 'email'), ('vendedores', 'telefono'), ('vendedores', 'alias_cbu'),
      ('licencias', 'venta_id'), ('licencias', 'codigo_vendedor'),
      ('comisiones', 'vendedor_id')
    ) as columnas(tabla, columna)
  loop
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = esperado.tabla
        and column_name = esperado.columna
    ) then
      raise exception using
        message = format('M06.5 requiere public.%I.%I.', esperado.tabla, esperado.columna),
        hint = 'Releve el schema legacy vigente antes de habilitar el acceso Auth+RLS transicional.';
    end if;
  end loop;
end
$$;

-- No se altera legacy: una policy o grant amplio existente para Auth/Public
-- haria permisivo el RLS nuevo, por lo que se aborta para relevarlo primero.
do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in ('vendedores', 'licencias', 'comisiones')
      and roles && array['public'::name, 'authenticated'::name]
  ) then
    raise exception using
      message = 'M06.5 requiere relevar policies existentes aplicables a public/authenticated.',
      hint = 'No combine el contrato Auth+RLS transicional con una policy legacy amplia; preservela y ajuste el inventario antes de reintentar.';
  end if;

  if has_table_privilege('public', 'public.vendedores', 'INSERT')
    or has_table_privilege('public', 'public.vendedores', 'UPDATE')
    or has_table_privilege('public', 'public.vendedores', 'DELETE')
    or has_table_privilege('public', 'public.licencias', 'INSERT')
    or has_table_privilege('public', 'public.licencias', 'UPDATE')
    or has_table_privilege('public', 'public.licencias', 'DELETE')
    or has_table_privilege('public', 'public.comisiones', 'INSERT')
    or has_table_privilege('public', 'public.comisiones', 'UPDATE')
    or has_table_privilege('public', 'public.comisiones', 'DELETE')
  then
    raise exception using
      message = 'M06.5 requiere que PUBLIC no tenga escrituras sobre las tablas transicionales.',
      hint = 'No revoque grants legacy sin inventario de consumidores; releve el grant amplio antes de habilitar Auth+RLS.';
  end if;
end
$$;

-- Se necesita solo para las licencias legacy que aun no tienen venta_id.
create or replace function app_private.codigo_vendedor_actual()
returns text
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select v.codigo_vendedor
  from public.perfiles p
  join public.vendedores v on v.id = p.vendedor_id
  where p.user_id = (select auth.uid())
    and p.rol = 'vendedor'
    and p.activo;
$$;

revoke all on function app_private.codigo_vendedor_actual() from public;
grant execute on function app_private.codigo_vendedor_actual() to authenticated;

alter table public.vendedores enable row level security;
alter table public.licencias enable row level security;
alter table public.comisiones enable row level security;

-- authenticated solo puede leer estas tablas; el perfil vendedor recibe UPDATE por columna.
grant select on public.vendedores, public.licencias, public.comisiones to authenticated;
revoke insert, update, delete on public.vendedores, public.licencias, public.comisiones from authenticated;
do $$
declare
  columna text;
begin
  for columna in
    select column_name
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'vendedores'
      and column_name not in ('email', 'telefono', 'alias_cbu')
  loop
    execute format('revoke update (%I) on public.vendedores from authenticated', columna);
  end loop;
end
$$;
grant update (email, telefono, alias_cbu) on public.vendedores to authenticated;

create policy vendedores_admin_select on public.vendedores for select to authenticated
  using ((select app_private.es_admin()));
create policy vendedores_select_vendedor_propio on public.vendedores for select to authenticated
  using (id = (select app_private.vendedor_actual_id()));
create policy vendedores_update_vendedor_propio on public.vendedores for update to authenticated
  using (id = (select app_private.vendedor_actual_id()))
  with check (id = (select app_private.vendedor_actual_id()));

create policy licencias_admin_select on public.licencias for select to authenticated
  using ((select app_private.es_admin()));
create policy licencias_select_vendedor_propietario on public.licencias for select to authenticated
  using (
    (venta_id is not null and (select app_private.es_vendedor_de_venta(venta_id)))
    or (
      venta_id is null
      and codigo_vendedor = (select app_private.codigo_vendedor_actual())
    )
  );

create policy comisiones_admin_select on public.comisiones for select to authenticated
  using ((select app_private.es_admin()));
create policy comisiones_select_vendedor_propietario on public.comisiones for select to authenticated
  using (vendedor_id = (select app_private.vendedor_actual_id()));

comment on function app_private.codigo_vendedor_actual() is
  'Codigo legacy del vendedor Auth activo. Solo respalda licencias sin venta_id durante coexistencia.';
