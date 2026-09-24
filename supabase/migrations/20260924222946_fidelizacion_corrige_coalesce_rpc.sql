-- Corrige la resolucion diferida de COALESCE en los helpers invocados por los RPC.
-- COALESCE es sintaxis SQL y no una funcion de pg_catalog: al calificarlo, PL/pgSQL
-- fallaba al ejecutar con SQLSTATE 42883 aunque PostgREST encontrara el wrapper.

create or replace function app_private.fidelizacion_buscar_cuenta_staff(
  p_email text
)
returns table (
  account_id uuid,
  cliente_email text,
  saldo numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_email text := pg_catalog.lower(pg_catalog.btrim(p_email));
  v_tenant_id uuid;
  v_membresias bigint;
begin
  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'Se requiere una sesion autenticada.';
  end if;

  if v_email is null or v_email = '' then
    raise exception using
      errcode = '22023',
      message = 'El email es obligatorio.';
  end if;

  select
    pg_catalog.count(*),
    (pg_catalog.array_agg(s.tenant_id order by s.tenant_id))[1]
  into v_membresias, v_tenant_id
  from public.fidelizacion_staff s
  join public.fidelizacion_tenants t
    on t.id = s.tenant_id
   and t.activo
  where s.user_id = v_user_id
    and s.activo
    and s.rol in ('admin', 'operador');

  if v_membresias <> 1 then
    raise exception using
      errcode = '42501',
      message = 'No existe un acceso unico de staff habilitado.';
  end if;

  return query
  select
    a.id,
    pg_catalog.btrim(u.email),
    coalesce(
      (
        select pg_catalog.sum(m.puntos)
        from public.fidelizacion_point_movements m
        where m.tenant_id = a.tenant_id
          and m.account_id = a.id
      ),
      0::numeric
    )
  from public.fidelizacion_accounts a
  join auth.users u
    on u.id = a.user_id
  where a.tenant_id = v_tenant_id
    and a.activo
    and pg_catalog.lower(pg_catalog.btrim(u.email)) = v_email;
end;
$$;

create or replace function app_private.fidelizacion_obtener_saldo_cliente(
  p_account_id uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
  v_saldo numeric;
begin
  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'Se requiere una sesion autenticada.';
  end if;

  if p_account_id is null then
    raise exception using
      errcode = '22023',
      message = 'La cuenta es obligatoria.';
  end if;

  select a.tenant_id
    into v_tenant_id
  from public.fidelizacion_accounts a
  join public.fidelizacion_tenants t
    on t.id = a.tenant_id
   and t.activo
  where a.id = p_account_id
    and a.user_id = v_user_id
    and a.activo;

  if v_tenant_id is null then
    raise exception using
      errcode = '42501',
      message = 'La cuenta no esta disponible para el cliente autenticado.';
  end if;

  select coalesce(pg_catalog.sum(m.puntos), 0::numeric)
    into v_saldo
  from public.fidelizacion_point_movements m
  where m.tenant_id = v_tenant_id
    and m.account_id = p_account_id;

  return v_saldo;
end;
$$;
