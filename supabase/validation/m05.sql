-- Solo lectura: perfiles, Auth y helpers privados de M05.
with esperadas(columna, tipo, admite_null) as (
  values
    ('user_id', 'uuid', false), ('nombre', 'text', false), ('rol', 'text', false),
    ('vendedor_id', 'uuid', true), ('activo', 'boolean', false),
    ('created_at', 'timestamp with time zone', false), ('updated_at', 'timestamp with time zone', false)
)
select e.*, c.data_type as tipo_encontrado, c.is_nullable = 'YES' as admite_null_encontrado,
  c.data_type = e.tipo and (c.is_nullable = 'YES') = e.admite_null as correcto
from esperadas e
left join information_schema.columns c
  on c.table_schema = 'public' and c.table_name = 'perfiles' and c.column_name = e.columna
order by e.columna;

select
  exists (select 1 from pg_constraint where conrelid = 'public.perfiles'::regclass
    and contype = 'f' and confrelid = 'auth.users'::regclass) as perfil_tiene_fk_auth_users,
  exists (select 1 from pg_constraint where conrelid = 'public.perfiles'::regclass
    and contype = 'f' and confrelid = 'public.vendedores'::regclass) as perfil_tiene_fk_vendedor,
  exists (select 1 from information_schema.columns where table_schema = 'public'
    and table_name = 'perfiles' and column_name = 'activo' and column_default is not null) as activo_tiene_default;

select exists (
  select 1 from pg_constraint
  where conname = 'perfiles_rol_vendedor_id_check'
    and conrelid = 'public.perfiles'::regclass and contype = 'c'
) as vendedor_requiere_vendedor_id_y_admin_lo_admite_opcional;

select conname, pg_get_constraintdef(oid) as definicion
from pg_constraint
where conname = 'perfiles_rol_vendedor_id_check'
  and conrelid = 'public.perfiles'::regclass;

select p.proname, p.prosecdef as security_definer,
  case
    when p.proname = 'es_vendedor_de_venta'
      then position('vendedor_actual_id' in lower(pg_get_functiondef(p.oid))) > 0
    else position('and activo' in lower(pg_get_functiondef(p.oid))) > 0
  end as excluye_perfil_inactivo,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_puede_ejecutar,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_no_puede_ejecutar
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'app_private'
  and p.proname in ('es_admin', 'vendedor_actual_id', 'es_vendedor_de_venta')
order by p.proname;
