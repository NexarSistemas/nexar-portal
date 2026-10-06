-- Solo lectura: valida el contrato de operaciones pendientes vigentes para clientes.

with esperadas(firma) as (
  values
    ('public.fidelizacion_obtener_operaciones_pendientes(uuid)'),
    ('app_private.fidelizacion_obtener_operaciones_pendientes(uuid)')
)
select firma as funcion_faltante
from esperadas
where to_regprocedure(firma) is null
order by firma;

select
  p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  p.provolatile = 's' as estable,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false)
    as search_path_vacio,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'app_private')
  and p.proname = 'fidelizacion_obtener_operaciones_pendientes'
order by n.nspname;

select
  pg_catalog.position('auth.uid()' in definicion) > 0 as deriva_identidad_auth,
  pg_catalog.position('app_private.fidelizacion_es_cliente' in definicion) > 0
    as reutiliza_autorizacion_cliente,
  pg_catalog.position('pending_customer' in definicion) > 0
    and pg_catalog.position('pending_staff' in definicion) > 0 as limita_estados_pendientes,
  pg_catalog.position('pg_catalog.now()' in definicion) > 0 as usa_hora_postgresql,
  pg_catalog.position('o.expires_at is null or o.expires_at > pg_catalog.now()' in definicion) > 0
    as excluye_operaciones_vencidas,
  pg_catalog.position('order by o.created_at desc, o.id desc' in definicion) > 0
    as orden_estable,
  pg_catalog.position('public.perfiles' in definicion) = 0 as sin_perfiles,
  pg_catalog.position('auth.users' in definicion) = 0 as sin_lectura_auth_users
from (
  select pg_catalog.lower(
    pg_get_functiondef('app_private.fidelizacion_obtener_operaciones_pendientes(uuid)'::regprocedure)
  ) as definicion
) f;

select
  pg_get_function_identity_arguments(p.oid) = 'p_account_id uuid'
    as acepta_solo_cuenta,
  pg_get_function_result(p.oid) = 'table(id uuid, tipo text, estado text, puntos bigint, created_at timestamp with time zone, expires_at timestamp with time zone)'
    as retorna_solo_campos_ui
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'fidelizacion_obtener_operaciones_pendientes';
