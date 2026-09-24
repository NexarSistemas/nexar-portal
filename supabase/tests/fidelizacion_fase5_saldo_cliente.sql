\set ON_ERROR_STOP on

-- Prueba local transaccional del saldo atomico para clientes de Fidelizacion.
begin;

insert into auth.users (id, email, aud, role)
values
  ('01400000-0000-4000-8000-000000000001', 'fase5-saldo-cliente-a@example.invalid', 'authenticated', 'authenticated'),
  ('01400000-0000-4000-8000-000000000002', 'fase5-saldo-cliente-b@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre, activo, public_qr_code)
values
  ('11400000-0000-4000-8000-000000000001', 'fase5-saldo-a', 'Fase 5 saldo A', true, 'JJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJJ'),
  ('11400000-0000-4000-8000-000000000002', 'fase5-saldo-cero', 'Fase 5 saldo cero', true, 'KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK'),
  ('11400000-0000-4000-8000-000000000003', 'fase5-saldo-b', 'Fase 5 saldo B', true, 'LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL'),
  ('11400000-0000-4000-8000-000000000004', 'fase5-saldo-cuenta-inactiva', 'Fase 5 saldo cuenta inactiva', true, 'MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM'),
  ('11400000-0000-4000-8000-000000000005', 'fase5-saldo-tenant-inactivo', 'Fase 5 saldo tenant inactivo', false, 'NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN');

insert into public.fidelizacion_accounts (id, tenant_id, user_id, activo)
values
  ('21400000-0000-4000-8000-000000000001', '11400000-0000-4000-8000-000000000001', '01400000-0000-4000-8000-000000000001', true),
  ('21400000-0000-4000-8000-000000000002', '11400000-0000-4000-8000-000000000002', '01400000-0000-4000-8000-000000000001', true),
  ('21400000-0000-4000-8000-000000000003', '11400000-0000-4000-8000-000000000003', '01400000-0000-4000-8000-000000000002', true),
  ('21400000-0000-4000-8000-000000000004', '11400000-0000-4000-8000-000000000004', '01400000-0000-4000-8000-000000000001', false),
  ('21400000-0000-4000-8000-000000000005', '11400000-0000-4000-8000-000000000005', '01400000-0000-4000-8000-000000000001', true);

insert into public.fidelizacion_rewards (id, tenant_id, nombre, puntos_requeridos)
values (
  '31400000-0000-4000-8000-000000000001',
  '11400000-0000-4000-8000-000000000001',
  'Recompensa saldo cliente',
  40
);

insert into public.fidelizacion_operations
  (id, tenant_id, account_id, tipo, puntos, reward_id, estado, confirmed_at, idempotency_key)
values
  ('41400000-0000-4000-8000-000000000001', '11400000-0000-4000-8000-000000000001', '21400000-0000-4000-8000-000000000001', 'earn', 150, null, 'confirmed', now(), 'fase5-saldo-earn'),
  ('41400000-0000-4000-8000-000000000002', '11400000-0000-4000-8000-000000000001', '21400000-0000-4000-8000-000000000001', 'redeem', 40, '31400000-0000-4000-8000-000000000001', 'confirmed', now(), 'fase5-saldo-redeem');

insert into public.fidelizacion_point_movements
  (id, tenant_id, account_id, tipo, puntos, operation_id)
values
  ('51400000-0000-4000-8000-000000000001', '11400000-0000-4000-8000-000000000001', '21400000-0000-4000-8000-000000000001', 'earn', 150, '41400000-0000-4000-8000-000000000001'),
  ('51400000-0000-4000-8000-000000000002', '11400000-0000-4000-8000-000000000001', '21400000-0000-4000-8000-000000000001', 'redeem', -40, '41400000-0000-4000-8000-000000000002');

insert into public.fidelizacion_redemptions
  (id, tenant_id, account_id, reward_id, operation_id, puntos_requeridos, estado)
values (
  '61400000-0000-4000-8000-000000000001',
  '11400000-0000-4000-8000-000000000001',
  '21400000-0000-4000-8000-000000000001',
  '31400000-0000-4000-8000-000000000001',
  '41400000-0000-4000-8000-000000000002',
  40,
  'confirmed'
);

insert into public.fidelizacion_operations
  (tenant_id, account_id, tipo, puntos, estado, confirmed_at, idempotency_key)
select
  '11400000-0000-4000-8000-000000000001',
  '21400000-0000-4000-8000-000000000001',
  'earn',
  1,
  'confirmed',
  now(),
  'fase5-saldo-lote-' || serie
from generate_series(1, 120) as serie;

insert into public.fidelizacion_point_movements
  (tenant_id, account_id, tipo, puntos, operation_id)
select
  o.tenant_id,
  o.account_id,
  'earn',
  1,
  o.id
from public.fidelizacion_operations o
where o.idempotency_key like 'fase5-saldo-lote-%';

-- El cliente A ve saldo cero, earn/redeem y los mas de 100 movimientos en una RPC.
select set_config('request.jwt.claims', '{"sub":"01400000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if public.fidelizacion_obtener_saldo_cliente('21400000-0000-4000-8000-000000000002') <> 0 then
    raise exception 'Una cuenta activa sin movimientos no devolvio saldo cero.';
  end if;

  if public.fidelizacion_obtener_saldo_cliente('21400000-0000-4000-8000-000000000001') <> 230 then
    raise exception 'El saldo no incluyo earn, redeem y mas de 100 movimientos.';
  end if;

  begin
    perform public.fidelizacion_obtener_saldo_cliente('21400000-0000-4000-8000-000000000003');
    raise exception 'El cliente consulto una cuenta de otro usuario o tenant.';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.fidelizacion_obtener_saldo_cliente('21400000-0000-4000-8000-000000000004');
    raise exception 'El cliente consulto una cuenta inactiva.';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.fidelizacion_obtener_saldo_cliente('21400000-0000-4000-8000-000000000005');
    raise exception 'El cliente consulto una cuenta de tenant inactivo.';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;

-- El cliente B solo accede a su propia cuenta.
select set_config('request.jwt.claims', '{"sub":"01400000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  if public.fidelizacion_obtener_saldo_cliente('21400000-0000-4000-8000-000000000003') <> 0 then
    raise exception 'El cliente no pudo consultar su propia cuenta activa.';
  end if;

  begin
    perform public.fidelizacion_obtener_saldo_cliente('21400000-0000-4000-8000-000000000001');
    raise exception 'El cliente B consulto la cuenta del cliente A.';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;
rollback;
