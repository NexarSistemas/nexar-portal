-- Fidelizacion Fase 6: caducidad server-side por defecto para operaciones nuevas.
-- No modifica operaciones existentes ni transiciona automaticamente su estado.

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
  v_expires_at timestamptz := pg_catalog.coalesce(
    p_expires_at,
    pg_catalog.now() + interval '15 minutes'
  );
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

  if v_expires_at <= pg_catalog.now() then
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
    tenant_id, account_id, tipo, puntos, estado, expires_at, idempotency_key
  ) values (
    v_tenant_id, p_account_id, 'earn', p_puntos, 'pending_customer',
    v_expires_at, v_idempotency_key
  )
  on conflict on constraint fidelizacion_operations_tenant_idempotency_key_key
    do nothing
  returning * into v_operacion;

  if v_operacion.id is null then
    select o.* into v_operacion
    from public.fidelizacion_operations o
    where o.tenant_id = v_tenant_id
      and o.idempotency_key = v_idempotency_key;

    if v_operacion.account_id <> p_account_id
      or v_operacion.tipo <> 'earn'
      or v_operacion.puntos <> p_puntos
      or v_operacion.reward_id is not null
      or (p_expires_at is not null and v_operacion.expires_at is distinct from p_expires_at)
    then
      raise exception using
        errcode = '23505',
        message = 'El idempotency_key ya fue usado con otros datos.';
    end if;
  end if;

  return query
  select v_operacion.id, v_operacion.puntos, v_operacion.estado,
    v_operacion.expires_at, v_operacion.created_at;
end;
$$;

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
  v_expires_at timestamptz := pg_catalog.coalesce(
    p_expires_at,
    pg_catalog.now() + interval '15 minutes'
  );
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
  for share;

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

grant execute on function app_private.fidelizacion_crear_redeem(uuid, text, timestamptz)
  to authenticated;
grant execute on function app_private.fidelizacion_escanear_redeem(text, uuid)
  to authenticated;
grant execute on function app_private.fidelizacion_confirmar_redeem(uuid)
  to authenticated;
grant execute on function app_private.fidelizacion_cancelar_redeem(uuid)
  to authenticated;
