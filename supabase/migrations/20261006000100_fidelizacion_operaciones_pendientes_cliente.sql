-- Fidelizacion: lectura authoritative de operaciones propias pendientes vigentes.

create or replace function app_private.fidelizacion_obtener_operaciones_pendientes(
  p_account_id uuid
)
returns table (
  id uuid,
  tipo text,
  estado text,
  puntos bigint,
  created_at timestamptz,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_tenant_id uuid;
begin
  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'Se requiere una sesion autenticada.';
  end if;

  if p_account_id is null then
    raise exception using
      errcode = '22023',
      message = 'La cuenta es obligatoria.';
  end if;

  select a.tenant_id
    into v_tenant_id
  from public.fidelizacion_accounts a
  where a.id = p_account_id;

  if v_tenant_id is null
    or not app_private.fidelizacion_es_cliente(v_tenant_id, p_account_id)
  then
    raise exception using
      errcode = '42501',
      message = 'La cuenta no esta disponible para el cliente autenticado.';
  end if;

  return query
  select
    o.id,
    o.tipo,
    o.estado,
    o.puntos,
    o.created_at,
    o.expires_at
  from public.fidelizacion_operations o
  where o.tenant_id = v_tenant_id
    and o.account_id = p_account_id
    and o.estado in ('pending_customer', 'pending_staff')
    and (o.expires_at is null or o.expires_at > pg_catalog.now())
  order by o.created_at desc, o.id desc;
end;
$$;

create or replace function public.fidelizacion_obtener_operaciones_pendientes(
  p_account_id uuid
)
returns table (
  id uuid,
  tipo text,
  estado text,
  puntos bigint,
  created_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from app_private.fidelizacion_obtener_operaciones_pendientes(p_account_id);
$$;

revoke all on function app_private.fidelizacion_obtener_operaciones_pendientes(uuid)
  from public, anon;
revoke all on function public.fidelizacion_obtener_operaciones_pendientes(uuid)
  from public, anon;

grant execute on function app_private.fidelizacion_obtener_operaciones_pendientes(uuid)
  to authenticated;
grant execute on function public.fidelizacion_obtener_operaciones_pendientes(uuid)
  to authenticated;

comment on function public.fidelizacion_obtener_operaciones_pendientes(uuid) is
  'Lista las operaciones pending_customer y pending_staff vigentes de la cuenta activa del cliente autenticado, usando la hora de PostgreSQL.';
