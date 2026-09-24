-- Restablece el contrato efectivo de los wrappers RPC usados por las pantallas
-- de Fidelizacion. Los helpers privados mantienen la autorizacion con auth.uid().

revoke all on schema app_private from public, anon;
grant usage on schema app_private to authenticated;

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

revoke all on function app_private.fidelizacion_buscar_cuenta_staff(text)
  from public, anon;
revoke all on function public.fidelizacion_buscar_cuenta_staff(text)
  from public, anon;
revoke all on function app_private.fidelizacion_registrar_cuenta_cliente(text)
  from public, anon;
revoke all on function public.fidelizacion_registrar_cuenta_cliente(text)
  from public, anon;
revoke all on function app_private.fidelizacion_obtener_saldo_cliente(uuid)
  from public, anon;
revoke all on function public.fidelizacion_obtener_saldo_cliente(uuid)
  from public, anon;
revoke all on function app_private.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  from public, anon;
revoke all on function public.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  from public, anon;
revoke all on function app_private.fidelizacion_obtener_earn_pendientes(text)
  from public, anon;
revoke all on function public.fidelizacion_obtener_earn_pendientes(text)
  from public, anon;
revoke all on function app_private.fidelizacion_confirmar_earn(text, uuid)
  from public, anon;
revoke all on function public.fidelizacion_confirmar_earn(text, uuid)
  from public, anon;
revoke all on function app_private.fidelizacion_crear_redeem(uuid, text, timestamptz)
  from public, anon;
revoke all on function public.fidelizacion_crear_redeem(uuid, text, timestamptz)
  from public, anon;
revoke all on function app_private.fidelizacion_escanear_redeem(text, uuid)
  from public, anon;
revoke all on function public.fidelizacion_escanear_redeem(text, uuid)
  from public, anon;
revoke all on function app_private.fidelizacion_confirmar_redeem(uuid)
  from public, anon;
revoke all on function public.fidelizacion_confirmar_redeem(uuid)
  from public, anon;
revoke all on function app_private.fidelizacion_cancelar_redeem(uuid)
  from public, anon;
revoke all on function public.fidelizacion_cancelar_redeem(uuid)
  from public, anon;

grant execute on function app_private.fidelizacion_buscar_cuenta_staff(text)
  to authenticated;
grant execute on function public.fidelizacion_buscar_cuenta_staff(text)
  to authenticated;
grant execute on function app_private.fidelizacion_registrar_cuenta_cliente(text)
  to authenticated;
grant execute on function public.fidelizacion_registrar_cuenta_cliente(text)
  to authenticated;
grant execute on function app_private.fidelizacion_obtener_saldo_cliente(uuid)
  to authenticated;
grant execute on function public.fidelizacion_obtener_saldo_cliente(uuid)
  to authenticated;
grant execute on function app_private.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  to authenticated;
grant execute on function public.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  to authenticated;
grant execute on function app_private.fidelizacion_obtener_earn_pendientes(text)
  to authenticated;
grant execute on function public.fidelizacion_obtener_earn_pendientes(text)
  to authenticated;
grant execute on function app_private.fidelizacion_confirmar_earn(text, uuid)
  to authenticated;
grant execute on function public.fidelizacion_confirmar_earn(text, uuid)
  to authenticated;
grant execute on function app_private.fidelizacion_crear_redeem(uuid, text, timestamptz)
  to authenticated;
grant execute on function public.fidelizacion_crear_redeem(uuid, text, timestamptz)
  to authenticated;
grant execute on function app_private.fidelizacion_escanear_redeem(text, uuid)
  to authenticated;
grant execute on function public.fidelizacion_escanear_redeem(text, uuid)
  to authenticated;
grant execute on function app_private.fidelizacion_confirmar_redeem(uuid)
  to authenticated;
grant execute on function public.fidelizacion_confirmar_redeem(uuid)
  to authenticated;
grant execute on function app_private.fidelizacion_cancelar_redeem(uuid)
  to authenticated;
grant execute on function public.fidelizacion_cancelar_redeem(uuid)
  to authenticated;
