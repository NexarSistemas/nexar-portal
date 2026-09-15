-- Solo lectura: precondiciones legacy de M00.
with esperadas(tabla) as (
  values ('vendedores'), ('pagos'), ('licencias'), ('comisiones'), ('precios_planes'),
         ('referidos'), ('portal_vendedor_sessions'), ('portal_password_recovery_requests'),
         ('admin_audit_log'), ('newsletter_preference_requests'), ('solicitudes_demo'),
         ('solicitudes_licencia'), ('solicitudes_soporte'), ('solicitudes_upgrade'),
         ('solicitudes_vendedores'), ('suscripciones_novedades')
)
select tabla, to_regclass(format('public.%I', tabla)) is not null as existe
from esperadas order by tabla;

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (table_name, column_name) in (
    ('vendedores', 'id'), ('vendedores', 'codigo_vendedor'),
    ('vendedores', 'password_hash'), ('vendedores', 'password_change_required'),
    ('vendedores', 'ultimo_login'), ('pagos', 'id'),
    ('licencias', 'license_key'), ('licencias', 'codigo_vendedor'),
    ('precios_planes', 'producto'), ('precios_planes', 'plan_comercial'),
    ('precios_planes', 'moneda'), ('precios_planes', 'monto'),
    ('precios_planes', 'tipo_cobro'), ('precios_planes', 'estado'),
    ('precios_planes', 'vigencia_desde'), ('precios_planes', 'vigencia_hasta')
  )
order by table_name;

select conrelid::regclass as tabla, conname, confrelid::regclass as tabla_referenciada,
  case confdeltype when 'r' then 'RESTRICT' when 'c' then 'CASCADE' when 'n' then 'SET NULL' end as on_delete
from pg_constraint
where contype = 'f'
  and (conrelid, confrelid) in (
    ('public.referidos'::regclass, 'public.vendedores'::regclass),
    ('public.portal_vendedor_sessions'::regclass, 'public.vendedores'::regclass),
    ('public.portal_password_recovery_requests'::regclass, 'public.vendedores'::regclass)
  )
order by tabla::text, conname;
