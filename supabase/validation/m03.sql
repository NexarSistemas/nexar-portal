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
                  'licencias_venta_item_id_fkey', 'licencias_venta_item_venta_fkey',
                  'licencias_producto_id_fkey', 'licencias_plan_id_fkey',
                  'comisiones_vendedor_id_fkey', 'comisiones_venta_id_fkey',
                  'comisiones_pago_id_fkey', 'comisiones_pago_venta_fkey')
order by conrelid::regclass::text, conname;

with atributos as (
  select
    (select attnum from pg_attribute where attrelid = 'public.venta_items'::regclass and attname = 'id' and not attisdropped) as item_id,
    (select attnum from pg_attribute where attrelid = 'public.venta_items'::regclass and attname = 'venta_id' and not attisdropped) as item_venta_id,
    (select attnum from pg_attribute where attrelid = 'public.licencias'::regclass and attname = 'venta_item_id' and not attisdropped) as licencia_item_id,
    (select attnum from pg_attribute where attrelid = 'public.licencias'::regclass and attname = 'venta_id' and not attisdropped) as licencia_venta_id,
    (select attnum from pg_attribute where attrelid = 'public.pagos'::regclass and attname = 'id' and not attisdropped) as pago_id,
    (select attnum from pg_attribute where attrelid = 'public.pagos'::regclass and attname = 'venta_id' and not attisdropped) as pago_venta_id,
    (select attnum from pg_attribute where attrelid = 'public.comisiones'::regclass and attname = 'pago_id' and not attisdropped) as comision_pago_id,
    (select attnum from pg_attribute where attrelid = 'public.comisiones'::regclass and attname = 'venta_id' and not attisdropped) as comision_venta_id
)
select
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'venta_items_id_venta_id_key'
      and c.conrelid = 'public.venta_items'::regclass and c.contype = 'u'
      and c.conkey = array[a.item_id, a.item_venta_id]::smallint[]
  ) as venta_items_tiene_unicidad_id_venta,
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'licencias_venta_item_venta_fkey'
      and c.conrelid = 'public.licencias'::regclass and c.confrelid = 'public.venta_items'::regclass
      and c.contype = 'f'
      and c.conkey = array[a.licencia_item_id, a.licencia_venta_id]::smallint[]
      and c.confkey = array[a.item_id, a.item_venta_id]::smallint[]
  ) as licencia_item_pertenece_a_venta,
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'pagos_id_venta_id_key'
      and c.conrelid = 'public.pagos'::regclass and c.contype = 'u'
      and c.conkey = array[a.pago_id, a.pago_venta_id]::smallint[]
  ) as pagos_tiene_unicidad_id_venta,
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'comisiones_pago_venta_fkey'
      and c.conrelid = 'public.comisiones'::regclass and c.confrelid = 'public.pagos'::regclass
      and c.contype = 'f'
      and c.conkey = array[a.comision_pago_id, a.comision_venta_id]::smallint[]
      and c.confkey = array[a.pago_id, a.pago_venta_id]::smallint[]
  ) as pago_corresponde_a_venta_de_comision;

select exists (
  select 1 from pg_index
  where indrelid = 'public.pagos'::regclass and indisunique
    and indexrelid::regclass::text = 'pagos_idempotency_key_uniq'
) as idempotencia_es_unica;
