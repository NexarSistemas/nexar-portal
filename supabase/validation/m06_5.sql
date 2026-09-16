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

with esperados(tabla, privilegio) as (
  values
    ('vendedores', 'SELECT'), ('licencias', 'SELECT'), ('comisiones', 'SELECT')
), actuales as (
  select table_name as tabla, privilege_type as privilegio
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'authenticated'
)
select 'faltante' as diferencia, * from (select * from esperados except select * from actuales) d
union all
select 'escritura_indebida' as diferencia, * from (
  select * from actuales
  where tabla in ('vendedores', 'licencias', 'comisiones')
    and privilegio in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
) d
order by tabla, privilegio;

with esperadas(columna) as (
  values ('email'), ('telefono'), ('alias_cbu')
), actuales as (
  select column_name as columna
  from information_schema.role_column_grants
  where table_schema = 'public'
    and grantee = 'authenticated'
    and table_name = 'vendedores'
    and privilege_type = 'UPDATE'
)
select 'faltante' as diferencia, columna from (select * from esperadas except select * from actuales) d
union all
select 'indebida' as diferencia, columna from (select * from actuales except select * from esperadas) d
order by columna;

select
  has_table_privilege('authenticated', 'public.vendedores', 'INSERT') as vendedor_insert_indebido,
  has_table_privilege('authenticated', 'public.vendedores', 'DELETE') as vendedor_delete_indebido,
  has_table_privilege('authenticated', 'public.licencias', 'INSERT, UPDATE, DELETE') as licencias_escritura_indebida,
  has_table_privilege('authenticated', 'public.comisiones', 'INSERT, UPDATE, DELETE') as comisiones_escritura_indebida;

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
