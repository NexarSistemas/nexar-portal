-- Solo lectura: RLS/grants/policies exactos para tablas nuevas; legacy queda intacto.
with esperadas(tabla, rls) as (
  values
    ('perfiles', true), ('clientes', true), ('productos', true), ('planes', true),
    ('precios', true), ('ventas', true), ('venta_items', true)
)
select e.*, c.relrowsecurity as rls_encontrado, c.relrowsecurity = e.rls as correcto
from esperadas e
left join pg_class c on c.relnamespace = 'public'::regnamespace and c.relname = e.tabla
order by e.tabla;

select c.relname as tabla_legacy, c.relrowsecurity as rls_informativo
from pg_class c
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('pagos', 'licencias', 'comisiones')
order by c.relname;

with esperadas(tabla, policyname, cmd) as (
  values
    ('perfiles', 'perfiles_select_propio', 'SELECT'), ('perfiles', 'perfiles_admin_total', 'ALL'),
    ('clientes', 'clientes_admin_total', 'ALL'), ('clientes', 'clientes_select_vendedor_propietario', 'SELECT'),
    ('productos', 'productos_select_autenticado', 'SELECT'), ('productos', 'productos_admin_total', 'ALL'),
    ('planes', 'planes_select_autenticado', 'SELECT'), ('planes', 'planes_admin_total', 'ALL'),
    ('precios', 'precios_select_autenticado', 'SELECT'), ('precios', 'precios_admin_total', 'ALL'),
    ('ventas', 'ventas_admin_total', 'ALL'), ('ventas', 'ventas_select_vendedor_propietario', 'SELECT'),
    ('venta_items', 'venta_items_admin_total', 'ALL'), ('venta_items', 'venta_items_select_vendedor_propietario', 'SELECT')
), actuales as (
  select tablename as tabla, policyname, upper(cmd) as cmd
  from pg_policies where schemaname = 'public'
)
select 'faltante' as diferencia, * from (select * from esperadas except select * from actuales) d
union all
select 'inesperada', * from (select * from actuales where tabla in ('perfiles', 'clientes', 'productos', 'planes', 'precios', 'ventas', 'venta_items') except select * from esperadas) d
order by tabla, policyname;

with tablas(tabla) as (
  values ('perfiles'), ('clientes'), ('productos'), ('planes'), ('precios'), ('ventas'), ('venta_items')
), esperados as (
  select tabla, privilegio
  from tablas cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) p(privilegio)
), actuales as (
  select table_name as tabla, privilege_type as privilegio
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'authenticated'
)
select 'faltante' as diferencia, * from (select * from esperados except select * from actuales) d
union all
select 'inesperado', * from (select * from actuales where tabla in (select tabla from tablas) except select * from esperados) d
order by tabla, privilegio;

select not exists (
  select 1 from pg_policies
  where schemaname = 'public'
    and policyname in ('pagos_admin_total', 'pagos_select_vendedor_propietario',
                       'licencias_admin_total', 'licencias_select_vendedor_propietario',
                       'comisiones_admin_total', 'comisiones_select_vendedor_propietario')
) as legacy_no_recibe_policies_de_m06;
