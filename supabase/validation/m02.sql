-- Solo lectura: contrato verificable de ventas y snapshots de M02.
with esperadas(tabla, columna, tipo, admite_null) as (
  values
    ('ventas', 'cliente_id', 'uuid', false), ('ventas', 'vendedor_id', 'uuid', true),
    ('ventas', 'fecha_venta', 'timestamp with time zone', false),
    ('ventas', 'moneda', 'text', false), ('ventas', 'estado', 'text', false),
    ('ventas', 'importe_total', 'numeric', false),
    ('venta_items', 'venta_id', 'uuid', false), ('venta_items', 'producto_id', 'uuid', false),
    ('venta_items', 'plan_id', 'uuid', true), ('venta_items', 'precio_id', 'uuid', true),
    ('venta_items', 'descripcion', 'text', false), ('venta_items', 'cantidad', 'numeric', false),
    ('venta_items', 'precio_unitario', 'numeric', false),
    ('venta_items', 'importe_total', 'numeric', false)
)
select e.*, c.data_type as tipo_encontrado, c.is_nullable = 'YES' as admite_null_encontrado,
  c.data_type = e.tipo and (c.is_nullable = 'YES') = e.admite_null as correcto
from esperadas e
left join information_schema.columns c
  on c.table_schema = 'public' and c.table_name = e.tabla and c.column_name = e.columna
order by e.tabla, e.columna;

select
  exists (select 1 from pg_constraint where conrelid = 'public.venta_items'::regclass
    and contype = 'f' and confrelid = 'public.ventas'::regclass) as item_tiene_fk_venta,
  exists (select 1 from pg_constraint where conrelid = 'public.venta_items'::regclass
    and contype = 'f' and confrelid = 'public.productos'::regclass) as item_tiene_fk_producto,
  exists (select 1 from pg_constraint where conrelid = 'public.venta_items'::regclass
    and contype = 'f' and confrelid = 'public.planes'::regclass) as item_tiene_fk_plan,
  exists (select 1 from pg_constraint where conrelid = 'public.venta_items'::regclass
    and contype = 'f' and confrelid = 'public.precios'::regclass) as item_tiene_fk_precio,
  exists (select 1 from pg_constraint where conrelid = 'public.ventas'::regclass
    and contype = 'c' and pg_get_constraintdef(oid) like '%estado%') as venta_estado_tiene_check;

select not exists (
  select 1 from pg_constraint
  where conrelid = 'public.venta_items'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) like '%producto_id%'
    and pg_get_constraintdef(oid) like '%plan_id%'
    and pg_get_constraintdef(oid) like '%precio_id%'
    and pg_get_constraintdef(oid) like '%IS NULL%'
) as plan_y_precio_no_estan_forzados_en_bloque;
