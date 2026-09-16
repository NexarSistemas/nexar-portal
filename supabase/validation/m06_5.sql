-- Solo lectura: contrato Auth+RLS transicional de M06.5; no ejecuta M07.

with esperadas(tabla, rls) as (
  values ('vendedores', true), ('licencias', true), ('comisiones', true)
)
select e.*, c.relrowsecurity as rls_encontrado, c.relrowsecurity = e.rls as correcto
from esperadas e
left join pg_class c on c.relnamespace = 'public'::regnamespace and c.relname = e.tabla
order by e.tabla;

select p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  p.proconfig @> array['search_path=pg_catalog, public'] as search_path_seguro,
  position('auth.uid' in lower(pg_get_functiondef(p.oid))) > 0 as usa_auth_uid,
  position('public.perfiles' in lower(pg_get_functiondef(p.oid))) > 0 as usa_perfiles,
  position('public.vendedores' in lower(pg_get_functiondef(p.oid))) > 0 as resuelve_codigo_desde_vendedor,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_no_puede_ejecutar
from pg_proc p
where p.oid = 'app_private.codigo_vendedor_actual()'::regprocedure;

with esperadas(tabla, policyname, cmd) as (
  values
    ('vendedores', 'vendedores_admin_select', 'SELECT'),
    ('vendedores', 'vendedores_select_vendedor_propio', 'SELECT'),
    ('vendedores', 'vendedores_update_vendedor_propio', 'UPDATE'),
    ('licencias', 'licencias_admin_select', 'SELECT'),
    ('licencias', 'licencias_select_vendedor_propietario', 'SELECT'),
    ('comisiones', 'comisiones_admin_select', 'SELECT'),
    ('comisiones', 'comisiones_select_vendedor_propietario', 'SELECT')
), actuales as (
  select tablename as tabla, policyname, upper(cmd) as cmd
  from pg_policies
  where schemaname = 'public'
)
select 'faltante' as diferencia, * from (select * from esperadas except select * from actuales) d
union all
select 'incorrecta' as diferencia, p.tablename, p.policyname, upper(p.cmd)
from pg_policies p
join esperadas e on e.tabla = p.tablename and e.policyname = p.policyname
where p.schemaname = 'public'
  and (p.roles <> array['authenticated'::name] or upper(p.cmd) <> e.cmd)
order by tabla, policyname;

select tablename, policyname, cmd, roles,
  qual as using_expresion, with_check as with_check_expresion
from pg_policies
where schemaname = 'public'
  and policyname in (
    'vendedores_admin_select', 'vendedores_select_vendedor_propio',
    'vendedores_update_vendedor_propio', 'licencias_admin_select',
    'licencias_select_vendedor_propietario', 'comisiones_admin_select',
    'comisiones_select_vendedor_propietario'
  )
order by tablename, policyname;

select policyname,
  position('es_admin' in coalesce(qual, '')) > 0 as usa_admin_auth,
  position('vendedor_actual_id' in coalesce(qual, '')) > 0 as usa_vendedor_auth,
  position('es_vendedor_de_venta' in coalesce(qual, '')) > 0 as usa_venta_canonica,
  position('codigo_vendedor_actual' in coalesce(qual, '')) > 0 as usa_fallback_legacy_acotado,
  position('venta_id is null' in coalesce(qual, '')) > 0 as fallback_solo_sin_venta,
  position('vendedor_actual_id' in coalesce(with_check, '')) > 0 as conserva_ownership_en_update
from pg_policies
where schemaname = 'public'
  and policyname in (
    'vendedores_admin_select', 'vendedores_select_vendedor_propio',
    'vendedores_update_vendedor_propio', 'licencias_admin_select',
    'licencias_select_vendedor_propietario', 'comisiones_admin_select',
    'comisiones_select_vendedor_propietario'
  )
order by policyname;

select
  has_table_privilege('authenticated', 'public.vendedores', 'SELECT') as vendedores_select_tabla_indebido,
  has_table_privilege('authenticated', 'public.licencias', 'SELECT') as licencias_select_concedido,
  has_table_privilege('authenticated', 'public.comisiones', 'SELECT') as comisiones_select_concedido;

with tablas(tabla) as (
  values ('vendedores'), ('licencias'), ('comisiones')
), privilegios(privilegio) as (
  values ('INSERT'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('UPDATE')
)
select t.tabla, p.privilegio,
  has_table_privilege('authenticated', format('public.%I', t.tabla), p.privilegio) as concedido
from tablas t cross join privilegios p
order by t.tabla, p.privilegio;

with columnas as (
  select c.table_name as tabla, c.column_name as columna
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name in ('vendedores', 'licencias', 'comisiones')
), privilegios(privilegio) as (
  values ('INSERT'), ('REFERENCES'), ('UPDATE')
)
select c.tabla, c.columna, p.privilegio
from columnas c cross join privilegios p
where not (
    c.tabla = 'vendedores'
    and c.columna in ('email', 'telefono', 'alias_cbu')
    and p.privilegio = 'UPDATE'
  )
  and has_column_privilege('authenticated', format('public.%I', c.tabla), c.columna, p.privilegio)
order by c.tabla, c.columna, p.privilegio;

with esperadas(columna) as (
  values ('id'), ('codigo_vendedor'), ('email'), ('telefono'), ('alias_cbu')
), actuales as (
  select a.attname as columna
  from pg_attribute a
  where a.attrelid = 'public.vendedores'::regclass
    and a.attnum > 0
    and not a.attisdropped
    and has_column_privilege('authenticated', 'public.vendedores', a.attname, 'SELECT')
)
select 'faltante' as diferencia, columna from (select * from esperadas except select * from actuales) d
union all
select 'indebida' as diferencia, columna from (select * from actuales except select * from esperadas) d
order by columna;

with esperadas(columna) as (
  values ('email'), ('telefono'), ('alias_cbu')
), actuales as (
  select a.attname as columna
  from pg_attribute a
  where a.attrelid = 'public.vendedores'::regclass
    and a.attnum > 0
    and not a.attisdropped
    and has_column_privilege('authenticated', 'public.vendedores', a.attname, 'UPDATE')
)
select 'faltante' as diferencia, columna from (select * from esperadas except select * from actuales) d
union all
select 'indebida' as diferencia, columna from (select * from actuales except select * from esperadas) d
order by columna;

select columna,
  not has_column_privilege('authenticated', 'public.vendedores', columna, 'SELECT') as no_seleccionable
from (values ('password_hash'), ('password_change_required'), ('ultimo_login')) sensibles(columna)
order by columna;

select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and tablename in ('vendedores', 'licencias', 'comisiones')
  and roles && array['public'::name, 'authenticated'::name]
  and policyname not in (
    'vendedores_admin_select', 'vendedores_select_vendedor_propio',
    'vendedores_update_vendedor_propio', 'licencias_admin_select',
    'licencias_select_vendedor_propietario', 'comisiones_admin_select',
    'comisiones_select_vendedor_propietario'
  )
order by tablename, policyname;

select count(*) = 6 as seis_policies_portal_secret_preservadas
from pg_policies
where schemaname = 'public' and policyname like 'portal_secret_%';

select tablename, policyname, cmd, roles, permissive, qual, with_check
from pg_policies
where schemaname = 'public' and policyname like 'portal_secret_%'
order by tablename, policyname;

select to_regclass('public.portal_vendedor_sessions') is not null as sesiones_legacy_existen,
       to_regclass('public.portal_password_recovery_requests') is not null as recuperacion_legacy_existe,
       exists (select 1 from pg_proc where oid = 'public.portal_dashboard_vendedor(text)'::regprocedure)
         as dashboard_legacy_existe,
       (select prosecdef from pg_proc where oid = 'public.portal_dashboard_vendedor(text)'::regprocedure)
         as dashboard_legacy_security_definer;

with esperadas(columna) as (
  values ('password_hash'), ('password_change_required'), ('ultimo_login'), ('es_admin')
), actuales as (
  select column_name as columna
  from information_schema.columns
  where table_schema = 'public' and table_name = 'vendedores'
)
select 'faltante' as diferencia, columna
from (select * from esperadas except select * from actuales) d
union all
select 'inesperada' as diferencia, columna
from (select * from actuales where columna in ('password_hash', 'password_change_required', 'ultimo_login', 'es_admin') except select * from esperadas) d
order by columna;

select current_setting('app.nexar_portal_m07_gate', true) as gate_m07,
       current_setting('app.nexar_portal_m07_gate', true) is distinct from 'completed'
         as m07_sigue_bloqueada;
