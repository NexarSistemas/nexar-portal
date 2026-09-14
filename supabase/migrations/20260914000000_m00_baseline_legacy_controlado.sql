-- M00: baseline legacy controlado.
-- No elimina ni modifica datos. Esta migracion documenta y verifica el minimo
-- indispensable para la coexistencia con Nexar Admin, Nexar Pagos y Portal Vendedor.

do $$
declare
  tabla text;
  esperado record;
begin
  foreach tabla in array array[
    'vendedores', 'pagos', 'licencias', 'comisiones', 'precios_planes',
    'referidos', 'portal_vendedor_sessions', 'portal_password_recovery_requests',
    'admin_audit_log', 'newsletter_preference_requests', 'solicitudes_demo',
    'solicitudes_licencia', 'solicitudes_soporte', 'solicitudes_upgrade',
    'solicitudes_vendedores', 'suscripciones_novedades'
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

  for esperado in
    select * from (values
      ('vendedores', 'codigo_vendedor'),
      ('vendedores', 'password_hash'),
      ('vendedores', 'password_change_required'),
      ('vendedores', 'ultimo_login'),
      ('licencias', 'license_key'),
      ('licencias', 'codigo_vendedor'),
      ('precios_planes', 'producto'),
      ('precios_planes', 'plan_comercial'),
      ('precios_planes', 'moneda'),
      ('precios_planes', 'monto'),
      ('precios_planes', 'tipo_cobro'),
      ('precios_planes', 'estado'),
      ('precios_planes', 'vigencia_desde'),
      ('precios_planes', 'vigencia_hasta')
    ) as columnas(tabla, columna)
  loop
    if not exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = esperado.tabla
        and column_name = esperado.columna
    ) then
      raise exception using
        message = format('M00 requiere public.%I.%I.', esperado.tabla, esperado.columna),
        hint = 'El relevamiento legacy vigente es una precondicion de M03, M04 y M07.';
    end if;
  end loop;

  if not exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and c.conrelid = 'public.referidos'::regclass
      and c.confrelid = 'public.vendedores'::regclass
      and c.confdeltype = 'r'
      and c.conkey = array[(select attnum from pg_attribute where attrelid = 'public.referidos'::regclass and attname = 'vendedor_id' and not attisdropped)]::smallint[]
  ) then
    raise exception using
      message = 'M00 requiere la FK legacy referidos.vendedor_id hacia vendedores con ON DELETE RESTRICT.',
      hint = 'M04 depende de eliminar primero los referidos de prueba.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and c.conrelid = 'public.portal_vendedor_sessions'::regclass
      and c.confrelid = 'public.vendedores'::regclass
      and c.confdeltype = 'c'
      and c.conkey = array[(select attnum from pg_attribute where attrelid = 'public.portal_vendedor_sessions'::regclass and attname = 'vendedor_id' and not attisdropped)]::smallint[]
  ) then
    raise exception using
      message = 'M00 requiere la FK legacy portal_vendedor_sessions.vendedor_id hacia vendedores con ON DELETE CASCADE.',
      hint = 'M07 no puede retirar sesiones hasta migrar sus consumidores activos.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.contype = 'f'
      and c.conrelid = 'public.portal_password_recovery_requests'::regclass
      and c.confrelid = 'public.vendedores'::regclass
      and c.confdeltype = 'n'
      and c.conkey = array[(select attnum from pg_attribute where attrelid = 'public.portal_password_recovery_requests'::regclass and attname = 'vendedor_id' and not attisdropped)]::smallint[]
  ) then
    raise exception using
      message = 'M00 requiere la FK legacy portal_password_recovery_requests.vendedor_id hacia vendedores con ON DELETE SET NULL.',
      hint = 'M04 preserva las solicitudes de recuperacion y depende de esta semantica.';
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
comment on table public.portal_password_recovery_requests is
  'Auth legacy operativo. M04 preserva sus registros y M07 continua bloqueada mientras tenga consumidores.';
comment on table public.admin_audit_log is
  'Fuente de auditoria existente; se conserva como fuente de verdad de auditoria.';
