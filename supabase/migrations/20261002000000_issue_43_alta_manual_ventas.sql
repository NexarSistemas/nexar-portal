-- Issue #43: alta manual atómica, con snapshots y precio de catálogo resuelto en servidor.

alter table public.ventas
  add column manual_idempotency_key uuid;

alter table public.ventas
  add constraint ventas_manual_idempotency_key_key unique (manual_idempotency_key);

create or replace function public.crear_venta_manual(
  p_cliente_id uuid,
  p_vendedor_id uuid,
  p_fecha_venta timestamptz,
  p_moneda text,
  p_items jsonb,
  p_idempotency_key uuid
)
returns public.ventas
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_venta public.ventas;
  v_item jsonb;
  v_producto public.productos;
  v_plan public.planes;
  v_precio public.precios;
  v_cantidad numeric(12,3);
  v_total numeric(14,2) := 0;
  v_moneda text := pg_catalog.upper(pg_catalog.btrim(p_moneda));
begin
  if auth.uid() is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesión autenticada.';
  end if;
  if not app_private.es_admin() then
    raise exception using errcode = '42501', message = 'El perfil no tiene acceso administrativo.';
  end if;
  if p_cliente_id is null or p_fecha_venta is null or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'Cliente, fecha e idempotency_key son obligatorios.';
  end if;
  if v_moneda is null or v_moneda !~ '^[A-Z]{3}$' then
    raise exception using errcode = '22023', message = 'La moneda debe usar un código ISO de tres letras.';
  end if;
  if pg_catalog.jsonb_typeof(p_items) <> 'array' or pg_catalog.jsonb_array_length(p_items) = 0 then
    raise exception using errcode = '22023', message = 'La venta requiere al menos un ítem.';
  end if;

  select * into v_venta from public.ventas where manual_idempotency_key = p_idempotency_key;
  if found then return v_venta; end if;

  perform 1 from public.clientes where id = p_cliente_id;
  if not found then
    raise exception using errcode = '23503', message = 'El cliente seleccionado no existe.';
  end if;
  if p_vendedor_id is not null then
    perform 1 from public.vendedores where id = p_vendedor_id;
    if not found then
      raise exception using errcode = '23503', message = 'El vendedor seleccionado no existe.';
    end if;
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_items)
  loop
    if pg_catalog.jsonb_typeof(v_item) <> 'object'
      or pg_catalog.nullif(v_item ->> 'producto_id', '') is null
      or pg_catalog.nullif(v_item ->> 'plan_id', '') is null
      or pg_catalog.jsonb_typeof(v_item -> 'cantidad') <> 'number'
    then
      raise exception using errcode = '22023', message = 'Cada ítem requiere producto, plan y cantidad.';
    end if;

    v_cantidad := (v_item ->> 'cantidad')::numeric(12,3);
    if v_cantidad <= 0 then
      raise exception using errcode = '22023', message = 'La cantidad de cada ítem debe ser mayor a cero.';
    end if;

    select * into v_producto
    from public.productos
    where id = (v_item ->> 'producto_id')::uuid and activo;
    if not found then
      raise exception using errcode = '23503', message = 'El producto seleccionado no existe o no está activo.';
    end if;

    select * into v_plan
    from public.planes
    where id = (v_item ->> 'plan_id')::uuid
      and producto_id = v_producto.id
      and activo;
    if not found then
      raise exception using errcode = '23503', message = 'El plan seleccionado no existe, no corresponde al producto o no está activo.';
    end if;

    select * into v_precio
    from public.precios
    where plan_id = v_plan.id
      and moneda = v_moneda
      and estado = 'activo'
      and vigente_desde <= p_fecha_venta
      and (vigente_hasta is null or vigente_hasta > p_fecha_venta)
    order by vigente_desde desc
    limit 1;
    if not found then
      raise exception using errcode = '22023', message = 'No hay un precio vigente para el plan y moneda seleccionados.';
    end if;

    v_total := v_total + (v_cantidad * v_precio.importe);
  end loop;

  insert into public.ventas (cliente_id, vendedor_id, fecha_venta, moneda, estado, importe_total, manual_idempotency_key)
  values (p_cliente_id, p_vendedor_id, p_fecha_venta, v_moneda, 'pendiente', v_total, p_idempotency_key)
  returning * into v_venta;

  for v_item in select value from pg_catalog.jsonb_array_elements(p_items)
  loop
    select * into v_producto from public.productos where id = (v_item ->> 'producto_id')::uuid;
    select * into v_plan from public.planes where id = (v_item ->> 'plan_id')::uuid;
    select * into v_precio
    from public.precios
    where plan_id = v_plan.id and moneda = v_moneda and estado = 'activo'
      and vigente_desde <= p_fecha_venta and (vigente_hasta is null or vigente_hasta > p_fecha_venta)
    order by vigente_desde desc limit 1;
    v_cantidad := (v_item ->> 'cantidad')::numeric(12,3);

    insert into public.venta_items (
      venta_id, producto_id, plan_id, precio_id, descripcion, producto_nombre, plan_nombre, cantidad, precio_unitario, importe_total
    ) values (
      v_venta.id, v_producto.id, v_plan.id, v_precio.id,
      v_producto.nombre || ' · ' || v_plan.nombre, v_producto.nombre, v_plan.nombre,
      v_cantidad, v_precio.importe, v_cantidad * v_precio.importe
    );
  end loop;

  return v_venta;
exception when unique_violation then
  select * into v_venta from public.ventas where manual_idempotency_key = p_idempotency_key;
  if found then return v_venta; end if;
  raise;
end;
$$;

revoke all on function public.crear_venta_manual(uuid, uuid, timestamptz, text, jsonb, uuid) from public, anon;
grant execute on function public.crear_venta_manual(uuid, uuid, timestamptz, text, jsonb, uuid) to authenticated;

comment on function public.crear_venta_manual(uuid, uuid, timestamptz, text, jsonb, uuid) is
  'Crea una venta manual pendiente con ítems y snapshots en una única transacción; resuelve precios vigentes y es idempotente por clave explícita.';
