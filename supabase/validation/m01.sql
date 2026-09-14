-- Solo lectura: contrato verificable de clientes y catalogo de M01.
with esperadas(tabla, columna, tipo, admite_null) as (
  values
    ('clientes', 'id', 'uuid', false), ('clientes', 'email', 'text', true),
    ('productos', 'id', 'uuid', false), ('productos', 'codigo', 'text', false),
    ('planes', 'producto_id', 'uuid', false),
    ('precios', 'plan_id', 'uuid', false), ('precios', 'moneda', 'text', false),
    ('precios', 'importe', 'numeric', false),
    ('precios', 'modalidad_cobro', 'text', false), ('precios', 'estado', 'text', false),
    ('precios', 'vigente_desde', 'timestamp with time zone', false),
    ('precios', 'vigente_hasta', 'timestamp with time zone', true)
)
select e.*, c.data_type as tipo_encontrado, c.is_nullable = 'YES' as admite_null_encontrado,
  c.data_type = e.tipo and (c.is_nullable = 'YES') = e.admite_null as correcto
from esperadas e
left join information_schema.columns c
  on c.table_schema = 'public' and c.table_name = e.tabla and c.column_name = e.columna
order by e.tabla, e.columna;

select
  exists (select 1 from pg_constraint where conrelid = 'public.precios'::regclass
    and contype = 'f' and confrelid = 'public.planes'::regclass) as precio_tiene_fk_plan,
  exists (select 1 from pg_constraint where conrelid = 'public.precios'::regclass
    and contype = 'c' and pg_get_constraintdef(oid) like '%modalidad_cobro%') as modalidad_tiene_check,
  exists (select 1 from pg_constraint where conrelid = 'public.precios'::regclass
    and contype = 'c' and pg_get_constraintdef(oid) like '%estado%') as estado_tiene_check,
  exists (select 1 from pg_constraint where conrelid = 'public.precios'::regclass
    and contype = 'c' and pg_get_constraintdef(oid) like '%vigente_hasta%') as vigencia_tiene_check;

select not exists (
  select 1
  from pg_index i
  join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
  where i.indrelid = 'public.clientes'::regclass
    and i.indisunique and i.indnkeyatts = 1 and a.attname = 'email'
) as email_no_es_unico;
