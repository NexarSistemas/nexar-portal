-- Solo lectura: verifica que los creadores de operaciones asignen 15 minutos por defecto.
select
  p.oid::regprocedure as funcion,
  pg_get_functiondef(p.oid) like '%coalesce(%' as normaliza_expiracion,
  pg_get_functiondef(p.oid) like '%15 minutes%' as usa_quince_minutos
from pg_catalog.pg_proc p
where p.oid in (
  'app_private.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'::regprocedure,
  'app_private.fidelizacion_crear_redeem(uuid,text,timestamptz)'::regprocedure
)
order by funcion;
