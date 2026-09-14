-- Solo lectura: preflight obligatorio antes de escribir el plan destructivo de M04.
select count(*) as vendedores_con_uuid
from public.vendedores
where id is not null;

-- Debe devolver exactamente una columna comercial candidata y una sola fila para RONA596.
-- No se ejecuta una busqueda heuristica aqui para no exponer valores de datos legacy.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'vendedores'
order by ordinal_position;

select to_regclass('public.precios_planes') is not null as precios_planes_coexiste;
