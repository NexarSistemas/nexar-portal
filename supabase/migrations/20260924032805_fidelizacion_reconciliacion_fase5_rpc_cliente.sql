-- Reconciliacion remota de Fase 5: repone solo los RPC cliente ausentes.
-- La base destino ya tiene Fases 1 a 4 y 6; no modifica tablas, RLS, grants
-- de tablas, objetos legacy ni M07.

create or replace function app_private.fidelizacion_registrar_cuenta_cliente(
  p_public_qr_code text
)
returns table (
  account_id uuid,
  tenant_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_public_qr_code text := pg_catalog.btrim(p_public_qr_code);
  v_tenant_id uuid;
  v_account_id uuid;
  v_account_activa boolean;
begin
  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'Se requiere una sesion autenticada.';
  end if;

  if v_public_qr_code is null
    or v_public_qr_code !~ '^[A-Za-z0-9_-]{32}$'
  then
    raise exception using
      errcode = '22023',
      message = 'El codigo QR es invalido.';
  end if;

  select t.id
    into v_tenant_id
  from public.fidelizacion_tenants t
  where t.public_qr_code = v_public_qr_code
    and t.activo;

  if v_tenant_id is null then
    raise exception using
      errcode = '42501',
      message = 'El comercio no esta disponible.';
  end if;

  insert into public.fidelizacion_accounts (tenant_id, user_id)
  values (v_tenant_id, v_user_id)
  on conflict on constraint fidelizacion_accounts_tenant_user_key
  do update set user_id = excluded.user_id
  returning id, activo
    into v_account_id, v_account_activa;

  if not v_account_activa then
    raise exception using
      errcode = '55000',
      message = 'La cuenta de fidelizacion no esta habilitada.';
  end if;

  return query
  select v_account_id, v_tenant_id;
end;
$$;

create or replace function public.fidelizacion_registrar_cuenta_cliente(
  p_public_qr_code text
)
returns table (
  account_id uuid,
  tenant_id uuid
)
language sql
volatile
security invoker
set search_path = ''
as $$
  select *
  from app_private.fidelizacion_registrar_cuenta_cliente(p_public_qr_code);
$$;

revoke all on function app_private.fidelizacion_registrar_cuenta_cliente(text)
  from public, anon;
revoke all on function public.fidelizacion_registrar_cuenta_cliente(text)
  from public, anon;

grant execute on function app_private.fidelizacion_registrar_cuenta_cliente(text)
  to authenticated;
grant execute on function public.fidelizacion_registrar_cuenta_cliente(text)
  to authenticated;

comment on function public.fidelizacion_registrar_cuenta_cliente(text) is
  'Registra de forma idempotente la cuenta del usuario autenticado en el tenant activo localizado por su QR publico.';

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
