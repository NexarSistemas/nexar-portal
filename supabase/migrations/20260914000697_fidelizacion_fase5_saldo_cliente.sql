-- Fidelizacion Fase 5: saldo derivado atomico para la cuenta cliente autenticada.

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

  select pg_catalog.coalesce(pg_catalog.sum(m.puntos), 0::numeric)
    into v_saldo
  from public.fidelizacion_point_movements m
  where m.tenant_id = v_tenant_id
    and m.account_id = p_account_id;

  return v_saldo;
end;
$$;

create or replace function public.fidelizacion_obtener_saldo_cliente(
  p_account_id uuid
)
returns numeric
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.fidelizacion_obtener_saldo_cliente(p_account_id);
$$;

revoke all on function app_private.fidelizacion_obtener_saldo_cliente(uuid)
  from public, anon;
revoke all on function public.fidelizacion_obtener_saldo_cliente(uuid)
  from public, anon;

grant execute on function app_private.fidelizacion_obtener_saldo_cliente(uuid)
  to authenticated;
grant execute on function public.fidelizacion_obtener_saldo_cliente(uuid)
  to authenticated;

comment on function public.fidelizacion_obtener_saldo_cliente(uuid) is
  'Devuelve el saldo derivado del ledger para la cuenta activa del cliente autenticado.';
