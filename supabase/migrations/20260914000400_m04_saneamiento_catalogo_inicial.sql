-- M04: saneamiento destructivo, explicitamente aprobado, de datos de prueba.
-- No retira estructuras legacy ni modifica precios_planes, auditoria, sesiones
-- de RONA596, recuperacion de password ni preferencias de novedades.

do $$
declare
  tabla text;
  columna record;
  vendedor_real_id uuid;
  cantidad_vendedores integer;
  tabla_vacia boolean;
begin
  if current_setting('app.nexar_portal_m04_approved', true) is distinct from 'approved' then
    raise exception using
      message = 'M04 no esta habilitada para ejecucion.',
      hint = 'Tras aprobar el plan de saneamiento, ejecute en una sesion controlada: SET app.nexar_portal_m04_approved = ''approved''.';
  end if;

  -- Preflight del snapshot 2026-09-14: cualquier cambio material exige relevar
  -- nuevamente antes de borrar datos.
  foreach tabla in array array[
    'vendedores', 'licencias', 'pagos', 'comisiones', 'referidos',
    'portal_vendedor_sessions', 'portal_password_recovery_requests',
    'admin_audit_log', 'precios_planes', 'newsletter_preference_requests',
    'suscripciones_novedades', 'solicitudes_demo', 'solicitudes_licencia',
    'solicitudes_soporte', 'solicitudes_upgrade', 'solicitudes_vendedores',
    'productos', 'planes', 'precios'
  ]
  loop
    if to_regclass(format('public.%I', tabla)) is null then
      raise exception using
        message = format('M04 requiere public.%I.', tabla),
        hint = 'El schema no coincide con el snapshot legacy aprobado; no se borro ningun dato.';
    end if;
  end loop;

  for columna in
    select * from (values
      ('vendedores', 'id'), ('vendedores', 'codigo_vendedor'),
      ('precios_planes', 'producto'), ('precios_planes', 'plan_comercial'),
      ('precios_planes', 'moneda'), ('precios_planes', 'monto'),
      ('precios_planes', 'tipo_cobro'), ('precios_planes', 'estado'),
      ('precios_planes', 'vigencia_desde'), ('precios_planes', 'vigencia_hasta')
    ) as esperadas(tabla, nombre)
  loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = columna.tabla
        and column_name = columna.nombre
    ) then
      raise exception using
        message = format('M04 requiere public.%I.%I.', columna.tabla, columna.nombre),
        hint = 'El schema no coincide con el snapshot legacy aprobado; no se borro ningun dato.';
    end if;
  end loop;

  select count(*) into cantidad_vendedores from public.vendedores;
  if cantidad_vendedores <> 2 then
    raise exception using
      message = format('M04 esperaba exactamente dos vendedores legacy y encontro %s.', cantidad_vendedores),
      hint = 'El snapshot cambio materialmente; releve los vendedores antes de autorizar saneamiento.';
  end if;

  if (select count(*) from public.vendedores where codigo_vendedor = 'RONA596') <> 1 then
    raise exception using
      message = 'M04 requiere exactamente un vendedor con codigo_vendedor RONA596.',
      hint = 'No se hardcodea UUID: corrija o releve el snapshot antes de continuar.';
  end if;
  select id into vendedor_real_id
  from public.vendedores
  where codigo_vendedor = 'RONA596';

  if not exists (
    select 1 from pg_constraint c
    where c.contype = 'f'
      and c.conrelid = 'public.referidos'::regclass
      and c.confrelid = 'public.vendedores'::regclass
      and c.confdeltype = 'r'
      and c.conkey = array[(select attnum from pg_attribute where attrelid = 'public.referidos'::regclass and attname = 'vendedor_id' and not attisdropped)]::smallint[]
  ) or not exists (
    select 1 from pg_constraint c
    where c.contype = 'f'
      and c.conrelid = 'public.portal_vendedor_sessions'::regclass
      and c.confrelid = 'public.vendedores'::regclass
      and c.confdeltype = 'c'
      and c.conkey = array[(select attnum from pg_attribute where attrelid = 'public.portal_vendedor_sessions'::regclass and attname = 'vendedor_id' and not attisdropped)]::smallint[]
  ) or not exists (
    select 1 from pg_constraint c
    where c.contype = 'f'
      and c.conrelid = 'public.portal_password_recovery_requests'::regclass
      and c.confrelid = 'public.vendedores'::regclass
      and c.confdeltype = 'n'
      and c.conkey = array[(select attnum from pg_attribute where attrelid = 'public.portal_password_recovery_requests'::regclass and attname = 'vendedor_id' and not attisdropped)]::smallint[]
  ) then
    raise exception using
      message = 'M04 detecto FK legacy distintas del snapshot esperado.',
      hint = 'No se borro ningun dato: revalide las dependencias de vendedores antes de continuar.';
  end if;

  -- No se permite que eliminar el vendedor de prueba altere solicitudes de
  -- recuperacion, que permanecen fuera del saneamiento.
  if exists (
    select 1
    from public.portal_password_recovery_requests r
    where r.vendedor_id is not null and r.vendedor_id <> vendedor_real_id
  ) then
    raise exception using
      message = 'M04 encontro recuperaciones de password vinculadas al vendedor de prueba.',
      hint = 'Esas solicitudes se preservan: releve el caso antes de eliminar el vendedor de prueba.';
  end if;

  if not exists (select 1 from public.precios_planes) then
    raise exception using
      message = 'M04 requiere un catalogo legacy no vacio en precios_planes.',
      hint = 'No se crea un catalogo canonico por inferencia cuando falta la fuente legacy.';
  end if;

  if exists (
    select 1 from public.precios_planes
    where producto not in ('nexar-tienda', 'nexar-finanzas')
       or plan_comercial not in ('BASICA', 'PRO', 'FULL')
       or producto is null or plan_comercial is null
       or moneda is null or moneda !~ '^[A-Z]{3}$'
       or monto is null or monto < 0
       or tipo_cobro is null or btrim(tipo_cobro) = ''
       or estado is null or btrim(estado) = ''
       or vigencia_desde is null
       or (vigencia_hasta is not null and vigencia_hasta <= vigencia_desde)
  ) then
    raise exception using
      message = 'M04 encontro un producto, plan o precio legacy incompatible.',
      hint = 'No se borro ningun dato: revise el mapeo de precios_planes antes de reintentar.';
  end if;

  if exists (
    select 1 from public.precios_planes
    group by producto, plan_comercial, vigencia_desde
    having count(*) > 1
  ) then
    raise exception using
      message = 'M04 encontro historial de precios legacy ambiguo para producto, plan y vigencia.',
      hint = 'No se borro ningun dato: consolide o releve el historial antes de migrarlo.';
  end if;

  foreach tabla in array array[
    'solicitudes_demo', 'solicitudes_licencia', 'solicitudes_soporte', 'solicitudes_vendedores'
  ]
  loop
    if not exists (
      select 1 from pg_attribute
      where attrelid = format('public.%I', tabla)::regclass
        and attname = 'id' and attidentity in ('a', 'd') and not attisdropped
    ) then
      raise exception using
        message = format('M04 esperaba una columna id identity en public.%I.', tabla),
        hint = 'No se borro ningun dato: el reset de secuencia requiere revalidar el schema.';
    end if;
  end loop;

  -- Ordenado por relaciones legacy conocidas. Las sesiones del vendedor real
  -- no se tocan; la recuperacion de password se preservo en el preflight.
  delete from public.licencias;
  delete from public.comisiones;
  delete from public.pagos;
  delete from public.referidos;
  delete from public.solicitudes_demo;
  delete from public.solicitudes_licencia;
  delete from public.solicitudes_soporte;
  delete from public.solicitudes_upgrade;
  delete from public.solicitudes_vendedores;
  delete from public.portal_vendedor_sessions where vendedor_id <> vendedor_real_id;
  delete from public.vendedores where id <> vendedor_real_id;

  foreach tabla in array array[
    'solicitudes_demo', 'solicitudes_licencia', 'solicitudes_soporte', 'solicitudes_vendedores'
  ]
  loop
    execute format('select not exists (select 1 from public.%I)', tabla) into tabla_vacia;
    if tabla_vacia then
      execute format('alter table public.%I alter column id restart with 1', tabla);
    end if;
  end loop;

  insert into public.productos (codigo, nombre)
  values ('nexar-tienda', 'Nexar Comercio'), ('nexar-finanzas', 'Nexar Finanzas')
  on conflict (codigo) do update set nombre = excluded.nombre;

  insert into public.planes (producto_id, codigo, nombre, activo)
  select p.id, c.plan_comercial, c.plan_comercial, true
  from (
    select distinct producto, plan_comercial from public.precios_planes
  ) c
  join public.productos p on p.codigo = c.producto
  on conflict (producto_id, codigo) do update
    set nombre = excluded.nombre, activo = excluded.activo;

  insert into public.precios (
    plan_id, moneda, importe, modalidad_cobro, estado, vigente_desde, vigente_hasta
  )
  select pl.id, lp.moneda, lp.monto, lp.tipo_cobro, lp.estado,
    lp.vigencia_desde, lp.vigencia_hasta
  from public.precios_planes lp
  join public.productos pr on pr.codigo = lp.producto
  join public.planes pl on pl.producto_id = pr.id and pl.codigo = lp.plan_comercial
  on conflict (plan_id, vigente_desde) do update set
    moneda = excluded.moneda,
    importe = excluded.importe,
    modalidad_cobro = excluded.modalidad_cobro,
    estado = excluded.estado,
    vigente_hasta = excluded.vigente_hasta;
end
$$;
