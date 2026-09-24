-- Solo lectura: verifica la reconciliacion remota de los RPC cliente de Fase 5.

with esperadas(firma, security_definer, volatilidad) as (
  values
    ('app_private.fidelizacion_registrar_cuenta_cliente(text)', true, 'v'::char),
    ('public.fidelizacion_registrar_cuenta_cliente(text)', false, 'v'::char),
    ('app_private.fidelizacion_obtener_saldo_cliente(uuid)', true, 's'::char),
    ('public.fidelizacion_obtener_saldo_cliente(uuid)', false, 's'::char)
)
select
  e.firma,
  p.oid is not null as existe,
  p.prosecdef = e.security_definer as security_esperada,
  p.provolatile = e.volatilidad as volatilidad_esperada,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false)
    as search_path_vacio,
  coalesce(not has_function_privilege('public', p.oid, 'EXECUTE'), false)
    as public_sin_execute,
  coalesce(not has_function_privilege('anon', p.oid, 'EXECUTE'), false)
    as anon_sin_execute,
  coalesce(has_function_privilege('authenticated', p.oid, 'EXECUTE'), false)
    as authenticated_con_execute
from esperadas e
left join pg_proc p on p.oid = to_regprocedure(e.firma)
order by e.firma;

with esperadas(tabla) as (
  values
    ('fidelizacion_tenants'),
    ('fidelizacion_accounts'),
    ('fidelizacion_staff'),
    ('fidelizacion_rewards'),
    ('fidelizacion_operations'),
    ('fidelizacion_point_movements'),
    ('fidelizacion_redemptions')
)
select
  e.tabla,
  c.oid is not null as existe,
  coalesce(c.relrowsecurity, false) as rls_activa,
  coalesce(has_table_privilege('authenticated', c.oid, 'SELECT'), false)
    as authenticated_con_select,
  coalesce(not has_table_privilege('authenticated', c.oid, 'INSERT'), false)
    as authenticated_sin_insert,
  coalesce(not has_table_privilege('authenticated', c.oid, 'UPDATE'), false)
    as authenticated_sin_update,
  coalesce(not has_table_privilege('authenticated', c.oid, 'DELETE'), false)
    as authenticated_sin_delete,
  coalesce(not has_table_privilege('anon', c.oid, 'SELECT, INSERT, UPDATE, DELETE'), false)
    as anon_sin_crud
from esperadas e
left join pg_class c
  on c.oid = to_regclass('public.' || e.tabla)
order by e.tabla;

with esperadas(tabla, policy) as (
  values
    ('fidelizacion_tenants', 'fidelizacion_tenants_select_miembro'),
    ('fidelizacion_accounts', 'fidelizacion_accounts_select_propia_o_staff'),
    ('fidelizacion_staff', 'fidelizacion_staff_select_propia_o_admin'),
    ('fidelizacion_rewards', 'fidelizacion_rewards_select_cliente_o_staff'),
    ('fidelizacion_operations', 'fidelizacion_operations_select_propia_o_staff'),
    ('fidelizacion_point_movements', 'fidelizacion_point_movements_select_propio_o_staff'),
    ('fidelizacion_redemptions', 'fidelizacion_redemptions_select_propia_o_staff')
)
select
  e.tabla,
  e.policy,
  exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = e.tabla
      and p.policyname = e.policy
      and p.cmd = 'SELECT'
      and p.roles = array['authenticated'::name]
  ) as policy_select_authenticated_presente
from esperadas e
order by e.tabla;
