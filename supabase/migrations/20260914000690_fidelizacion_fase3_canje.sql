-- Fidelizacion Fase 3: canje redeem seguro, atomico e idempotente.
-- Se inserta antes de M07 y no modifica el dominio legacy.

alter table public.fidelizacion_operations
  add constraint fidelizacion_operations_tenant_id_account_reward_puntos_key
  unique (tenant_id, id, account_id, reward_id, puntos);

alter table public.fidelizacion_redemptions
  add constraint fidelizacion_redemptions_operation_puntos_fkey
  foreign key (tenant_id, operation_id, account_id, reward_id, puntos_requeridos)
  references public.fidelizacion_operations (tenant_id, id, account_id, reward_id, puntos)
  on delete restrict,
  add constraint fidelizacion_redemptions_confirmed_check check (estado = 'confirmed');

create or replace function app_private.fidelizacion_validar_integridad_redeem_confirmada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_operation_id uuid;
  v_operacion public.fidelizacion_operations%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := pg_catalog.to_jsonb(old);
  else
    v_row := pg_catalog.to_jsonb(new);
  end if;
  v_operation_id := coalesce(
    (v_row ->> 'operation_id')::uuid,
    (v_row ->> 'id')::uuid
  );

  select o.*
    into v_operacion
  from public.fidelizacion_operations o
  where o.id = v_operation_id;

  if v_operacion.id is null or v_operacion.tipo <> 'redeem' then
    return null;
  end if;

  if v_operacion.estado = 'confirmed' then
    if not exists (
      select 1
      from public.fidelizacion_redemptions r
      where r.operation_id = v_operacion.id
        and r.tenant_id = v_operacion.tenant_id
        and r.account_id = v_operacion.account_id
        and r.reward_id = v_operacion.reward_id
        and r.puntos_requeridos = v_operacion.puntos
        and r.estado = 'confirmed'
    ) or not exists (
      select 1
      from public.fidelizacion_point_movements m
      where m.operation_id = v_operacion.id
        and m.tenant_id = v_operacion.tenant_id
        and m.account_id = v_operacion.account_id
        and m.tipo = 'redeem'
        and m.puntos = v_operacion.puntos_movimiento
    ) then
      raise exception using
        errcode = '23514',
        message = 'Un canje confirmado requiere una redencion y un movimiento consistentes.';
    end if;
  elsif exists (
    select 1
    from public.fidelizacion_redemptions r
    where r.operation_id = v_operacion.id
  ) or exists (
    select 1
    from public.fidelizacion_point_movements m
    where m.operation_id = v_operacion.id
  ) then
    raise exception using
      errcode = '23514',
      message = 'Un canje no confirmado no puede tener redencion ni movimiento.';
  end if;

  return null;
end;
$$;

create constraint trigger fidelizacion_operations_redeem_integridad_confirmada
after insert or update or delete on public.fidelizacion_operations
deferrable initially deferred
for each row execute function app_private.fidelizacion_validar_integridad_redeem_confirmada();

create constraint trigger fidelizacion_redemptions_redeem_integridad_confirmada
after insert or update or delete on public.fidelizacion_redemptions
deferrable initially deferred
for each row execute function app_private.fidelizacion_validar_integridad_redeem_confirmada();

create constraint trigger fidelizacion_point_movements_redeem_integridad_confirmada
after insert or update or delete on public.fidelizacion_point_movements
deferrable initially deferred
for each row execute function app_private.fidelizacion_validar_integridad_redeem_confirmada();

create or replace function app_private.fidelizacion_crear_redeem(
  p_reward_id uuid,
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
  v_idempotency_key text := pg_catalog.btrim(p_idempotency_key);
  v_tenant_id uuid;
  v_account_id uuid;
  v_puntos bigint;
  v_operacion public.fidelizacion_operations%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;

  if p_reward_id is null or v_idempotency_key is null or v_idempotency_key = '' then
    raise exception using errcode = '22023', message = 'Recompensa e idempotency_key validos son obligatorios.';
  end if;

  if p_expires_at is not null and p_expires_at <= pg_catalog.now() then
    raise exception using errcode = '22023', message = 'La expiracion debe ser futura.';
  end if;

  select a.tenant_id, a.id
    into v_tenant_id, v_account_id
  from public.fidelizacion_accounts a
  join public.fidelizacion_tenants t on t.id = a.tenant_id and t.activo
  where a.user_id = v_user_id and a.activo
  for share of a, t;

  if v_account_id is null then
    raise exception using
      errcode = '42501', message = 'No existe una cuenta activa para el cliente autenticado.';
  end if;

  select o.* into v_operacion
  from public.fidelizacion_operations o
  where o.tenant_id = v_tenant_id and o.idempotency_key = v_idempotency_key;
  if v_operacion.id is not null then
    if v_operacion.account_id <> v_account_id
      or v_operacion.tipo <> 'redeem'
      or v_operacion.reward_id <> p_reward_id
      or v_operacion.expires_at is distinct from p_expires_at
    then
      raise exception using errcode = '23505', message = 'El idempotency_key ya fue usado con otros datos.';
    end if;
    return query select v_operacion.id, v_operacion.puntos, v_operacion.estado,
      v_operacion.expires_at, v_operacion.created_at;
    return;
  end if;

  select r.puntos_requeridos into v_puntos
  from public.fidelizacion_rewards r
  where r.tenant_id = v_tenant_id and r.id = p_reward_id and r.activa
  for share;
  if v_puntos is null then
    raise exception using
      errcode = '42501', message = 'La recompensa no esta activa para la cuenta del cliente.';
  end if;

  insert into public.fidelizacion_operations (
    tenant_id, account_id, tipo, puntos, reward_id, estado, expires_at, idempotency_key
  ) values (
    v_tenant_id, v_account_id, 'redeem', v_puntos, p_reward_id,
    'pending_customer', p_expires_at, v_idempotency_key
  )
  on conflict on constraint fidelizacion_operations_tenant_idempotency_key_key do nothing
  returning * into v_operacion;

  if v_operacion.id is null then
    select o.* into v_operacion
    from public.fidelizacion_operations o
    where o.tenant_id = v_tenant_id and o.idempotency_key = v_idempotency_key;

    if v_operacion.account_id <> v_account_id
      or v_operacion.tipo <> 'redeem'
      or v_operacion.reward_id <> p_reward_id
      or v_operacion.expires_at is distinct from p_expires_at
    then
      raise exception using errcode = '23505', message = 'El idempotency_key ya fue usado con otros datos.';
    end if;
  end if;

  return query select v_operacion.id, v_operacion.puntos, v_operacion.estado,
    v_operacion.expires_at, v_operacion.created_at;
end;
$$;

create or replace function app_private.fidelizacion_escanear_redeem(
  p_public_qr_code text,
  p_operation_id uuid
)
returns table (operation_id uuid, puntos bigint, estado text, expires_at timestamptz)
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

  select t.id, a.id into v_tenant_id, v_account_id
  from public.fidelizacion_tenants t
  join public.fidelizacion_accounts a
    on a.tenant_id = t.id and a.user_id = v_user_id and a.activo
  where t.public_qr_code = p_public_qr_code and t.activo
  for update of a;

  if v_account_id is null then
    raise exception using errcode = '42501', message = 'El QR no corresponde a una cuenta activa del cliente autenticado.';
  end if;

  select o.* into v_operacion
  from public.fidelizacion_operations o
  where o.id = p_operation_id and o.tenant_id = v_tenant_id
    and o.account_id = v_account_id and o.tipo = 'redeem'
  for update;

  if v_operacion.id is null then
    raise exception using errcode = '42501', message = 'La operacion no esta disponible para el cliente autenticado.';
  end if;

  if v_operacion.estado = 'pending_staff' then
    return query select v_operacion.id, v_operacion.puntos, v_operacion.estado, v_operacion.expires_at;
    return;
  end if;

  if v_operacion.estado <> 'pending_customer' then
    raise exception using errcode = '55000', message = 'La operacion no esta pendiente de escaneo del cliente.';
  end if;

  if v_operacion.expires_at is not null and v_operacion.expires_at <= pg_catalog.now() then
    raise exception using errcode = '55000', message = 'La operacion esta expirada.';
  end if;

  update public.fidelizacion_operations o
  set estado = 'pending_staff'
  where o.id = v_operacion.id
  returning o.* into v_operacion;

  return query select v_operacion.id, v_operacion.puntos, v_operacion.estado, v_operacion.expires_at;
end;
$$;

create or replace function app_private.fidelizacion_confirmar_redeem(p_operation_id uuid)
returns table (
  operation_id uuid,
  redemption_id uuid,
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
  v_operacion public.fidelizacion_operations%rowtype;
  v_redemption_id uuid;
  v_saldo numeric;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;

  select o.* into v_operacion
  from public.fidelizacion_operations o
  where o.id = p_operation_id and o.tipo = 'redeem'
  for update;

  if v_operacion.id is null or not exists (
    select 1 from public.fidelizacion_staff s
    join public.fidelizacion_tenants t on t.id = s.tenant_id and t.activo
    where s.tenant_id = v_operacion.tenant_id and s.user_id = v_user_id
      and s.activo and s.rol in ('admin', 'operador')
  ) then
    raise exception using errcode = '42501', message = 'La operacion no esta disponible para el staff autenticado.';
  end if;

  perform 1 from public.fidelizacion_accounts a
  where a.id = v_operacion.account_id and a.tenant_id = v_operacion.tenant_id and a.activo
  for update;
  if not found then
    raise exception using errcode = '42501', message = 'La cuenta no esta activa para confirmar el canje.';
  end if;

  if v_operacion.estado = 'confirmed' then
    select r.id into v_redemption_id from public.fidelizacion_redemptions r
    where r.operation_id = v_operacion.id and r.tenant_id = v_operacion.tenant_id
      and r.account_id = v_operacion.account_id and r.reward_id = v_operacion.reward_id
      and r.puntos_requeridos = v_operacion.puntos and r.estado = 'confirmed';
    if v_redemption_id is null or not exists (
      select 1 from public.fidelizacion_point_movements m
      where m.operation_id = v_operacion.id and m.tenant_id = v_operacion.tenant_id
        and m.account_id = v_operacion.account_id and m.tipo = 'redeem'
        and m.puntos = v_operacion.puntos_movimiento
    ) then
      raise exception using errcode = '23514', message = 'La operacion confirmada no tiene artefactos consistentes.';
    end if;
  elsif v_operacion.estado <> 'pending_staff' then
    raise exception using errcode = '55000', message = 'La operacion no esta pendiente de confirmacion del staff.';
  elsif v_operacion.expires_at is not null and v_operacion.expires_at <= pg_catalog.now() then
    raise exception using errcode = '55000', message = 'La operacion esta expirada.';
  else
    select coalesce(sum(m.puntos), 0::numeric) into v_saldo
    from public.fidelizacion_point_movements m
    where m.tenant_id = v_operacion.tenant_id and m.account_id = v_operacion.account_id;
    if v_saldo < v_operacion.puntos then
      raise exception using errcode = '23514', message = 'Saldo insuficiente para confirmar el canje.';
    end if;

    insert into public.fidelizacion_redemptions (
      tenant_id, account_id, reward_id, operation_id, puntos_requeridos, estado
    ) values (
      v_operacion.tenant_id, v_operacion.account_id, v_operacion.reward_id,
      v_operacion.id, v_operacion.puntos, 'confirmed'
    ) returning id into v_redemption_id;

    insert into public.fidelizacion_point_movements (
      tenant_id, account_id, tipo, puntos, descripcion, operation_id
    ) values (
      v_operacion.tenant_id, v_operacion.account_id, 'redeem', v_operacion.puntos_movimiento,
      'Canje confirmado por el staff', v_operacion.id
    );

    update public.fidelizacion_operations o
    set estado = 'confirmed', confirmed_at = pg_catalog.now()
    where o.id = v_operacion.id
    returning o.* into v_operacion;
  end if;

  select coalesce(sum(m.puntos), 0::numeric) into v_saldo
  from public.fidelizacion_point_movements m
  where m.tenant_id = v_operacion.tenant_id and m.account_id = v_operacion.account_id;

  return query select v_operacion.id, v_redemption_id, v_operacion.puntos,
    v_operacion.estado, v_operacion.confirmed_at, v_saldo;
end;
$$;

create or replace function app_private.fidelizacion_cancelar_redeem(p_operation_id uuid)
returns table (operation_id uuid, estado text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_operacion public.fidelizacion_operations%rowtype;
  v_es_cliente boolean;
  v_es_staff boolean;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;

  select o.* into v_operacion
  from public.fidelizacion_operations o
  where o.id = p_operation_id and o.tipo = 'redeem'
  for update;
  if v_operacion.id is null then
    raise exception using errcode = '42501', message = 'La operacion no esta disponible.';
  end if;

  v_es_cliente := app_private.fidelizacion_es_cliente(v_operacion.tenant_id, v_operacion.account_id);
  v_es_staff := app_private.fidelizacion_es_staff(v_operacion.tenant_id, array['admin', 'operador']);
  if not v_es_cliente and not v_es_staff then
    raise exception using errcode = '42501', message = 'La operacion no esta disponible para el usuario autenticado.';
  end if;
  if v_operacion.estado = 'confirmed' then
    raise exception using errcode = '55000', message = 'Un canje confirmado no puede cancelarse.';
  end if;
  if v_operacion.estado = 'pending_customer' and not v_es_cliente then
    raise exception using errcode = '42501', message = 'Solo el cliente puede cancelar antes del escaneo.';
  end if;
  if v_operacion.estado = 'pending_staff' and not v_es_staff then
    raise exception using errcode = '42501', message = 'Solo el staff puede cancelar despues del escaneo.';
  end if;
  if v_operacion.estado not in ('pending_customer', 'pending_staff') then
    raise exception using errcode = '55000', message = 'La operacion no puede cancelarse en su estado actual.';
  end if;

  update public.fidelizacion_operations o set estado = 'cancelled'
  where o.id = v_operacion.id returning o.* into v_operacion;
  return query select v_operacion.id, v_operacion.estado;
end;
$$;

create or replace function public.fidelizacion_crear_redeem(p_reward_id uuid, p_idempotency_key text, p_expires_at timestamptz default null)
returns table (operation_id uuid, puntos bigint, estado text, expires_at timestamptz, created_at timestamptz)
language sql security definer set search_path = '' as $$
  select * from app_private.fidelizacion_crear_redeem(p_reward_id, p_idempotency_key, p_expires_at);
$$;

create or replace function public.fidelizacion_escanear_redeem(p_public_qr_code text, p_operation_id uuid)
returns table (operation_id uuid, puntos bigint, estado text, expires_at timestamptz)
language sql security definer set search_path = '' as $$
  select * from app_private.fidelizacion_escanear_redeem(p_public_qr_code, p_operation_id);
$$;

create or replace function public.fidelizacion_confirmar_redeem(p_operation_id uuid)
returns table (operation_id uuid, redemption_id uuid, puntos bigint, estado text, confirmed_at timestamptz, saldo numeric)
language sql security definer set search_path = '' as $$
  select * from app_private.fidelizacion_confirmar_redeem(p_operation_id);
$$;

create or replace function public.fidelizacion_cancelar_redeem(p_operation_id uuid)
returns table (operation_id uuid, estado text)
language sql security definer set search_path = '' as $$
  select * from app_private.fidelizacion_cancelar_redeem(p_operation_id);
$$;

revoke all on function app_private.fidelizacion_validar_integridad_redeem_confirmada() from public;
revoke all on function app_private.fidelizacion_crear_redeem(uuid, text, timestamptz) from public, anon;
revoke all on function app_private.fidelizacion_escanear_redeem(text, uuid) from public, anon;
revoke all on function app_private.fidelizacion_confirmar_redeem(uuid) from public, anon;
revoke all on function app_private.fidelizacion_cancelar_redeem(uuid) from public, anon;
revoke all on function public.fidelizacion_crear_redeem(uuid, text, timestamptz) from public, anon;
revoke all on function public.fidelizacion_escanear_redeem(text, uuid) from public, anon;
revoke all on function public.fidelizacion_confirmar_redeem(uuid) from public, anon;
revoke all on function public.fidelizacion_cancelar_redeem(uuid) from public, anon;

grant execute on function public.fidelizacion_crear_redeem(uuid, text, timestamptz) to authenticated;
grant execute on function public.fidelizacion_escanear_redeem(text, uuid) to authenticated;
grant execute on function public.fidelizacion_confirmar_redeem(uuid) to authenticated;
grant execute on function public.fidelizacion_cancelar_redeem(uuid) to authenticated;

comment on function public.fidelizacion_crear_redeem(uuid, text, timestamptz) is
  'Crea una intencion redeem propia desde una recompensa activa y congela su costo.';
comment on function public.fidelizacion_escanear_redeem(text, uuid) is
  'El QR estatico solo valida el tenant y avanza un redeem propio a pending_staff sin descontar puntos.';
comment on function public.fidelizacion_confirmar_redeem(uuid) is
  'Confirma un redeem por staff autorizado, serializa por cuenta y crea redencion y movimiento negativo atomicos.';
comment on function public.fidelizacion_cancelar_redeem(uuid) is
  'Cancela un redeem pendiente con autorizacion segun el estado y sin crear movimientos.';
