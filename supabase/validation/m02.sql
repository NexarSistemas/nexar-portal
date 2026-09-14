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

with atributos as (
  select
    (select attnum from pg_attribute where attrelid = 'public.venta_items'::regclass and attname = 'plan_id' and not attisdropped) as item_plan_id,
    (select attnum from pg_attribute where attrelid = 'public.venta_items'::regclass and attname = 'producto_id' and not attisdropped) as item_producto_id,
    (select attnum from pg_attribute where attrelid = 'public.venta_items'::regclass and attname = 'precio_id' and not attisdropped) as item_precio_id,
    (select attnum from pg_attribute where attrelid = 'public.planes'::regclass and attname = 'id' and not attisdropped) as plan_id,
    (select attnum from pg_attribute where attrelid = 'public.planes'::regclass and attname = 'producto_id' and not attisdropped) as plan_producto_id,
    (select attnum from pg_attribute where attrelid = 'public.precios'::regclass and attname = 'id' and not attisdropped) as precio_id,
    (select attnum from pg_attribute where attrelid = 'public.precios'::regclass and attname = 'plan_id' and not attisdropped) as precio_plan_id
)
select
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'planes_id_producto_id_key'
      and c.conrelid = 'public.planes'::regclass and c.contype = 'u'
      and c.conkey = array[a.plan_id, a.plan_producto_id]::smallint[]
  ) as planes_tiene_unicidad_para_fk_compuesta,
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'precios_id_plan_id_key'
      and c.conrelid = 'public.precios'::regclass and c.contype = 'u'
      and c.conkey = array[a.precio_id, a.precio_plan_id]::smallint[]
  ) as precios_tiene_unicidad_para_fk_compuesta,
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'venta_items_plan_producto_fkey'
      and c.conrelid = 'public.venta_items'::regclass and c.confrelid = 'public.planes'::regclass
      and c.contype = 'f'
      and c.conkey = array[a.item_plan_id, a.item_producto_id]::smallint[]
      and c.confkey = array[a.plan_id, a.plan_producto_id]::smallint[]
  ) as plan_pertenece_al_producto,
  exists (
    select 1 from pg_constraint c cross join atributos a
    where c.conname = 'venta_items_precio_plan_fkey'
      and c.conrelid = 'public.venta_items'::regclass and c.confrelid = 'public.precios'::regclass
      and c.contype = 'f'
      and c.conkey = array[a.item_precio_id, a.item_plan_id]::smallint[]
      and c.confkey = array[a.precio_id, a.precio_plan_id]::smallint[]
  ) as precio_pertenece_al_plan,
  exists (
    select 1 from pg_constraint
    where conname = 'venta_items_precio_requiere_plan_check'
      and conrelid = 'public.venta_items'::regclass and contype = 'c'
  ) as precio_requiere_plan;
