\set ON_ERROR_STOP on

-- Prueba local transaccional del contrato de lectura para el panel operador.
begin;

insert into auth.users (id, email, aud, role)
values
  ('01200000-0000-4000-8000-000000000001', 'Cliente.Fase4@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000002', 'fase4-saldo-cero@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000003', 'fase4-cliente-b@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000004', 'fase4-cuenta-inactiva@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000005', 'fase4-operador-a@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000006', 'fase4-admin-a@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000007', 'fase4-sin-staff@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000008', 'fase4-staff-inactivo@example.invalid', 'authenticated', 'authenticated'),
  ('01200000-0000-4000-8000-000000000009', 'fase4-staff-tenant-inactivo@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre, activo, public_qr_code)
values
  ('11200000-0000-4000-8000-000000000001', 'fase4-tenant-a', 'Fase 4 tenant A', true, 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD'),
  ('11200000-0000-4000-8000-000000000002', 'fase4-tenant-b', 'Fase 4 tenant B', true, 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE'),
  ('11200000-0000-4000-8000-000000000003', 'fase4-tenant-inactivo', 'Fase 4 tenant inactivo', false, 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF');

insert into public.fidelizacion_accounts (id, tenant_id, user_id, activo)
values
  ('21200000-0000-4000-8000-000000000001', '11200000-0000-4000-8000-000000000001', '01200000-0000-4000-8000-000000000001', true),
  ('21200000-0000-4000-8000-000000000002', '11200000-0000-4000-8000-000000000001', '01200000-0000-4000-8000-000000000002', true),
  ('21200000-0000-4000-8000-000000000003', '11200000-0000-4000-8000-000000000002', '01200000-0000-4000-8000-000000000003', true),
  ('21200000-0000-4000-8000-000000000004', '11200000-0000-4000-8000-000000000001', '01200000-0000-4000-8000-000000000004', false);

insert into public.fidelizacion_staff (tenant_id, user_id, rol, activo)
values
  ('11200000-0000-4000-8000-000000000001', '01200000-0000-4000-8000-000000000005', 'operador', true),
  ('11200000-0000-4000-8000-000000000001', '01200000-0000-4000-8000-000000000006', 'admin', true),
  ('11200000-0000-4000-8000-000000000001', '01200000-0000-4000-8000-000000000008', 'operador', false),
  ('11200000-0000-4000-8000-000000000003', '01200000-0000-4000-8000-000000000009', 'operador', true);

insert into public.fidelizacion_rewards (id, tenant_id, nombre, puntos_requeridos)
values
  ('31200000-0000-4000-8000-000000000001', '11200000-0000-4000-8000-000000000001', 'Recompensa Fase 4', 30);

insert into public.fidelizacion_operations
  (id, tenant_id, account_id, tipo, puntos, reward_id, estado, confirmed_at, idempotency_key)
values
  ('41200000-0000-4000-8000-000000000001', '11200000-0000-4000-8000-000000000001', '21200000-0000-4000-8000-000000000001', 'earn', 100, null, 'confirmed', now(), 'fase4-earn-confirmada'),
  ('41200000-0000-4000-8000-000000000002', '11200000-0000-4000-8000-000000000001', '21200000-0000-4000-8000-000000000001', 'redeem', 30, '31200000-0000-4000-8000-000000000001', 'confirmed', now(), 'fase4-redeem-confirmado');

insert into public.fidelizacion_point_movements
  (id, tenant_id, account_id, tipo, puntos, operation_id)
values
  ('51200000-0000-4000-8000-000000000001', '11200000-0000-4000-8000-000000000001', '21200000-0000-4000-8000-000000000001', 'earn', 100, '41200000-0000-4000-8000-000000000001'),
  ('51200000-0000-4000-8000-000000000002', '11200000-0000-4000-8000-000000000001', '21200000-0000-4000-8000-000000000001', 'redeem', -30, '41200000-0000-4000-8000-000000000002');

insert into public.fidelizacion_redemptions
  (id, tenant_id, account_id, reward_id, operation_id, puntos_requeridos, estado)
values
  ('61200000-0000-4000-8000-000000000001', '11200000-0000-4000-8000-000000000001', '21200000-0000-4000-8000-000000000001', '31200000-0000-4000-8000-000000000001', '41200000-0000-4000-8000-000000000002', 30, 'confirmed');

-- Operador: email normalizado, saldo derivado, saldo cero y no enumeracion.
select set_config('request.jwt.claims', '{"sub":"01200000-0000-4000-8000-000000000005","role":"authenticated"}', true);
set local role authenticated;

do $$
declare
  v_result record;
begin
  select * into v_result
  from public.fidelizacion_buscar_cuenta_staff('  CLIENTE.FASE4@EXAMPLE.INVALID  ');
  if v_result.account_id <> '21200000-0000-4000-8000-000000000001'
    or v_result.cliente_email <> 'Cliente.Fase4@example.invalid'
    or v_result.saldo <> 70
  then
    raise exception 'El operador no obtuvo la cuenta normalizada y su saldo derivado.';
  end if;

  select * into v_result
  from public.fidelizacion_buscar_cuenta_staff('fase4-saldo-cero@example.invalid');
  if v_result.account_id <> '21200000-0000-4000-8000-000000000002'
    or v_result.saldo <> 0
  then
    raise exception 'Una cuenta sin movimientos no devolvio saldo cero.';
  end if;

  if exists (select 1 from public.fidelizacion_buscar_cuenta_staff('fase4-cliente-b@example.invalid'))
    or exists (select 1 from public.fidelizacion_buscar_cuenta_staff('no-existe@example.invalid'))
    or exists (select 1 from public.fidelizacion_buscar_cuenta_staff('fase4-cuenta-inactiva@example.invalid'))
  then
    raise exception 'La busqueda revelo otra cuenta, una cuenta inexistente o una cuenta inactiva.';
  end if;
end
$$;

reset role;

-- Admin del mismo tenant recibe el mismo contrato de lectura.
select set_config('request.jwt.claims', '{"sub":"01200000-0000-4000-8000-000000000006","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if not exists (
    select 1
    from public.fidelizacion_buscar_cuenta_staff('cliente.fase4@example.invalid')
    where saldo = 70
  ) then
    raise exception 'El admin activo no encontro la cuenta de su tenant.';
  end if;
end
$$;

reset role;

-- Usuarios sin staff efectivo son rechazados sin acceso a auth.users.
select set_config('request.jwt.claims', '{"sub":"01200000-0000-4000-8000-000000000007","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  begin
    perform * from public.fidelizacion_buscar_cuenta_staff('Cliente.Fase4@example.invalid');
    raise exception 'Un usuario sin staff pudo buscar cuentas.';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;

select set_config('request.jwt.claims', '{"sub":"01200000-0000-4000-8000-000000000008","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  begin
    perform * from public.fidelizacion_buscar_cuenta_staff('Cliente.Fase4@example.invalid');
    raise exception 'Un staff inactivo pudo buscar cuentas.';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;

select set_config('request.jwt.claims', '{"sub":"01200000-0000-4000-8000-000000000009","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  begin
    perform * from public.fidelizacion_buscar_cuenta_staff('Cliente.Fase4@example.invalid');
    raise exception 'El staff de un tenant inactivo pudo buscar cuentas.';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;

rollback;
