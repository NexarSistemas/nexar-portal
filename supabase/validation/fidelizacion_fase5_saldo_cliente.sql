-- Solo lectura: valida el contrato de saldo atomico para clientes de Fidelizacion.

with esperadas(firma) as (
  values
    ('public.fidelizacion_obtener_saldo_cliente(uuid)'),
    ('app_private.fidelizacion_obtener_saldo_cliente(uuid)')
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
  and p.proname = 'fidelizacion_obtener_saldo_cliente'
order by n.nspname;

select
  pg_catalog.position('auth.uid()' in definicion) > 0 as deriva_identidad_auth,
  pg_catalog.position('public.fidelizacion_accounts' in definicion) > 0 as valida_cuenta,
  pg_catalog.position('public.fidelizacion_tenants' in definicion) > 0 as valida_tenant,
  pg_catalog.position('a.user_id = v_user_id' in definicion) > 0 as valida_propiedad,
  pg_catalog.position('a.activo' in definicion) > 0 as valida_cuenta_activa,
  pg_catalog.position('t.activo' in definicion) > 0 as valida_tenant_activo,
  pg_catalog.position('public.fidelizacion_point_movements' in definicion) > 0 as deriva_saldo_del_ledger,
  pg_catalog.position('sum(m.puntos)' in definicion) > 0 as suma_movimientos,
  pg_catalog.position('public.perfiles' in definicion) = 0 as sin_perfiles,
  pg_catalog.position('auth.users' in definicion) = 0 as sin_lectura_auth_users
from (
  select pg_catalog.lower(
    pg_get_functiondef('app_private.fidelizacion_obtener_saldo_cliente(uuid)'::regprocedure)
  ) as definicion
) f;

select
  pg_get_function_identity_arguments(p.oid) = 'p_account_id uuid'
    as acepta_solo_cuenta,
  pg_get_function_result(p.oid) = 'numeric'
    as retorna_solo_saldo
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'fidelizacion_obtener_saldo_cliente';
