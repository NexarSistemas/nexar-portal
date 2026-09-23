-- Solo lectura: valida el contrato de registro seguro de clientes de Fidelizacion.

with esperadas(firma) as (
  values
    ('public.fidelizacion_registrar_cuenta_cliente(text)'),
    ('app_private.fidelizacion_registrar_cuenta_cliente(text)')
)
select firma as funcion_faltante
from esperadas
where to_regprocedure(firma) is null
order by firma;

select
  p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  p.provolatile = 'v' as volatil,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false)
    as search_path_vacio,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'app_private')
  and p.proname = 'fidelizacion_registrar_cuenta_cliente'
order by n.nspname;

select
  pg_catalog.position('auth.uid()' in definicion) > 0 as deriva_identidad_auth,
  pg_catalog.position('public.fidelizacion_tenants' in definicion) > 0 as resuelve_tenant_por_qr,
  pg_catalog.position('public.fidelizacion_accounts' in definicion) > 0 as crea_cuenta,
  pg_catalog.position('fidelizacion_accounts_tenant_user_key' in definicion) > 0
    as usa_unicidad_existente,
  pg_catalog.position('public.perfiles' in definicion) = 0 as sin_perfiles,
  pg_catalog.position('public.fidelizacion_staff' in definicion) = 0 as sin_staff,
  pg_catalog.position('auth.users' in definicion) = 0 as sin_lectura_auth_users
from (
  select pg_catalog.lower(
    pg_get_functiondef(
      'app_private.fidelizacion_registrar_cuenta_cliente(text)'::regprocedure
    )
  ) as definicion
) f;

select
  not has_table_privilege('authenticated', 'public.fidelizacion_accounts', 'INSERT')
    as authenticated_sin_insert_cuentas,
  has_table_privilege('authenticated', 'public.fidelizacion_accounts', 'SELECT')
    as authenticated_con_select_cuentas;

select
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.fidelizacion_accounts'::regclass
      and conname = 'fidelizacion_accounts_tenant_user_key'
      and contype = 'u'
  ) as unicidad_tenant_usuario_presente;

select
  pg_get_function_identity_arguments(p.oid) = 'p_public_qr_code text'
    as acepta_solo_qr_publico,
  pg_get_function_result(p.oid) = 'TABLE(account_id uuid, tenant_id uuid)'
    as retorno_minimo
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'fidelizacion_registrar_cuenta_cliente';
