create or replace function app_private.fidelizacion_listar_clientes_staff(p_busqueda text, p_limite integer, p_offset integer, p_account_id uuid default null)
returns table (account_id uuid, cliente_email text, saldo numeric)
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tenant uuid;
  v_count bigint;
  v_busqueda text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_busqueda, '')));
begin
  if v_user is null then
    raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 50 or p_offset is null or p_offset < 0 or p_offset > 100000 or pg_catalog.length(v_busqueda) > 254 then
    raise exception using errcode = '22023', message = 'Parametros de paginacion o busqueda invalidos.';
  end if;
  select pg_catalog.count(*), (pg_catalog.array_agg(s.tenant_id order by s.tenant_id))[1]
    into v_count, v_tenant
  from public.fidelizacion_staff s
  join public.fidelizacion_tenants t on t.id = s.tenant_id and t.activo
  where s.user_id = v_user and s.activo and s.rol in ('admin', 'operador');
  if v_count <> 1 then
    raise exception using errcode = '42501', message = 'No existe un acceso unico de staff habilitado.';
  end if;
  return query
  select a.id, pg_catalog.btrim(u.email),
    coalesce((select pg_catalog.sum(m.puntos) from public.fidelizacion_point_movements m
      where m.tenant_id = a.tenant_id and m.account_id = a.id), 0::numeric)
  from public.fidelizacion_accounts a
  join auth.users u on u.id = a.user_id
  where a.tenant_id = v_tenant and a.activo
    and (p_account_id is null or a.id = p_account_id)
    and (v_busqueda = '' or pg_catalog.strpos(pg_catalog.lower(u.email), v_busqueda) > 0)
  order by pg_catalog.lower(u.email) nulls last, a.id
  limit p_limite offset p_offset;
end;
$$;

create or replace function public.fidelizacion_listar_clientes_staff(p_busqueda text, p_limite integer, p_offset integer, p_account_id uuid default null)
returns table (account_id uuid, cliente_email text, saldo numeric)
language sql stable security invoker set search_path = ''
as $$ select * from app_private.fidelizacion_listar_clientes_staff(p_busqueda, p_limite, p_offset, p_account_id); $$;

revoke all on function app_private.fidelizacion_listar_clientes_staff(text, integer, integer, uuid) from public, anon;
revoke all on function public.fidelizacion_listar_clientes_staff(text, integer, integer, uuid) from public, anon;
grant execute on function app_private.fidelizacion_listar_clientes_staff(text, integer, integer, uuid) to authenticated;
grant execute on function public.fidelizacion_listar_clientes_staff(text, integer, integer, uuid) to authenticated;
