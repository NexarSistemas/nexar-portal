-- M00: baseline legacy controlado.
-- No elimina ni modifica datos. Esta migracion documenta y verifica el minimo
-- indispensable para la coexistencia con Nexar Admin, Nexar Pagos y Portal Vendedor.

do $$
declare
  tabla text;
begin
  foreach tabla in array array[
    'vendedores', 'pagos', 'licencias', 'comisiones', 'precios_planes',
    'referidos', 'portal_vendedor_sessions', 'admin_audit_log'
  ]
  loop
    if to_regclass(format('public.%I', tabla)) is null then
      raise exception using
        message = format('M00 requiere la tabla legacy public.%I.', tabla),
        hint = 'No continue: releve el schema legacy y ajuste el baseline antes de ejecutar.';
    end if;
  end loop;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'vendedores'
      and column_name = 'id'
      and data_type = 'uuid'
  ) then
    raise exception using
      message = 'M00 requiere public.vendedores.id de tipo uuid.',
      hint = 'La relacion comercial canonica depende de conservar el UUID legacy del vendedor.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'pagos'
      and column_name = 'id'
      and data_type = 'uuid'
  ) then
    raise exception using
      message = 'M00 requiere public.pagos.id de tipo uuid.',
      hint = 'M03 necesita esta clave para relacionar comisiones de forma compatible.';
  end if;
end
$$;

comment on table public.vendedores is
  'Legacy reutilizado. Se conserva id UUID y sus consumidores durante la coexistencia.';
comment on table public.pagos is
  'Legacy reutilizado. M03 agrega venta_id nullable sin retirar columnas vigentes.';
comment on table public.licencias is
  'Legacy reutilizado. M03 agrega relaciones canonicas nullable sin retirar columnas vigentes.';
comment on table public.comisiones is
  'Legacy reutilizado. M03 agrega relaciones canonicas nullable sin retirar columnas vigentes.';
comment on table public.precios_planes is
  'Legacy en coexistencia. No se transforma en vista ni se retira en este baseline.';
comment on table public.referidos is
  'Legacy en coexistencia; M04 solo sanea datos de prueba con aprobacion operativa.';
comment on table public.portal_vendedor_sessions is
  'Auth legacy. No retirar hasta completar el gate documentado previo a M07.';
comment on table public.admin_audit_log is
  'Fuente de auditoria existente; se conserva como fuente de verdad de auditoria.';
