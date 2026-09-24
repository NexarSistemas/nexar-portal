-- Solo lectura: detecta la calificacion invalida que produce 42883 al ejecutar los helpers.

select
  p.oid::regprocedure as helper,
  pg_get_functiondef(p.oid) not ilike '%pg_catalog.coalesce(%' as coalesce_resuelto_como_sintaxis_sql
from pg_catalog.pg_proc p
where p.oid in (
  'app_private.fidelizacion_buscar_cuenta_staff(text)'::regprocedure,
  'app_private.fidelizacion_obtener_saldo_cliente(uuid)'::regprocedure
)
order by helper;
