-- Solo lectura: contrato de permisos para las relaciones de clientes del Issue #27.

with esperadas(tabla, rls) as (
  values ('pagos', true), ('licencias', true)
)
select e.*, c.relrowsecurity as rls_encontrado, c.relrowsecurity = e.rls as correcto
from esperadas e
left join pg_class c on c.relnamespace = 'public'::regnamespace and c.relname = e.tabla
order by e.tabla;

select
  exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'pagos'
      and p.policyname = 'pagos_admin_select'
      and upper(p.cmd) = 'SELECT'
      and p.roles = array['authenticated'::name]
      and position('app_private.es_admin' in coalesce(p.qual, '')) > 0
      and position('vendedor_actual_id' in coalesce(p.qual, '')) = 0
  ) as pagos_admin_select_configurada;

select
  exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'licencias'
      and p.policyname = 'licencias_admin_select'
      and upper(p.cmd) = 'SELECT'
      and p.roles = array['authenticated'::name]
      and position('app_private.es_admin' in coalesce(p.qual, '')) > 0
  ) as licencias_admin_select_preservada;

select policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public'
  and tablename = 'pagos'
  and cmd = 'SELECT'
  and roles && array['public'::name, 'authenticated'::name]
  and policyname <> 'pagos_admin_select';

select
  has_table_privilege('authenticated', 'public.pagos', 'SELECT') as pagos_select_tabla_indebido,
  has_table_privilege('public', 'public.pagos', 'SELECT') as pagos_select_public_indebido,
  has_table_privilege('anon', 'public.pagos', 'SELECT') as pagos_select_anon_indebido;

with esperadas(tabla, columna) as (
  values
    ('pagos', 'id'), ('pagos', 'venta_id'), ('pagos', 'monto'), ('pagos', 'moneda'),
    ('pagos', 'proveedor_origen'), ('pagos', 'estado_proveedor'),
    ('pagos', 'decision_administrativa'), ('pagos', 'created_at'),
    ('licencias', 'license_key'), ('licencias', 'producto'), ('licencias', 'usuario'),
    ('licencias', 'plan'), ('licencias', 'plan_vendido'), ('licencias', 'expira'),
    ('licencias', 'created_at'), ('licencias', 'cliente_id')
), actuales as (
  select c.relname as tabla, a.attname as columna
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  where a.attrelid in ('public.pagos'::regclass, 'public.licencias'::regclass)
    and a.attnum > 0
    and not a.attisdropped
    and has_column_privilege('authenticated', a.attrelid, a.attname, 'SELECT')
)
select 'faltante' as diferencia, tabla, columna from (select * from esperadas except select * from actuales) d
union all
select 'indebida', tabla, columna from (select * from actuales except select * from esperadas) d
order by tabla, columna;

select c.column_name,
  has_column_privilege('authenticated', 'public.pagos', c.column_name, 'SELECT')
    as accesible_para_authenticated
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name = 'pagos'
  and c.column_name in (
    'raw_payload', 'init_point', 'sandbox_init_point', 'email', 'telefono',
    'license_key', 'external_reference', 'correlation_id', 'idempotency_key',
    'mercado_pago_id', 'payment_id'
  )
order by c.column_name;

select
  has_column_privilege('authenticated', 'public.licencias', 'cliente_id', 'SELECT')
    as licencia_cliente_id_seleccionable,
  not has_column_privilege('authenticated', 'public.licencias', 'venta_id', 'SELECT')
    as licencia_venta_id_no_seleccionable,
  not has_column_privilege('authenticated', 'public.licencias', 'venta_item_id', 'SELECT')
    as licencia_venta_item_id_no_seleccionable;

select conname, conrelid::regclass as tabla, confrelid::regclass as tabla_referenciada
from pg_constraint
where conname in ('pagos_venta_id_fkey', 'licencias_cliente_id_fkey')
order by conname;
