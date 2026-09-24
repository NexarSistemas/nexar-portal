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
  v_expires_at timestamptz := coalesce(
    p_expires_at,
    pg_catalog.now() + interval '15 minutes'
  );
  v_tenant_id uuid;
  v_account_id uuid;
  v_puntos bigint;
  v_saldo_confirmado numeric;
  v_puntos_reservados numeric;
  v_operacion public.fidelizacion_operations%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;

  if p_reward_id is null or v_idempotency_key is null or v_idempotency_key = '' then
    raise exception using errcode = '22023', message = 'Recompensa e idempotency_key validos son obligatorios.';
  end if;

  if v_expires_at <= pg_catalog.now() then
    raise exception using errcode = '22023', message = 'La expiracion debe ser futura.';
  end if;

  select r.tenant_id into v_tenant_id
  from public.fidelizacion_rewards r
  join public.fidelizacion_tenants t on t.id = r.tenant_id and t.activo
  where r.id = p_reward_id
  for share of r, t;

  if v_tenant_id is null then
    raise exception using
      errcode = '42501', message = 'La recompensa no esta activa para el cliente autenticado.';
  end if;

  select a.id into v_account_id
  from public.fidelizacion_accounts a
  where a.tenant_id = v_tenant_id and a.user_id = v_user_id and a.activo
  for update;

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
      or (p_expires_at is not null and v_operacion.expires_at is distinct from p_expires_at)
    then
      raise exception using errcode = '23505', message = 'El idempotency_key ya fue usado con otros datos.';
    end if;
    return query select v_operacion.id, v_operacion.puntos, v_operacion.estado,
      v_operacion.expires_at, v_operacion.created_at;
    return;
  end if;

  select r.puntos_requeridos into v_puntos
  from public.fidelizacion_rewards r
  where r.id = p_reward_id and r.tenant_id = v_tenant_id and r.activa
  for share;
  if v_puntos is null then
    raise exception using
      errcode = '42501', message = 'La recompensa no esta activa para crear un canje.';
  end if;

  select coalesce(sum(m.puntos), 0) into v_saldo_confirmado
  from public.fidelizacion_point_movements m
  where m.tenant_id = v_tenant_id and m.account_id = v_account_id;

  select coalesce(sum(o.puntos), 0) into v_puntos_reservados
  from public.fidelizacion_operations o
  where o.tenant_id = v_tenant_id
    and o.account_id = v_account_id
    and o.tipo = 'redeem'
    and o.estado in ('pending_customer', 'pending_staff')
    and (o.expires_at is null or o.expires_at > pg_catalog.now());

  if v_saldo_confirmado - v_puntos_reservados < v_puntos then
    raise exception using
      errcode = '23514', message = 'Saldo disponible insuficiente para crear el canje.';
  end if;

  insert into public.fidelizacion_operations (
    tenant_id, account_id, tipo, puntos, reward_id, estado, expires_at, idempotency_key
  ) values (
    v_tenant_id, v_account_id, 'redeem', v_puntos, p_reward_id,
    'pending_customer', v_expires_at, v_idempotency_key
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
      or (p_expires_at is not null and v_operacion.expires_at is distinct from p_expires_at)
    then
      raise exception using errcode = '23505', message = 'El idempotency_key ya fue usado con otros datos.';
    end if;
  end if;

  return query select v_operacion.id, v_operacion.puntos, v_operacion.estado,
    v_operacion.expires_at, v_operacion.created_at;
end;
$$;
