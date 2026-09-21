-- Solo lectura: valida RPC, privilegios, atomicidad e integridad de Fidelizacion Fase 2.

with esperadas(firma) as (
  values
    ('public.fidelizacion_crear_earn(uuid,bigint,text,timestamp with time zone)'),
    ('public.fidelizacion_obtener_earn_pendientes(text)'),
    ('public.fidelizacion_confirmar_earn(text,uuid)'),
    ('app_private.fidelizacion_crear_earn(uuid,bigint,text,timestamp with time zone)'),
    ('app_private.fidelizacion_obtener_earn_pendientes(text)'),
    ('app_private.fidelizacion_confirmar_earn(text,uuid)')
)
select firma as funcion_faltante
from esperadas
where to_regprocedure(firma) is null
order by firma;

select
  p.oid::regprocedure as funcion,
  not p.prosecdef as security_invoker,
  coalesce(
    p.proconfig @> array['search_path=']
      or p.proconfig @> array['search_path=""'],
    false
  ) as search_path_vacio,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute,
  pg_catalog.position('app_private.' in pg_get_functiondef(p.oid)) > 0 as delega_en_schema_privado
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'fidelizacion_crear_earn',
    'fidelizacion_obtener_earn_pendientes',
    'fidelizacion_confirmar_earn'
  )
order by p.proname;

select
  p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  coalesce(
    p.proconfig @> array['search_path=']
      or p.proconfig @> array['search_path=""'],
    false
  ) as search_path_vacio,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute,
  pg_catalog.position('auth.uid()' in pg_get_functiondef(p.oid)) > 0 as deriva_identidad_auth,
  pg_catalog.position('public.perfiles' in pg_get_functiondef(p.oid)) = 0 as sin_perfiles
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'app_private'
  and p.proname in (
    'fidelizacion_crear_earn',
    'fidelizacion_obtener_earn_pendientes',
    'fidelizacion_confirmar_earn'
  )
order by p.proname;

select
  pg_catalog.position('fidelizacion_staff' in definicion) > 0 as valida_staff,
  pg_catalog.position('fidelizacion_accounts' in definicion) > 0 as valida_cuenta,
  pg_catalog.position('fidelizacion_tenants' in definicion) > 0 as valida_tenant,
  pg_catalog.position('on conflict on constraint fidelizacion_operations_tenant_idempotency_key_key' in definicion) > 0
    as idempotencia_con_constraint,
  pg_catalog.position('pending_customer' in definicion) > 0 as crea_pending_customer
from (
  select pg_catalog.lower(pg_get_functiondef(
    'app_private.fidelizacion_crear_earn(uuid,bigint,text,timestamp with time zone)'::regprocedure
  )) as definicion
) f;

select
  pg_catalog.position('public_qr_code' in definicion) > 0 as qr_resuelve_tenant,
  pg_catalog.position('pending_customer' in definicion) > 0 as solo_pendientes,
  pg_catalog.position('fidelizacion_point_movements' in definicion) > 0 as descarta_movimiento_existente,
  pg_catalog.position('insert into' in definicion) = 0 as resolver_sin_insert,
  pg_catalog.position('update ' in definicion) = 0 as resolver_sin_update,
  pg_catalog.position('delete ' in definicion) = 0 as resolver_sin_delete
from (
  select pg_catalog.lower(pg_get_functiondef(
    'app_private.fidelizacion_obtener_earn_pendientes(text)'::regprocedure
  )) as definicion
) f;

select
  pg_catalog.position('public_qr_code' in definicion) > 0 as valida_qr,
  pg_catalog.position('fidelizacion_accounts' in definicion) > 0 as valida_cuenta_cliente,
  pg_catalog.position('for update' in definicion) > 0 as bloquea_operacion,
  pg_catalog.position('fidelizacion_point_movements' in definicion) > 0 as crea_movimiento,
  pg_catalog.position('set estado = ''confirmed''' in definicion) > 0 as confirma_operacion,
  pg_catalog.position('sum(m.puntos)' in definicion) > 0 as saldo_derivado
from (
  select pg_catalog.lower(pg_get_functiondef(
    'app_private.fidelizacion_confirmar_earn(text,uuid)'::regprocedure
  )) as definicion
) f;

select
  conname,
  contype,
  pg_get_constraintdef(oid) as definicion
from pg_constraint
where conrelid = 'public.fidelizacion_point_movements'::regclass
  and conname in (
    'fidelizacion_point_movements_operation_fkey',
    'fidelizacion_point_movements_operation_id_key'
  )
order by conname;

select
  has_table_privilege('authenticated', 'public.fidelizacion_operations', 'INSERT')
    or has_table_privilege('authenticated', 'public.fidelizacion_operations', 'UPDATE')
    or has_table_privilege('authenticated', 'public.fidelizacion_operations', 'DELETE')
    as authenticated_escribe_operaciones_directamente,
  has_table_privilege('authenticated', 'public.fidelizacion_point_movements', 'INSERT')
    or has_table_privilege('authenticated', 'public.fidelizacion_point_movements', 'UPDATE')
    or has_table_privilege('authenticated', 'public.fidelizacion_point_movements', 'DELETE')
    as authenticated_escribe_movimientos_directamente;

select column_name as saldo_mutable_indebido
from information_schema.columns
where table_schema = 'public'
  and table_name = 'fidelizacion_accounts'
  and column_name in ('saldo', 'balance', 'puntos');
