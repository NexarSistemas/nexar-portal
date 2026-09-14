-- Solo lectura: gate previo a M07; debe revisarse antes de cualquier DDL destructivo.
select current_setting('app.nexar_portal_m07_gate', true) as gate_m07;

select to_regclass('public.portal_vendedor_sessions') is not null as sesiones_legacy_existen,
       to_regclass('public.admin_audit_log') is not null as auditoria_legacy_existe;

select table_name, column_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (table_name, column_name) in (
    ('pagos', 'venta_id'), ('licencias', 'cliente_id'), ('licencias', 'venta_id'),
    ('licencias', 'venta_item_id'), ('comisiones', 'vendedor_id'),
    ('comisiones', 'venta_id'), ('comisiones', 'pago_id')
  )
order by table_name, column_name;
