-- Solo lectura: contrato de alta manual atómica e idempotente del Issue #43.

select attname, atttypid::regtype as tipo, attnotnull
from pg_attribute
where attrelid = 'public.ventas'::regclass
  and attname = 'manual_idempotency_key'
  and not attisdropped;

select conname, contype, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conrelid = 'public.ventas'::regclass
  and conname = 'ventas_manual_idempotency_key_key';

select p.prosecdef as security_definer,
  coalesce(p.proconfig @> array['search_path='] or p.proconfig @> array['search_path=""'], false) as search_path_vacio,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute
from pg_proc p
where p.oid = to_regprocedure('public.crear_venta_manual(uuid,uuid,timestamp with time zone,text,jsonb,uuid)');
