-- Solo lectura: valida el contrato invoker entre wrappers publicos y helpers privados.

with esperadas(firma) as (
  values
    ('public.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'),
    ('app_private.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'),
    ('public.fidelizacion_obtener_earn_pendientes(text)'),
    ('app_private.fidelizacion_obtener_earn_pendientes(text)'),
    ('public.fidelizacion_confirmar_earn(text,uuid)'),
    ('app_private.fidelizacion_confirmar_earn(text,uuid)'),
    ('public.fidelizacion_crear_redeem(uuid,text,timestamptz)'),
    ('app_private.fidelizacion_crear_redeem(uuid,text,timestamptz)'),
    ('public.fidelizacion_escanear_redeem(text,uuid)'),
    ('app_private.fidelizacion_escanear_redeem(text,uuid)'),
    ('public.fidelizacion_confirmar_redeem(uuid)'),
    ('app_private.fidelizacion_confirmar_redeem(uuid)'),
    ('public.fidelizacion_cancelar_redeem(uuid)'),
    ('app_private.fidelizacion_cancelar_redeem(uuid)'),
    ('public.fidelizacion_buscar_cuenta_staff(text)'),
    ('app_private.fidelizacion_buscar_cuenta_staff(text)'),
    ('public.fidelizacion_registrar_cuenta_cliente(text)'),
    ('app_private.fidelizacion_registrar_cuenta_cliente(text)'),
    ('public.fidelizacion_obtener_saldo_cliente(uuid)'),
    ('app_private.fidelizacion_obtener_saldo_cliente(uuid)')
)
select firma as funcion_faltante
from esperadas
where to_regprocedure(firma) is null
order by firma;

select
  has_schema_privilege('authenticated', 'app_private', 'USAGE') as authenticated_tiene_usage_privado,
  not has_schema_privilege('anon', 'app_private', 'USAGE') as anon_sin_usage_privado,
  not has_schema_privilege('public', 'app_private', 'USAGE') as public_sin_usage_privado;

with esperadas(firma) as (
  values
    ('public.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'),
    ('app_private.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'),
    ('public.fidelizacion_obtener_earn_pendientes(text)'),
    ('app_private.fidelizacion_obtener_earn_pendientes(text)'),
    ('public.fidelizacion_confirmar_earn(text,uuid)'),
    ('app_private.fidelizacion_confirmar_earn(text,uuid)'),
    ('public.fidelizacion_crear_redeem(uuid,text,timestamptz)'),
    ('app_private.fidelizacion_crear_redeem(uuid,text,timestamptz)'),
    ('public.fidelizacion_escanear_redeem(text,uuid)'),
    ('app_private.fidelizacion_escanear_redeem(text,uuid)'),
    ('public.fidelizacion_confirmar_redeem(uuid)'),
    ('app_private.fidelizacion_confirmar_redeem(uuid)'),
    ('public.fidelizacion_cancelar_redeem(uuid)'),
    ('app_private.fidelizacion_cancelar_redeem(uuid)'),
    ('public.fidelizacion_buscar_cuenta_staff(text)'),
    ('app_private.fidelizacion_buscar_cuenta_staff(text)'),
    ('public.fidelizacion_registrar_cuenta_cliente(text)'),
    ('app_private.fidelizacion_registrar_cuenta_cliente(text)'),
    ('public.fidelizacion_obtener_saldo_cliente(uuid)'),
    ('app_private.fidelizacion_obtener_saldo_cliente(uuid)')
)
select
  e.firma as funcion,
  n.nspname = 'app_private' as helper_privado,
  p.prosecdef = (n.nspname = 'app_private') as seguridad_esperada,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false)
    as search_path_vacio,
  coalesce(not has_function_privilege('public', p.oid, 'EXECUTE'), false) as public_sin_execute,
  coalesce(not has_function_privilege('anon', p.oid, 'EXECUTE'), false) as anon_sin_execute,
  coalesce(has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) as authenticated_con_execute
from esperadas e
left join pg_catalog.pg_proc p on p.oid = to_regprocedure(e.firma)
left join pg_catalog.pg_namespace n on n.oid = p.pronamespace
order by e.firma;

select
  p.oid::regprocedure as wrapper,
  pg_get_function_identity_arguments(p.oid) as argumentos_json_esperados
from pg_catalog.pg_proc p
where p.oid in (
  'public.fidelizacion_buscar_cuenta_staff(text)'::regprocedure,
  'public.fidelizacion_registrar_cuenta_cliente(text)'::regprocedure,
  'public.fidelizacion_obtener_saldo_cliente(uuid)'::regprocedure
)
order by wrapper;
