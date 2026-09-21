-- Fidelizacion Fase 2: acreditacion earn segura, atomica e idempotente.
-- El QR solo localiza al tenant; ninguna funcion acredita sin una operacion pendiente valida.

create or replace function app_private.fidelizacion_crear_earn(
  p_account_id uuid,
  p_puntos bigint,
  p_idempotency_key text,
  p_expires_at timestamptz default null
)
returns table (
  operation_id uuid,
  puntos bigint,
  estado text,
  expires_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
  v_idempotency_key text := pg_catalog.btrim(p_idempotency_key);
  v_operacion public.fidelizacion_operations%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;

  if p_account_id is null or p_puntos is null or p_puntos <= 0
    or v_idempotency_key is null or v_idempotency_key = ''
  then
    raise exception using errcode = '22023', message = 'Cuenta, puntos e idempotency_key validos son obligatorios.';
  end if;

  if p_expires_at is not null and p_expires_at <= pg_catalog.now() then
    raise exception using errcode = '22023', message = 'La expiracion debe ser futura.';
  end if;

  select a.tenant_id
    into v_tenant_id
  from public.fidelizacion_accounts a
  join public.fidelizacion_tenants t
    on t.id = a.tenant_id and t.activo
  join public.fidelizacion_staff s
    on s.tenant_id = a.tenant_id
   and s.user_id = v_user_id
   and s.activo
   and s.rol in ('admin', 'operador')
  where a.id = p_account_id
    and a.activo
  for share of a, t, s;

  if v_tenant_id is null then
    raise exception using
      errcode = '42501',
      message = 'La cuenta no esta disponible para el staff autenticado.';
  end if;

  insert into public.fidelizacion_operations (
    tenant_id,
    account_id,
    tipo,
    puntos,
    estado,
    expires_at,
    idempotency_key
  )
  values (
    v_tenant_id,
    p_account_id,
    'earn',
    p_puntos,
    'pending_customer',
    p_expires_at,
    v_idempotency_key
  )
  on conflict on constraint fidelizacion_operations_tenant_idempotency_key_key
    do nothing
  returning * into v_operacion;

  if v_operacion.id is null then
    select o.*
      into v_operacion
    from public.fidelizacion_operations o
    where o.tenant_id = v_tenant_id
      and o.idempotency_key = v_idempotency_key;

    if v_operacion.account_id <> p_account_id
      or v_operacion.tipo <> 'earn'
      or v_operacion.puntos <> p_puntos
      or v_operacion.reward_id is not null
      or v_operacion.expires_at is distinct from p_expires_at
    then
      raise exception using
        errcode = '23505',
        message = 'El idempotency_key ya fue usado con otros datos.';
    end if;
  end if;

  return query
  select
    v_operacion.id,
    v_operacion.puntos,
    v_operacion.estado,
    v_operacion.expires_at,
    v_operacion.created_at;
end;
$$;

create or replace function app_private.fidelizacion_obtener_earn_pendientes(
  p_public_qr_code text
)
returns table (
  operation_id uuid,
  puntos bigint,
  estado text,
  expires_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;

  return query
  select
    o.id,
    o.puntos,
    o.estado,
    o.expires_at,
    o.created_at
  from public.fidelizacion_tenants t
  join public.fidelizacion_accounts a
    on a.tenant_id = t.id
   and a.user_id = v_user_id
   and a.activo
  join public.fidelizacion_operations o
    on o.tenant_id = a.tenant_id
   and o.account_id = a.id
  where t.public_qr_code = p_public_qr_code
    and t.activo
    and o.tipo = 'earn'
    and o.estado = 'pending_customer'
    and (o.expires_at is null or o.expires_at > pg_catalog.now())
    and not exists (
      select 1
      from public.fidelizacion_point_movements m
      where m.operation_id = o.id
    )
  order by o.created_at, o.id;
end;
$$;

create or replace function app_private.fidelizacion_confirmar_earn(
  p_public_qr_code text,
  p_operation_id uuid
)
returns table (
  operation_id uuid,
  puntos bigint,
  estado text,
  confirmed_at timestamptz,
  saldo numeric
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
  v_account_id uuid;
  v_operacion public.fidelizacion_operations%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;

  select t.id, a.id
    into v_tenant_id, v_account_id
  from public.fidelizacion_tenants t
  join public.fidelizacion_accounts a
    on a.tenant_id = t.id
   and a.user_id = v_user_id
   and a.activo
  where t.public_qr_code = p_public_qr_code
    and t.activo
  for share of t, a;

  if v_tenant_id is null then
    raise exception using
      errcode = '42501',
      message = 'El QR no corresponde a una cuenta activa del cliente autenticado.';
  end if;

  select o.*
    into v_operacion
  from public.fidelizacion_operations o
  where o.id = p_operation_id
    and o.tenant_id = v_tenant_id
    and o.account_id = v_account_id
    and o.tipo = 'earn'
  for update;

  if v_operacion.id is null then
    raise exception using
      errcode = '42501',
      message = 'La operacion no esta disponible para el cliente autenticado.';
  end if;

  if v_operacion.estado = 'confirmed' then
    if not exists (
      select 1
      from public.fidelizacion_point_movements m
      where m.operation_id = v_operacion.id
        and m.tenant_id = v_operacion.tenant_id
        and m.account_id = v_operacion.account_id
        and m.tipo = 'earn'
        and m.puntos = v_operacion.puntos
    ) then
      raise exception using
        errcode = '23514',
        message = 'La operacion confirmada no tiene un movimiento consistente.';
    end if;

    return query
    select
      v_operacion.id,
      v_operacion.puntos,
      v_operacion.estado,
      v_operacion.confirmed_at,
      coalesce(sum(m.puntos), 0::numeric)
    from public.fidelizacion_point_movements m
    where m.tenant_id = v_operacion.tenant_id
      and m.account_id = v_operacion.account_id;
    return;
  end if;

  if v_operacion.estado <> 'pending_customer' then
    raise exception using
      errcode = '55000',
      message = 'La operacion no esta pendiente de confirmacion del cliente.';
  end if;

  if v_operacion.expires_at is not null and v_operacion.expires_at <= pg_catalog.now() then
    raise exception using errcode = '55000', message = 'La operacion esta expirada.';
  end if;

  insert into public.fidelizacion_point_movements (
    tenant_id,
    account_id,
    tipo,
    puntos,
    descripcion,
    operation_id
  )
  values (
    v_operacion.tenant_id,
    v_operacion.account_id,
    'earn',
    v_operacion.puntos,
    'Acreditacion confirmada por el cliente',
    v_operacion.id
  );

  update public.fidelizacion_operations o
  set estado = 'confirmed',
      confirmed_at = pg_catalog.now()
  where o.id = v_operacion.id
  returning o.* into v_operacion;

  return query
  select
    v_operacion.id,
    v_operacion.puntos,
    v_operacion.estado,
    v_operacion.confirmed_at,
    coalesce(sum(m.puntos), 0::numeric)
  from public.fidelizacion_point_movements m
  where m.tenant_id = v_operacion.tenant_id
    and m.account_id = v_operacion.account_id;
end;
$$;

create or replace function public.fidelizacion_crear_earn(
  p_account_id uuid,
  p_puntos bigint,
  p_idempotency_key text,
  p_expires_at timestamptz default null
)
returns table (
  operation_id uuid,
  puntos bigint,
  estado text,
  expires_at timestamptz,
  created_at timestamptz
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from app_private.fidelizacion_crear_earn(
    p_account_id,
    p_puntos,
    p_idempotency_key,
    p_expires_at
  );
$$;

create or replace function public.fidelizacion_obtener_earn_pendientes(
  p_public_qr_code text
)
returns table (
  operation_id uuid,
  puntos bigint,
  estado text,
  expires_at timestamptz,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from app_private.fidelizacion_obtener_earn_pendientes(p_public_qr_code);
$$;

create or replace function public.fidelizacion_confirmar_earn(
  p_public_qr_code text,
  p_operation_id uuid
)
returns table (
  operation_id uuid,
  puntos bigint,
  estado text,
  confirmed_at timestamptz,
  saldo numeric
)
language sql
security invoker
set search_path = ''
as $$
  select *
  from app_private.fidelizacion_confirmar_earn(
    p_public_qr_code,
    p_operation_id
  );
$$;

revoke all on function app_private.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  from public, anon;
revoke all on function app_private.fidelizacion_obtener_earn_pendientes(text)
  from public, anon;
revoke all on function app_private.fidelizacion_confirmar_earn(text, uuid)
  from public, anon;
revoke all on function public.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  from public, anon;
revoke all on function public.fidelizacion_obtener_earn_pendientes(text)
  from public, anon;
revoke all on function public.fidelizacion_confirmar_earn(text, uuid)
  from public, anon;

grant execute on function public.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  to authenticated;
grant execute on function public.fidelizacion_obtener_earn_pendientes(text)
  to authenticated;
grant execute on function public.fidelizacion_confirmar_earn(text, uuid)
  to authenticated;
grant usage on schema app_private to authenticated;
grant execute on function app_private.fidelizacion_crear_earn(uuid, bigint, text, timestamptz)
  to authenticated;
grant execute on function app_private.fidelizacion_obtener_earn_pendientes(text)
  to authenticated;
grant execute on function app_private.fidelizacion_confirmar_earn(text, uuid)
  to authenticated;

comment on function public.fidelizacion_crear_earn(uuid, bigint, text, timestamptz) is
  'Crea una operacion earn pendiente solo para staff activo del tenant de la cuenta.';
comment on function public.fidelizacion_obtener_earn_pendientes(text) is
  'Resuelve el QR estatico y lista earn pendientes de la cuenta autenticada sin mutar saldo.';
comment on function public.fidelizacion_confirmar_earn(text, uuid) is
  'Confirma una earn propia con bloqueo de fila y crea exactamente un movimiento positivo atomico.';
