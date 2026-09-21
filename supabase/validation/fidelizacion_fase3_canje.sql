-- Solo lectura: valida RPC, privilegios e integridad de Fidelizacion Fase 3.

with esperadas(firma) as (
  values
    ('public.fidelizacion_crear_redeem(uuid,text,timestamp with time zone)'),
    ('public.fidelizacion_escanear_redeem(text,uuid)'),
    ('public.fidelizacion_confirmar_redeem(uuid)'),
    ('public.fidelizacion_cancelar_redeem(uuid)'),
    ('app_private.fidelizacion_crear_redeem(uuid,text,timestamp with time zone)'),
    ('app_private.fidelizacion_escanear_redeem(text,uuid)'),
    ('app_private.fidelizacion_confirmar_redeem(uuid)'),
    ('app_private.fidelizacion_cancelar_redeem(uuid)')
)
select firma as funcion_faltante
from esperadas
where to_regprocedure(firma) is null
order by firma;

select
  p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false) as search_path_vacio,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in (
  'fidelizacion_crear_redeem', 'fidelizacion_escanear_redeem',
  'fidelizacion_confirmar_redeem', 'fidelizacion_cancelar_redeem'
)
order by p.proname;

select
  p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false) as search_path_vacio,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  not has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_sin_execute,
  pg_catalog.position('auth.uid()' in pg_get_functiondef(p.oid)) > 0 as deriva_identidad_auth,
  pg_catalog.position('public.perfiles' in pg_get_functiondef(p.oid)) = 0 as sin_perfiles
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'app_private' and p.proname in (
  'fidelizacion_crear_redeem', 'fidelizacion_escanear_redeem',
  'fidelizacion_confirmar_redeem', 'fidelizacion_cancelar_redeem'
)
order by p.proname;

select
  pg_catalog.position('fidelizacion_rewards' in definicion) > 0 as valida_recompensa_activa,
  pg_catalog.position('puntos_requeridos' in definicion) > 0 as congela_costo,
  pg_catalog.position('on conflict on constraint fidelizacion_operations_tenant_idempotency_key_key' in definicion) > 0 as idempotencia_por_constraint,
  pg_catalog.position('pending_customer' in definicion) > 0 as crea_pending_customer
from (
  select pg_catalog.lower(pg_get_functiondef('app_private.fidelizacion_crear_redeem(uuid,text,timestamp with time zone)'::regprocedure)) as definicion
) f;

select
  pg_catalog.position('public_qr_code' in definicion) > 0 as qr_resuelve_tenant,
  pg_catalog.position('pending_customer' in definicion) > 0 as valida_estado_origen,
  pg_catalog.position('pending_staff' in definicion) > 0 as avanza_a_pending_staff,
  pg_catalog.position('fidelizacion_point_movements' in definicion) = 0 as escaneo_sin_movimientos
from (
  select pg_catalog.lower(pg_get_functiondef('app_private.fidelizacion_escanear_redeem(text,uuid)'::regprocedure)) as definicion
) f;

select
  pg_catalog.position('fidelizacion_staff' in definicion) > 0 as valida_staff,
  pg_catalog.position('for update' in definicion) > 0 as bloquea_operacion,
  pg_catalog.position('for update;' in definicion) > 0 as bloquea_cuenta,
  pg_catalog.position('sum(m.puntos)' in definicion) > 0 as saldo_derivado_bajo_lock,
  pg_catalog.position('fidelizacion_redemptions' in definicion) > 0 as crea_redencion,
  pg_catalog.position('fidelizacion_point_movements' in definicion) > 0 as crea_movimiento_negativo
from (
  select pg_catalog.lower(pg_get_functiondef('app_private.fidelizacion_confirmar_redeem(uuid)'::regprocedure)) as definicion
) f;

select conname, contype, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conrelid = 'public.fidelizacion_redemptions'::regclass
  and conname in (
    'fidelizacion_redemptions_operation_puntos_fkey',
    'fidelizacion_redemptions_confirmed_check'
  )
order by conname;

select tgname, tgdeferrable, tginitdeferred
from pg_trigger
where tgrelid in (
  'public.fidelizacion_operations'::regclass,
  'public.fidelizacion_redemptions'::regclass,
  'public.fidelizacion_point_movements'::regclass
)
  and tgname like 'fidelizacion_%_redeem_integridad_confirmada'
order by tgname;
