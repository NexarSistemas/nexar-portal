-- Solo lectura: gate previo a M07; debe revisarse antes de cualquier DDL destructivo.
select current_setting('app.nexar_portal_m07_gate', true) as gate_m07;

select to_regclass('public.portal_vendedor_sessions') is not null as sesiones_legacy_existen,
       to_regclass('public.admin_audit_log') is not null as auditoria_legacy_existe;

select p.oid::regprocedure as funcion, p.prosecdef as security_definer
from pg_proc p
where p.oid = 'public.portal_dashboard_vendedor(text)'::regprocedure;

select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
  and policyname like 'portal_secret_%'
order by tablename, policyname;

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'vendedores'
  and column_name in ('password_hash', 'password_change_required', 'ultimo_login', 'es_admin')
order by column_name;

select to_regclass('public.portal_password_recovery_requests') is not null
  as recuperacion_password_legacy_existe;

select table_name, column_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (table_name, column_name) in (
    ('pagos', 'venta_id'), ('licencias', 'cliente_id'), ('licencias', 'venta_id'),
    ('licencias', 'venta_item_id'), ('comisiones', 'vendedor_id'),
    ('comisiones', 'venta_id'), ('comisiones', 'pago_id')
  )
order by table_name, column_name;
