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
), esperados(tabla, grantee, privilegio) as (
  select tabla, 'authenticated'::name, privilegio
  from tablas cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) p(privilegio)
), actuales as (
  select c.relname as tabla, r.rolname::name as grantee,
    upper(a.privilege_type)::text as privilegio
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
  join pg_roles r on r.oid = a.grantee
  where n.nspname = 'public'
    and c.relname in (select tabla from tablas)
    and r.rolname in ('anon', 'authenticated')
)
select 'faltante' as diferencia, * from (select * from esperados except select * from actuales) d
union all
select 'inesperado', * from (select * from actuales except select * from esperados) d
order by tabla, grantee, privilegio;

select not exists (
  select 1 from pg_policies
  where schemaname = 'public'
    and policyname in ('pagos_admin_total', 'pagos_select_vendedor_propietario',
                       'licencias_admin_total', 'licencias_select_vendedor_propietario',
                       'comisiones_admin_total', 'comisiones_select_vendedor_propietario')
) as legacy_no_recibe_policies_de_m06;

select not exists (
  select 1 from pg_policies
  where schemaname = 'public'
    and tablename = 'solicitudes_upgrade'
    and policyname = 'allow admin read'
) as allow_admin_read_legacy_retirada;

select policyname, cmd, roles, permissive,
  position('es_admin' in coalesce(qual, '')) > 0 as usa_es_admin
from pg_policies
where schemaname = 'public'
  and tablename = 'solicitudes_upgrade'
  and policyname = 'solicitudes_upgrade_admin_select';

select exists (
  select 1
  from pg_policies
  where schemaname = 'public'
    and tablename = 'solicitudes_upgrade'
    and policyname = 'solicitudes_upgrade_admin_select'
    and cmd = 'SELECT'
    and cardinality(roles) = 1
    and roles[1] = 'authenticated'::name
    and position('es_admin' in coalesce(qual, '')) > 0
) as lectura_administrativa_authenticated_configurada;

select exists (
  select 1
  from pg_policies
  where schemaname = 'public'
    and tablename = 'solicitudes_upgrade'
    and cmd = 'INSERT'
    and 'anon' = any(roles)
) as insercion_anon_legacy_preservada;
