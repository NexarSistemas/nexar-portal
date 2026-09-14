-- Solo lectura: perfiles, helpers y ausencia de provision prematura vinculada.
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'perfiles'
order by ordinal_position;

select n.nspname as esquema, p.proname, p.prosecdef as security_definer,
       pg_get_function_result(p.oid) as resultado
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'app_private'
  and p.proname in ('es_admin', 'vendedor_actual_id', 'es_vendedor_de_venta')
order by p.proname;

select count(*) as perfiles_vinculados_a_vendedor
from public.perfiles where vendedor_id is not null;
