-- Solo lectura: entidades, tipos, FKs, unicidad e indices de M01.
select table_name, column_name, data_type, numeric_precision, numeric_scale
from information_schema.columns
where table_schema = 'public'
  and table_name in ('clientes', 'productos', 'planes', 'precios')
order by table_name, ordinal_position;

select c.conrelid::regclass as tabla, c.conname, c.contype, pg_get_constraintdef(c.oid) as definicion
from pg_constraint c
where c.connamespace = 'public'::regnamespace
  and c.conrelid in ('public.clientes'::regclass, 'public.productos'::regclass,
                     'public.planes'::regclass, 'public.precios'::regclass)
order by tabla::text, c.conname;

select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('clientes', 'productos', 'planes', 'precios')
order by tablename, indexname;
