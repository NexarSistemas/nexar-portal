-- Solo lectura: verifica el hardening de los RPC publicos de canje de Fase 6.
select
  p.oid::regprocedure as funcion,
  p.prosecdef as usa_security_definer,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_puede_ejecutar
from pg_catalog.pg_proc p
where p.oid in (
  'public.fidelizacion_crear_redeem(uuid,text,timestamptz)'::regprocedure,
  'public.fidelizacion_escanear_redeem(text,uuid)'::regprocedure,
  'public.fidelizacion_confirmar_redeem(uuid)'::regprocedure,
  'public.fidelizacion_cancelar_redeem(uuid)'::regprocedure
)
order by funcion;
