-- Solo lectura: RLS, policies, grants e indices usados por ownership.
select c.relname as tabla, c.relrowsecurity as rls_habilitado
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in ('perfiles', 'clientes', 'productos', 'planes', 'precios', 'ventas',
                    'venta_items', 'pagos', 'licencias', 'comisiones')
order by c.relname;

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('perfiles', 'clientes', 'productos', 'planes', 'precios', 'ventas',
                    'venta_items', 'pagos', 'licencias', 'comisiones')
order by tablename, policyname;

select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'authenticated'
  and table_name in ('perfiles', 'clientes', 'productos', 'planes', 'precios', 'ventas',
                     'venta_items', 'pagos', 'licencias', 'comisiones')
order by table_name, privilege_type;
