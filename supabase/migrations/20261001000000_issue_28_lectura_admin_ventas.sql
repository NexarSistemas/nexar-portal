-- Issue #28: lectura administrativa mínima de relaciones canónicas por venta.
-- Conserva la exposición histórica existente y no modifica registros legacy.

create or replace function app_private.licencias_admin_por_venta(p_venta_id uuid)
returns table (license_key text, producto text, plan text, plan_vendido text, expira timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.'; end if;
  if p_venta_id is null then raise exception using errcode = '22023', message = 'La venta es obligatoria.'; end if;
  if not app_private.es_admin() then raise exception using errcode = '42501', message = 'El perfil no tiene acceso administrativo.'; end if;
  return query
  select l.license_key::text, l.producto::text, l.plan::text, l.plan_vendido::text, l.expira::timestamptz, l.created_at::timestamptz
  from public.licencias l
  where l.venta_id = p_venta_id
    or exists (select 1 from public.venta_items vi where vi.id = l.venta_item_id and vi.venta_id = p_venta_id);
end;
$$;

create or replace function public.licencias_admin_por_venta(p_venta_id uuid)
returns table (license_key text, producto text, plan text, plan_vendido text, expira timestamptz, created_at timestamptz)
language sql stable security invoker set search_path = ''
as $$ select * from app_private.licencias_admin_por_venta(p_venta_id); $$;

create or replace function app_private.comisiones_admin_por_venta(p_venta_id uuid)
returns table (tipo text, producto text, license_key text, monto numeric, estado text, created_at timestamptz, paid_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception using errcode = '28000', message = 'Se requiere una sesion autenticada.'; end if;
  if p_venta_id is null then raise exception using errcode = '22023', message = 'La venta es obligatoria.'; end if;
  if not app_private.es_admin() then raise exception using errcode = '42501', message = 'El perfil no tiene acceso administrativo.'; end if;
  return query
  select c.tipo::text, c.producto::text, c.license_key::text, c.monto, c.estado::text, c.created_at::timestamptz, c.paid_at::timestamptz
  from public.comisiones c
  where c.venta_id = p_venta_id
    or exists (select 1 from public.pagos p where p.id = c.pago_id and p.venta_id = p_venta_id);
end;
$$;

create or replace function public.comisiones_admin_por_venta(p_venta_id uuid)
returns table (tipo text, producto text, license_key text, monto numeric, estado text, created_at timestamptz, paid_at timestamptz)
language sql stable security invoker set search_path = ''
as $$ select * from app_private.comisiones_admin_por_venta(p_venta_id); $$;

revoke all on function app_private.licencias_admin_por_venta(uuid) from public, anon;
revoke all on function public.licencias_admin_por_venta(uuid) from public, anon;
revoke all on function app_private.comisiones_admin_por_venta(uuid) from public, anon;
revoke all on function public.comisiones_admin_por_venta(uuid) from public, anon;
grant execute on function app_private.licencias_admin_por_venta(uuid) to authenticated;
grant execute on function public.licencias_admin_por_venta(uuid) to authenticated;
grant execute on function app_private.comisiones_admin_por_venta(uuid) to authenticated;
grant execute on function public.comisiones_admin_por_venta(uuid) to authenticated;

comment on function public.licencias_admin_por_venta(uuid) is 'Devuelve licencias históricas vinculadas canónicamente a una venta para un administrador autenticado.';
comment on function public.comisiones_admin_por_venta(uuid) is 'Devuelve comisiones históricas vinculadas canónicamente a una venta para un administrador autenticado.';
