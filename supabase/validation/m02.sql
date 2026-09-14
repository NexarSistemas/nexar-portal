-- Solo lectura: ventas, items, snapshot e integridad referencial de M02.
select table_name, column_name, data_type, numeric_precision, numeric_scale
from information_schema.columns
where table_schema = 'public' and table_name in ('ventas', 'venta_items')
order by table_name, ordinal_position;

select c.conrelid::regclass as tabla, c.conname, pg_get_constraintdef(c.oid) as definicion
from pg_constraint c
where c.connamespace = 'public'::regnamespace
  and c.conrelid in ('public.ventas'::regclass, 'public.venta_items'::regclass)
order by tabla::text, c.conname;

select count(*) as items_sin_venta
from public.venta_items vi left join public.ventas v on v.id = vi.venta_id
where v.id is null;
