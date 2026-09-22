-- Solo lectura: valida el RPC minimo usado por el panel operador de Fidelizacion.

with esperadas(firma) as (
  values
    ('public.fidelizacion_buscar_cuenta_staff(text)'),
    ('app_private.fidelizacion_buscar_cuenta_staff(text)')
)
select firma as funcion_faltante
from esperadas
where to_regprocedure(firma) is null
order by firma;

select
  p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false)
    as search_path_vacio,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'app_private')
  and p.proname = 'fidelizacion_buscar_cuenta_staff'
order by n.nspname;

select
  pg_catalog.position('auth.uid()' in definicion) > 0 as deriva_identidad_auth,
  pg_catalog.position('public.fidelizacion_staff' in definicion) > 0 as valida_staff,
  pg_catalog.position('public.fidelizacion_tenants' in definicion) > 0 as valida_tenant,
  pg_catalog.position('auth.users' in definicion) > 0 as busca_email_en_auth,
  pg_catalog.position('public.fidelizacion_point_movements' in definicion) > 0 as deriva_saldo_del_ledger,
  pg_catalog.position('sum(m.puntos)' in definicion) > 0 as suma_movimientos,
  pg_catalog.position('public.perfiles' in definicion) = 0 as sin_perfiles,
  pg_catalog.position('public.clientes' in definicion) = 0 as sin_clientes_legacy
from (
  select pg_catalog.lower(
    pg_get_functiondef('app_private.fidelizacion_buscar_cuenta_staff(text)'::regprocedure)
  ) as definicion
) f;

select
  not has_table_privilege('authenticated', 'auth.users', 'SELECT')
    as authenticated_sin_select_auth_users;
