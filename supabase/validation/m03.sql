-- Solo lectura: relaciones y extensiones aditivas de M03 sobre legacy.
with esperadas(tabla, columna, tipo, admite_null) as (
  values
    ('pagos', 'venta_id', 'uuid', true), ('pagos', 'proveedor_origen', 'text', true),
    ('pagos', 'estado_proveedor', 'text', true), ('pagos', 'decision_administrativa', 'text', true),
    ('pagos', 'idempotency_key', 'text', true), ('pagos', 'correlation_id', 'uuid', true),
    ('licencias', 'cliente_id', 'uuid', true), ('licencias', 'venta_id', 'uuid', true),
    ('licencias', 'venta_item_id', 'uuid', true), ('licencias', 'producto_id', 'uuid', true),
    ('licencias', 'plan_id', 'uuid', true),
    ('comisiones', 'vendedor_id', 'uuid', true), ('comisiones', 'venta_id', 'uuid', true),
    ('comisiones', 'pago_id', 'uuid', true), ('comisiones', 'importe_historico', 'numeric', true)
)
select e.*, c.data_type as tipo_encontrado, c.is_nullable = 'YES' as admite_null_encontrado,
  c.data_type = e.tipo and (c.is_nullable = 'YES') = e.admite_null as correcto
from esperadas e
left join information_schema.columns c
  on c.table_schema = 'public' and c.table_name = e.tabla and c.column_name = e.columna
order by e.tabla, e.columna;

select conrelid::regclass as tabla, conname, confrelid::regclass as tabla_referenciada
from pg_constraint
where conname in ('pagos_venta_id_fkey', 'licencias_cliente_id_fkey', 'licencias_venta_id_fkey',
                  'licencias_venta_item_id_fkey', 'licencias_producto_id_fkey', 'licencias_plan_id_fkey',
                  'comisiones_vendedor_id_fkey', 'comisiones_venta_id_fkey', 'comisiones_pago_id_fkey')
order by conrelid::regclass::text, conname;

select exists (
  select 1 from pg_index
  where indrelid = 'public.pagos'::regclass and indisunique
    and indexrelid::regclass::text = 'pagos_idempotency_key_uniq'
) as idempotencia_es_unica;
