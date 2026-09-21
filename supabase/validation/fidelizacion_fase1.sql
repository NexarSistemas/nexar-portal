-- Solo lectura: valida el esquema, integridad, grants y RLS de Fidelizacion Fase 1.

with esperadas(tabla) as (
  values
    ('fidelizacion_tenants'),
    ('fidelizacion_accounts'),
    ('fidelizacion_staff'),
    ('fidelizacion_rewards'),
    ('fidelizacion_operations'),
    ('fidelizacion_point_movements'),
    ('fidelizacion_redemptions')
)
select tabla as tabla_faltante
from esperadas
where to_regclass(format('public.%I', tabla)) is null
order by tabla;

select to_regclass('public.fidelizacion_levels') is null as fidelizacion_levels_no_existe;

select c.relname as tabla, c.relrowsecurity as rls_habilitada
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'fidelizacion_tenants', 'fidelizacion_accounts', 'fidelizacion_staff',
    'fidelizacion_rewards', 'fidelizacion_operations',
    'fidelizacion_point_movements', 'fidelizacion_redemptions'
  )
order by c.relname;

select con.conname, con.conrelid::regclass as tabla,
       con.confrelid::regclass as referencia, pg_get_constraintdef(con.oid) as definicion
from pg_constraint con
where con.conrelid = 'public.fidelizacion_accounts'::regclass
  and con.contype = 'f'
order by con.conname;

select count(*) = 1 as accounts_referencia_directa_auth_users
from pg_constraint con
where con.conrelid = 'public.fidelizacion_accounts'::regclass
  and con.contype = 'f'
  and con.confrelid = 'auth.users'::regclass;

select count(*) = 1 as staff_referencia_directa_auth_users
from pg_constraint con
where con.conrelid = 'public.fidelizacion_staff'::regclass
  and con.contype = 'f'
  and con.confrelid = 'auth.users'::regclass;

select count(*) = 0 as sin_dependencia_de_perfiles
from pg_constraint con
where con.conrelid in (
    'public.fidelizacion_tenants'::regclass,
    'public.fidelizacion_accounts'::regclass,
    'public.fidelizacion_staff'::regclass,
    'public.fidelizacion_rewards'::regclass,
    'public.fidelizacion_operations'::regclass,
    'public.fidelizacion_point_movements'::regclass,
    'public.fidelizacion_redemptions'::regclass
  )
  and con.confrelid = 'public.perfiles'::regclass;

with esperadas(constraint_name) as (
  values
    ('fidelizacion_accounts_tenant_user_key'),
    ('fidelizacion_accounts_tenant_id_id_key'),
    ('fidelizacion_staff_pkey'),
    ('fidelizacion_rewards_tenant_id_id_key'),
    ('fidelizacion_operations_tenant_account_fkey'),
    ('fidelizacion_operations_tenant_reward_fkey'),
    ('fidelizacion_operations_tenant_idempotency_key_key'),
    ('fidelizacion_operations_tenant_id_account_tipo_puntos_key'),
    ('fidelizacion_operations_tenant_id_account_reward_key'),
    ('fidelizacion_point_movements_operation_fkey'),
    ('fidelizacion_point_movements_operation_id_key'),
    ('fidelizacion_redemptions_tenant_account_fkey'),
    ('fidelizacion_redemptions_tenant_reward_fkey'),
    ('fidelizacion_redemptions_operation_fkey'),
    ('fidelizacion_redemptions_operation_id_key')
)
select constraint_name as constraint_faltante
from esperadas e
where not exists (select 1 from pg_constraint c where c.conname = e.constraint_name)
order by constraint_name;

with esperada(columna) as (
  values ('puntos_movimiento'::text)
)
select a.attname as columna_faltante_o_no_generada,
       a.attgenerated as tipo_generacion,
       pg_get_expr(d.adbin, d.adrelid) as expresion,
       coalesce(a.attgenerated = 's'
         and position('tipo' in pg_get_expr(d.adbin, d.adrelid)) > 0
         and position('puntos' in pg_get_expr(d.adbin, d.adrelid)) > 0, false)
         as puntos_firmados_derivados_de_tipo_y_puntos
from esperada e
left join pg_attribute a
  on a.attrelid = to_regclass('public.fidelizacion_operations')
  and a.attname = e.columna
  and a.attnum > 0
left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum;

select con.conname, pg_get_constraintdef(con.oid) as definicion,
       array(
         select a.attname
         from unnest(con.conkey) with ordinality as k(attnum, orden)
         join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
         order by k.orden
       ) = array['tenant_id', 'operation_id', 'account_id', 'tipo', 'puntos']::name[]
         as fk_incluye_puntos_movimiento,
       array(
         select a.attname
         from unnest(con.confkey) with ordinality as k(attnum, orden)
         join pg_attribute a on a.attrelid = con.confrelid and a.attnum = k.attnum
         order by k.orden
       ) = array['tenant_id', 'id', 'account_id', 'tipo', 'puntos_movimiento']::name[]
         as fk_apunta_a_puntos_firmados
from pg_constraint con
where con.conrelid = 'public.fidelizacion_point_movements'::regclass
  and con.conname = 'fidelizacion_point_movements_operation_fkey';

select con.conname,
       array(
         select a.attname
         from unnest(con.conkey) with ordinality as k(attnum, orden)
         join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
         order by k.orden
       ) = array['tenant_id', 'id', 'account_id', 'tipo', 'puntos_movimiento']::name[]
         as unique_respalda_fk_de_movimientos
from pg_constraint con
where con.conrelid = 'public.fidelizacion_operations'::regclass
  and con.conname = 'fidelizacion_operations_tenant_id_account_tipo_puntos_key'
  and con.contype = 'u';

select conname, conrelid::regclass as tabla, confrelid::regclass as referencia,
       pg_get_constraintdef(oid) as definicion
from pg_constraint
where conname in (
  'fidelizacion_operations_tenant_account_fkey',
  'fidelizacion_operations_tenant_reward_fkey',
  'fidelizacion_point_movements_operation_fkey',
  'fidelizacion_redemptions_tenant_account_fkey',
  'fidelizacion_redemptions_tenant_reward_fkey',
  'fidelizacion_redemptions_operation_fkey'
)
order by conname;

select column_name as saldo_mutable_indebido
from information_schema.columns
where table_schema = 'public'
  and table_name = 'fidelizacion_accounts'
  and column_name in ('saldo', 'balance', 'puntos');

select c.relname as tabla,
       has_table_privilege('public', c.oid, 'SELECT')
         or has_table_privilege('public', c.oid, 'INSERT')
         or has_table_privilege('public', c.oid, 'UPDATE')
         or has_table_privilege('public', c.oid, 'DELETE')
         or has_table_privilege('public', c.oid, 'TRUNCATE')
         or has_table_privilege('public', c.oid, 'REFERENCES')
         or has_table_privilege('public', c.oid, 'TRIGGER')
         as public_tiene_privilegio_indebido,
       has_table_privilege('anon', c.oid, 'SELECT')
         or has_table_privilege('anon', c.oid, 'INSERT')
         or has_table_privilege('anon', c.oid, 'UPDATE')
         or has_table_privilege('anon', c.oid, 'DELETE')
         or has_table_privilege('anon', c.oid, 'TRUNCATE')
         or has_table_privilege('anon', c.oid, 'REFERENCES')
         or has_table_privilege('anon', c.oid, 'TRIGGER')
         as anon_tiene_privilegio_indebido,
       has_table_privilege('authenticated', c.oid, 'SELECT') as authenticated_puede_select,
       has_table_privilege('authenticated', c.oid, 'INSERT')
         or has_table_privilege('authenticated', c.oid, 'UPDATE')
         or has_table_privilege('authenticated', c.oid, 'DELETE')
         or has_table_privilege('authenticated', c.oid, 'TRUNCATE')
         or has_table_privilege('authenticated', c.oid, 'REFERENCES')
         or has_table_privilege('authenticated', c.oid, 'TRIGGER')
         as authenticated_tiene_escritura_indebida,
       has_table_privilege('service_role', c.oid, 'SELECT')
         and has_table_privilege('service_role', c.oid, 'INSERT')
         and has_table_privilege('service_role', c.oid, 'UPDATE')
         and has_table_privilege('service_role', c.oid, 'DELETE')
         as service_role_tiene_crud
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname like 'fidelizacion_%'
  and c.relkind = 'r'
order by c.relname;

select grantee, table_name, column_name, privilege_type
from information_schema.column_privileges
where table_schema = 'public'
  and table_name like 'fidelizacion_%'
  and grantee in ('PUBLIC', 'anon', 'authenticated')
order by grantee, table_name, column_name, privilege_type;

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename like 'fidelizacion_%'
order by tablename, policyname;

select tablename, policyname, cmd, roles as policy_no_select_o_rol_inesperado
from pg_policies
where schemaname = 'public'
  and tablename like 'fidelizacion_%'
  and (cmd <> 'SELECT' or roles <> array['authenticated'::name])
order by tablename, policyname;

select p.oid::regprocedure as funcion,
       p.prosecdef as security_definer,
       p.provolatile = 's' as estable,
       p.proconfig as configuracion,
       not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
       not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_con_execute,
       position('public.perfiles' in pg_get_functiondef(p.oid)) = 0 as sin_perfiles
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'app_private'
  and p.proname in ('fidelizacion_es_cliente', 'fidelizacion_es_staff')
order by p.proname;

select column_default,
       column_default like '%extensions.gen_random_bytes(24)%' as usa_192_bits_aleatorios,
       column_default like '%base64%' as codifica_base64
from information_schema.columns
where table_schema = 'public'
  and table_name = 'fidelizacion_tenants'
  and column_name = 'public_qr_code';

select conname, contype, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conrelid = 'public.fidelizacion_tenants'::regclass
  and conname in (
    'fidelizacion_tenants_public_qr_code_check',
    'fidelizacion_tenants_public_qr_code_key'
  )
order by conname;

with fk_columnas as (
  select con.conrelid, unnest(con.conkey) as attnum
  from pg_constraint con
  join pg_namespace n on n.oid = con.connamespace
  where con.contype = 'f'
    and n.nspname = 'public'
    and con.conrelid::regclass::text like 'fidelizacion_%'
)
select f.conrelid::regclass as tabla, a.attname as columna_fk_sin_indice
from fk_columnas f
join pg_attribute a on a.attrelid = f.conrelid and a.attnum = f.attnum
where not exists (
  select 1
  from pg_index i
  where i.indrelid = f.conrelid and f.attnum = any (i.indkey)
)
order by tabla, columna_fk_sin_indice;
