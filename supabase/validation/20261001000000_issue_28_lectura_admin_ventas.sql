-- Solo lectura: contrato de permisos y relaciones canónicas del Issue #28.

with esperadas(firma, security_definer) as (
  values
    ('app_private.licencias_admin_por_venta(uuid)', true),
    ('public.licencias_admin_por_venta(uuid)', false),
    ('app_private.comisiones_admin_por_venta(uuid)', true),
    ('public.comisiones_admin_por_venta(uuid)', false)
)
select e.firma,
  p.oid is not null as existe,
  p.prosecdef = e.security_definer as seguridad_esperada,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false) as search_path_vacio,
  coalesce(not has_function_privilege('public', p.oid, 'EXECUTE'), false) as public_sin_execute,
  coalesce(not has_function_privilege('anon', p.oid, 'EXECUTE'), false) as anon_sin_execute,
  coalesce(has_function_privilege('authenticated', p.oid, 'EXECUTE'), false) as authenticated_con_execute
from esperadas e
left join pg_proc p on p.oid = to_regprocedure(e.firma)
order by e.firma;

select conname, conrelid::regclass as tabla, confrelid::regclass as tabla_referenciada
from pg_constraint
where conname in ('licencias_venta_id_fkey', 'licencias_venta_item_venta_fkey', 'comisiones_venta_id_fkey', 'comisiones_pago_venta_fkey')
order by conname;
