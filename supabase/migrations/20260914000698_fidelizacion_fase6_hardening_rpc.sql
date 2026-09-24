-- Fidelizacion Fase 6: los RPC publicos de canje no elevan privilegios.
-- La autorizacion y las mutaciones sensibles permanecen en app_private.

create or replace function public.fidelizacion_crear_redeem(
  p_reward_id uuid,
  p_idempotency_key text,
  p_expires_at timestamptz default null
)
returns table (operation_id uuid, puntos bigint, estado text, expires_at timestamptz, created_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from app_private.fidelizacion_crear_redeem(p_reward_id, p_idempotency_key, p_expires_at);
$$;

create or replace function public.fidelizacion_escanear_redeem(
  p_public_qr_code text,
  p_operation_id uuid
)
returns table (operation_id uuid, puntos bigint, estado text, expires_at timestamptz)
language sql
security invoker
set search_path = ''
as $$
  select * from app_private.fidelizacion_escanear_redeem(p_public_qr_code, p_operation_id);
$$;

create or replace function public.fidelizacion_confirmar_redeem(p_operation_id uuid)
returns table (
  operation_id uuid,
  redemption_id uuid,
  puntos bigint,
  estado text,
  confirmed_at timestamptz,
  saldo numeric
)
language sql
security invoker
set search_path = ''
as $$
  select * from app_private.fidelizacion_confirmar_redeem(p_operation_id);
$$;

create or replace function public.fidelizacion_cancelar_redeem(p_operation_id uuid)
returns table (operation_id uuid, estado text)
language sql
security invoker
set search_path = ''
as $$
  select * from app_private.fidelizacion_cancelar_redeem(p_operation_id);
$$;

revoke all on function public.fidelizacion_crear_redeem(uuid, text, timestamptz) from public, anon;
revoke all on function public.fidelizacion_escanear_redeem(text, uuid) from public, anon;
revoke all on function public.fidelizacion_confirmar_redeem(uuid) from public, anon;
revoke all on function public.fidelizacion_cancelar_redeem(uuid) from public, anon;

grant execute on function public.fidelizacion_crear_redeem(uuid, text, timestamptz) to authenticated;
grant execute on function public.fidelizacion_escanear_redeem(text, uuid) to authenticated;
grant execute on function public.fidelizacion_confirmar_redeem(uuid) to authenticated;
grant execute on function public.fidelizacion_cancelar_redeem(uuid) to authenticated;
