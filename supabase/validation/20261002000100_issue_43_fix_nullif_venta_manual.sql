-- Solo lectura: valida la corrección del Issue #43 sobre NULLIF.

select
  pg_get_functiondef(p.oid) not like '%pg_catalog.nullif%' as sin_nullif_invalido,
  pg_get_functiondef(p.oid) like '%nullif(v_item ->> ''producto_id'', '''')%' as valida_producto_vacio,
  pg_get_functiondef(p.oid) like '%nullif(v_item ->> ''plan_id'', '''')%' as valida_plan_vacio,
  not p.prosecdef as security_invoker,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false) as search_path_vacio,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute
from pg_proc p
where p.oid = to_regprocedure('public.crear_venta_manual(uuid,uuid,timestamp with time zone,text,jsonb,uuid)');
