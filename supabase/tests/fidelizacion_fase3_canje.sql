\set ON_ERROR_STOP on

-- Prueba local transaccional de canjes. Requiere Fases 1, 2 y 3 aplicadas.
begin;

insert into auth.users (id, email, aud, role) values
  ('01100000-0000-4000-8000-000000000001', 'fase3-cliente-a@example.invalid', 'authenticated', 'authenticated'),
  ('01100000-0000-4000-8000-000000000002', 'fase3-cliente-b@example.invalid', 'authenticated', 'authenticated'),
  ('01100000-0000-4000-8000-000000000003', 'fase3-staff-a@example.invalid', 'authenticated', 'authenticated'),
  ('01100000-0000-4000-8000-000000000004', 'fase3-staff-b@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre, public_qr_code) values
  ('11100000-0000-4000-8000-000000000001', 'fase3-tenant-a', 'Fase 3 tenant A', 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'),
  ('11100000-0000-4000-8000-000000000002', 'fase3-tenant-b', 'Fase 3 tenant B', 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD');

insert into public.fidelizacion_accounts (id, tenant_id, user_id) values
  ('21100000-0000-4000-8000-000000000001', '11100000-0000-4000-8000-000000000001', '01100000-0000-4000-8000-000000000001'),
  ('21100000-0000-4000-8000-000000000002', '11100000-0000-4000-8000-000000000001', '01100000-0000-4000-8000-000000000002');

insert into public.fidelizacion_staff (tenant_id, user_id, rol) values
  ('11100000-0000-4000-8000-000000000001', '01100000-0000-4000-8000-000000000003', 'operador'),
  ('11100000-0000-4000-8000-000000000002', '01100000-0000-4000-8000-000000000004', 'admin');

insert into public.fidelizacion_rewards (id, tenant_id, nombre, puntos_requeridos, activa) values
  ('31100000-0000-4000-8000-000000000002', '11100000-0000-4000-8000-000000000001', 'Reward activa', 40, true),
  ('31100000-0000-4000-8000-000000000003', '11100000-0000-4000-8000-000000000001', 'Reward inactiva', 10, false),
  ('31100000-0000-4000-8000-000000000004', '11100000-0000-4000-8000-000000000002', 'Reward otro tenant', 10, true),
  ('31100000-0000-4000-8000-000000000005', '11100000-0000-4000-8000-000000000001', 'Reward costosa', 70, true),
  ('31100000-0000-4000-8000-000000000006', '11100000-0000-4000-8000-000000000001', 'Reward concurrente', 60, true);

-- Saldo inicial de 100 para ambos clientes, derivado exclusivamente del ledger.
insert into public.fidelizacion_operations (id, tenant_id, account_id, tipo, puntos, estado, confirmed_at, idempotency_key) values
  ('41100000-0000-4000-8000-000000000001', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001', 'earn', 100, 'confirmed', now(), 'fase3-earn-a'),
  ('41100000-0000-4000-8000-000000000002', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000002', 'earn', 100, 'confirmed', now(), 'fase3-earn-b');
insert into public.fidelizacion_point_movements (tenant_id, account_id, tipo, puntos, operation_id) values
  ('11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001', 'earn', 100, '41100000-0000-4000-8000-000000000001'),
  ('11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000002', 'earn', 100, '41100000-0000-4000-8000-000000000002');

-- Cliente A crea una intencion, repite idempotentemente y conserva el costo original.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000002', 'fase3-redeem-a', null);
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000002', 'fase3-redeem-a', null);

do $$
begin
  begin
    perform * from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000004', 'fase3-otro-tenant', null);
    raise exception 'Una recompensa de otro tenant fue aceptada.';
  exception when insufficient_privilege then null; end;
  begin
    perform * from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000003', 'fase3-inactiva', null);
    raise exception 'Una recompensa inactiva fue aceptada.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

update public.fidelizacion_rewards set puntos_requeridos = 45 where id = '31100000-0000-4000-8000-000000000002';
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000002', 'fase3-redeem-a', null);
reset role;
do $$
begin
  if (select count(*) from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a' and puntos = 40) <> 1 then
    raise exception 'El costo aplicado no quedo congelado en la operacion.';
  end if;
end $$;

-- El QR correcto solo avanza el estado; QR ajeno y expiracion se rechazan.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', (select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
do $$
begin
  if exists (select 1 from public.fidelizacion_point_movements where account_id = '21100000-0000-4000-8000-000000000001' and tipo = 'redeem') then
    raise exception 'El escaneo del QR desconto puntos.';
  end if;
  begin
    perform * from public.fidelizacion_escanear_redeem('DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD', (select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
    raise exception 'El QR de otro tenant fue aceptado.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', (select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
    raise exception 'Un cliente ajeno escaneo una operacion conocida.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

insert into public.fidelizacion_operations (id, tenant_id, account_id, tipo, puntos, reward_id, estado, expires_at, idempotency_key) values
  ('41100000-0000-4000-8000-000000000003', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001', 'redeem', 40, '31100000-0000-4000-8000-000000000002', 'pending_customer', now() - interval '1 hour', 'fase3-expirada');
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', '41100000-0000-4000-8000-000000000003');
    raise exception 'Una operacion expirada fue escaneada.';
  exception when object_not_in_prerequisite_state then null; end;
end $$;
reset role;

-- Solo el staff del tenant confirma; repetir no duplica el debito ni la redencion.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000004","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_confirmar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
    raise exception 'Staff de otro tenant confirmo el canje.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select * from public.fidelizacion_confirmar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
select * from public.fidelizacion_confirmar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
reset role;

do $$
declare v_operation_id uuid := (select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a');
begin
  if (select count(*) from public.fidelizacion_redemptions where operation_id = v_operation_id) <> 1
    or (select count(*) from public.fidelizacion_point_movements where operation_id = v_operation_id and tipo = 'redeem' and puntos = -40) <> 1
    or (select coalesce(sum(puntos), 0) from public.fidelizacion_point_movements where account_id = '21100000-0000-4000-8000-000000000001') <> 60 then
    raise exception 'El canje confirmado no preservo redencion, debito unico y saldo final correctos.';
  end if;
end $$;

select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', (select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
    raise exception 'Un canje confirmado se reutilizo mediante el QR.';
  exception when object_not_in_prerequisite_state then null; end;
end $$;
reset role;

-- Saldo insuficiente deja la operacion pending_staff sin artefactos parciales.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000005', 'fase3-sin-saldo', null);
select * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', (select id from public.fidelizacion_operations where idempotency_key = 'fase3-sin-saldo'));
reset role;
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_confirmar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-sin-saldo'));
    raise exception 'Un canje con saldo insuficiente fue confirmado.';
  exception when check_violation then null; end;
end $$;
reset role;

do $$
declare v_operation_id uuid := (select id from public.fidelizacion_operations where idempotency_key = 'fase3-sin-saldo');
begin
  if exists (select 1 from public.fidelizacion_redemptions where operation_id = v_operation_id)
    or exists (select 1 from public.fidelizacion_point_movements where operation_id = v_operation_id)
    or not exists (select 1 from public.fidelizacion_operations where id = v_operation_id and estado = 'pending_staff') then
    raise exception 'El saldo insuficiente dejo efectos parciales.';
  end if;
end $$;

-- Un fallo tras insertar artefactos revierte redencion, movimiento y estado.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000002', 'fase3-atomicidad', null);
select * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', (select id from public.fidelizacion_operations where idempotency_key = 'fase3-atomicidad'));
reset role;
create function pg_temp.fidelizacion_fase3_fallar_confirmacion()
returns trigger language plpgsql as $$
begin
  if new.id = (select id from public.fidelizacion_operations where idempotency_key = 'fase3-atomicidad')
    and new.estado = 'confirmed' then
    raise exception 'fallo controlado de atomicidad fase 3';
  end if;
  return new;
end;
$$;
create trigger fidelizacion_fase3_fallo_atomico
before update of estado on public.fidelizacion_operations
for each row execute function pg_temp.fidelizacion_fase3_fallar_confirmacion();
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_confirmar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-atomicidad'));
    raise exception 'La confirmacion no activo el fallo controlado.';
  exception when raise_exception then
    if sqlerrm <> 'fallo controlado de atomicidad fase 3' then raise; end if;
  end;
end $$;
reset role;
drop trigger fidelizacion_fase3_fallo_atomico on public.fidelizacion_operations;
do $$
declare v_operation_id uuid := (select id from public.fidelizacion_operations where idempotency_key = 'fase3-atomicidad');
begin
  if exists (select 1 from public.fidelizacion_redemptions where operation_id = v_operation_id)
    or exists (select 1 from public.fidelizacion_point_movements where operation_id = v_operation_id)
    or not exists (select 1 from public.fidelizacion_operations where id = v_operation_id and estado = 'pending_staff') then
    raise exception 'El fallo controlado dejo estado parcial.';
  end if;
end $$;

-- Cancelacion: cliente antes de escanear; un confirmado no puede cancelarse.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000002', 'fase3-cancelar', null);
select * from public.fidelizacion_cancelar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-cancelar'));
do $$ begin
  begin
    perform * from public.fidelizacion_cancelar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-redeem-a'));
    raise exception 'Un canje confirmado pudo cancelarse.';
  exception when object_not_in_prerequisite_state then null; end;
end $$;
reset role;

-- Dos canjes distintos contra 100 puntos: el segundo queda rechazado tras el primero.
insert into public.fidelizacion_operations (id, tenant_id, account_id, tipo, puntos, reward_id, estado, idempotency_key) values
  ('41100000-0000-4000-8000-000000000004', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000002', 'redeem', 60, '31100000-0000-4000-8000-000000000006', 'pending_staff', 'fase3-concurrencia-1'),
  ('41100000-0000-4000-8000-000000000005', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000002', 'redeem', 60, '31100000-0000-4000-8000-000000000006', 'pending_staff', 'fase3-concurrencia-2');
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select * from public.fidelizacion_confirmar_redeem('41100000-0000-4000-8000-000000000004');
do $$ begin
  begin
    perform * from public.fidelizacion_confirmar_redeem('41100000-0000-4000-8000-000000000005');
    raise exception 'Dos canjes agotaron un saldo de 100 puntos.';
  exception when check_violation then null; end;
end $$;
reset role;

-- La prueba estructural cubre la serializacion de llamadas concurrentes reales por cuenta.
do $$
declare v_definicion text;
begin
  select pg_catalog.lower(pg_get_functiondef('app_private.fidelizacion_confirmar_redeem(uuid)'::regprocedure)) into v_definicion;
  if pg_catalog.position('for update' in v_definicion) = 0
    or pg_catalog.position('sum(m.puntos)' in v_definicion) < pg_catalog.position('for update' in v_definicion) then
    raise exception 'La confirmacion no bloquea antes de recalcular el saldo.';
  end if;
end $$;

rollback;
