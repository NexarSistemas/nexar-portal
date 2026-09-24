-- Solo lectura: verifica la construccion SQL de la caducidad en ambos creadores.
select
  p.oid::regprocedure as funcion,
  pg_catalog.lower(pg_get_functiondef(p.oid)) like '%coalesce(%' as usa_coalesce,
  pg_catalog.lower(pg_get_functiondef(p.oid)) not like '%pg_catalog.coalesce(%' as evita_funcion_inexistente,
  pg_catalog.lower(pg_get_functiondef(p.oid)) like '%15 minutes%' as conserva_quince_minutos
from pg_catalog.pg_proc p
where p.oid in (
  'app_private.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'::regprocedure,
  'app_private.fidelizacion_crear_redeem(uuid,text,timestamptz)'::regprocedure
)
order by funcion;
