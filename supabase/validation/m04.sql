-- Solo lectura: preflight y resultado esperado de M04.
select current_setting('app.nexar_portal_m04_approved', true) as aprobacion_m04;

select codigo_vendedor, count(*) as cantidad
from public.vendedores
where codigo_vendedor = 'RONA596'
group by codigo_vendedor;

select count(*) as cantidad_vendedores_legacy from public.vendedores;

select count(*) as recuperaciones_asociadas_a_vendedores_de_prueba
from public.portal_password_recovery_requests r
where r.vendedor_id is not null
  and not exists (
    select 1 from public.vendedores v
    where v.id = r.vendedor_id and v.codigo_vendedor = 'RONA596'
  );

with tablas(tabla) as (
  values ('licencias'), ('pagos'), ('comisiones'), ('referidos'),
    ('solicitudes_demo'), ('solicitudes_licencia'), ('solicitudes_soporte'),
    ('solicitudes_upgrade'), ('solicitudes_vendedores'), ('admin_audit_log'),
    ('precios_planes')
)
select tabla, to_regclass(format('public.%I', tabla)) is not null as existe
from tablas order by tabla;

select producto, plan_comercial, moneda, monto, tipo_cobro, estado,
  vigencia_desde, vigencia_hasta
from public.precios_planes
order by producto, plan_comercial, vigencia_desde;

select c.relname as tabla, a.attname as columna_identity, a.attidentity
from pg_class c
join pg_attribute a on a.attrelid = c.oid
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('solicitudes_demo', 'solicitudes_licencia', 'solicitudes_soporte', 'solicitudes_vendedores')
  and a.attname = 'id' and not a.attisdropped
order by c.relname;

-- Ejecutar despues de M04: debe quedar solo RONA596 y los datos saneables vacios.
select codigo_vendedor from public.vendedores order by codigo_vendedor;

select 'licencias' as tabla, count(*) as cantidad from public.licencias
union all select 'pagos', count(*) from public.pagos
union all select 'comisiones', count(*) from public.comisiones
union all select 'referidos', count(*) from public.referidos
union all select 'solicitudes_demo', count(*) from public.solicitudes_demo
union all select 'solicitudes_licencia', count(*) from public.solicitudes_licencia
union all select 'solicitudes_soporte', count(*) from public.solicitudes_soporte
union all select 'solicitudes_upgrade', count(*) from public.solicitudes_upgrade
union all select 'solicitudes_vendedores', count(*) from public.solicitudes_vendedores;

select to_regclass('public.admin_audit_log') is not null as admin_audit_log_preservado,
       to_regclass('public.precios_planes') is not null as precios_planes_preservado;

select s.relname as secuencia, t.relname as tabla
from pg_class s
join pg_depend d on d.objid = s.oid and d.deptype in ('a', 'i')
join pg_class t on t.oid = d.refobjid
where s.relkind = 'S'
  and t.relnamespace = 'public'::regnamespace
  and t.relname in ('solicitudes_demo', 'solicitudes_licencia', 'solicitudes_soporte', 'solicitudes_vendedores')
order by t.relname, s.relname;

select lp.producto, lp.plan_comercial, lp.vigencia_desde,
  pr.id is not null and pl.id is not null and pc.id is not null as correspondencia_canonica
from public.precios_planes lp
left join public.productos pr on pr.codigo = lp.producto
left join public.planes pl on pl.producto_id = pr.id and pl.codigo = lp.plan_comercial
left join public.precios pc on pc.plan_id = pl.id and pc.vigente_desde = lp.vigencia_desde
order by lp.producto, lp.plan_comercial, lp.vigencia_desde;
