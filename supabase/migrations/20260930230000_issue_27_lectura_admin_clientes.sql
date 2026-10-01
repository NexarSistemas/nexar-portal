-- Issue #27: lectura administrativa mínima de relaciones canónicas de clientes.
-- No modifica filas, relaciones legacy ni policies de licencias existentes.

do $$
declare
  columna text;
begin
  if not exists (
    select 1
    from pg_class c
    where c.oid = 'public.pagos'::regclass
      and c.relrowsecurity
  ) then
    raise exception using
      message = 'Issue #27 requiere RLS habilitado en public.pagos.',
      hint = 'Releve las policies y los consumidores legacy antes de habilitar nuevas lecturas.';
  end if;

  if not exists (
    select 1
    from pg_class c
    where c.oid = 'public.licencias'::regclass
      and c.relrowsecurity
  ) then
    raise exception using
      message = 'Issue #27 requiere RLS habilitado en public.licencias.',
      hint = 'No amplie grants sin el aislamiento transicional de licencias.';
  end if;

  foreach columna in array array[
    'id', 'venta_id', 'monto', 'moneda', 'proveedor_origen',
    'estado_proveedor', 'decision_administrativa', 'created_at'
  ]
  loop
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'pagos'
        and column_name = columna
    ) then
      raise exception using
        message = format('Issue #27 requiere public.pagos.%I.', columna),
        hint = 'Releve el schema remoto antes de restringir el grant de SELECT legado.';
    end if;
  end loop;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'licencias'
      and column_name = 'cliente_id'
  ) then
    raise exception using
      message = 'Issue #27 requiere public.licencias.cliente_id.',
      hint = 'La correlacion con clientes usa exclusivamente la FK canonica.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'pagos_venta_id_fkey'
      and conrelid = 'public.pagos'::regclass
      and confrelid = 'public.ventas'::regclass
  ) then
    raise exception using
      message = 'Issue #27 requiere la FK canonica public.pagos.venta_id.',
      hint = 'No use external_reference ni otra heuristica para relacionar pagos con clientes.';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'pagos'
      and cmd in ('SELECT', 'ALL')
  ) then
    raise exception using
      message = 'Issue #27 requiere que public.pagos no tenga policies SELECT o ALL previas.',
      hint = 'Releve las policies legacy antes de habilitar pagos_admin_select; no se modifican automaticamente.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'licencias_cliente_id_fkey'
      and conrelid = 'public.licencias'::regclass
      and confrelid = 'public.clientes'::regclass
  ) then
    raise exception using
      message = 'Issue #27 requiere la FK canonica public.licencias.cliente_id.',
      hint = 'No use usuario, email ni otra heuristica para relacionar licencias con clientes.';
  end if;

  if has_table_privilege('public', 'public.pagos', 'SELECT')
    or exists (
      select 1
      from pg_attribute a
      where a.attrelid = 'public.pagos'::regclass
        and a.attnum > 0
        and not a.attisdropped
        and has_column_privilege('public', a.attrelid, a.attname, 'SELECT')
    ) then
    raise exception using
      message = 'Issue #27 requiere que PUBLIC no tenga SELECT sobre public.pagos.',
      hint = 'No revoque grants legacy de PUBLIC sin inventario de consumidores.';
  end if;
end
$$;

-- El grant legado de tabla completa no aporta lecturas mientras no hay policy,
-- pero se volvería excesivo al habilitar la lectura administrativa.
revoke select on table public.pagos from authenticated;

do $$
declare
  objeto record;
begin
  for objeto in
    select column_name
    from information_schema.columns
    where table_schema = 'public' and table_name = 'pagos'
  loop
    execute format(
      'revoke all privileges (%I) on table public.pagos from authenticated',
      objeto.column_name
    );
  end loop;
end
$$;

grant select (
  id, venta_id, monto, moneda, proveedor_origen,
  estado_proveedor, decision_administrativa, created_at
) on public.pagos to authenticated;

create policy pagos_admin_select on public.pagos for select to authenticated
  using ((select app_private.es_admin()));

create or replace function app_private.licencias_admin_por_cliente(
  p_cliente_id uuid
)
returns table (
  cliente_id uuid,
  license_key text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'Se requiere una sesion autenticada.';
  end if;

  if p_cliente_id is null then
    raise exception using
      errcode = '22023',
      message = 'El cliente es obligatorio.';
  end if;

  if not app_private.es_admin() then
    raise exception using
      errcode = '42501',
      message = 'El perfil no tiene acceso administrativo.';
  end if;

  return query
  select l.cliente_id, l.license_key::text
  from public.licencias l
  where l.cliente_id = p_cliente_id;
end;
$$;

create or replace function public.licencias_admin_por_cliente(
  p_cliente_id uuid
)
returns table (
  cliente_id uuid,
  license_key text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from app_private.licencias_admin_por_cliente(p_cliente_id);
$$;

revoke all on function app_private.licencias_admin_por_cliente(uuid) from public, anon;
revoke all on function public.licencias_admin_por_cliente(uuid) from public, anon;
grant execute on function app_private.licencias_admin_por_cliente(uuid) to authenticated;
grant execute on function public.licencias_admin_por_cliente(uuid) to authenticated;

comment on function public.licencias_admin_por_cliente(uuid) is
  'Devuelve solo la relacion canonica licencia-cliente para un administrador autenticado.';
