-- Fidelizacion Fase 4: lectura minima de cuenta y saldo para el panel operador.

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
    pg_catalog.coalesce(
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

create or replace function public.fidelizacion_buscar_cuenta_staff(
  p_email text
)
returns table (
  account_id uuid,
  cliente_email text,
  saldo numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from app_private.fidelizacion_buscar_cuenta_staff(p_email);
$$;

revoke all on function app_private.fidelizacion_buscar_cuenta_staff(text)
  from public, anon;
revoke all on function public.fidelizacion_buscar_cuenta_staff(text)
  from public, anon;

grant execute on function app_private.fidelizacion_buscar_cuenta_staff(text)
  to authenticated;
grant execute on function public.fidelizacion_buscar_cuenta_staff(text)
  to authenticated;

comment on function public.fidelizacion_buscar_cuenta_staff(text) is
  'Busca por email exacto una cuenta activa del unico tenant autorizado al staff y devuelve su saldo derivado.';
