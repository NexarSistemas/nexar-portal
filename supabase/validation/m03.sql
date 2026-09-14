-- Solo lectura: columnas/FKs canonicas agregadas a legacy y su integridad.
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (table_name, column_name) in (
    ('pagos', 'venta_id'), ('licencias', 'cliente_id'), ('licencias', 'venta_id'),
    ('licencias', 'venta_item_id'), ('comisiones', 'vendedor_id'),
    ('comisiones', 'venta_id'), ('comisiones', 'pago_id')
  )
order by table_name, column_name;

select conrelid::regclass as tabla, conname, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conname in ('pagos_venta_id_fkey', 'licencias_cliente_id_fkey', 'licencias_venta_id_fkey',
                  'licencias_venta_item_id_fkey', 'comisiones_vendedor_id_fkey',
                  'comisiones_venta_id_fkey', 'comisiones_pago_id_fkey')
order by tabla::text, conname;

select 'pagos' as tabla, count(*) as relaciones_huerfanas
from public.pagos p left join public.ventas v on v.id = p.venta_id
where p.venta_id is not null and v.id is null
union all
select 'licencias', count(*)
from public.licencias l left join public.clientes c on c.id = l.cliente_id
where l.cliente_id is not null and c.id is null;
