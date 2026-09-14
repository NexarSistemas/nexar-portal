-- Solo lectura: precondiciones legacy de M00.
with esperadas(tabla) as (
  values ('vendedores'), ('pagos'), ('licencias'), ('comisiones'), ('precios_planes'),
         ('referidos'), ('portal_vendedor_sessions'), ('admin_audit_log')
)
select tabla, to_regclass(format('public.%I', tabla)) is not null as existe
from esperadas order by tabla;

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (table_name, column_name) in (('vendedores', 'id'), ('pagos', 'id'))
order by table_name;
