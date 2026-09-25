\set ON_ERROR_STOP on

-- Prueba local transaccional de canjes. Requiere Fases 1, 2 y 3 aplicadas.
begin;

insert into auth.users (id, email, aud, role) values
  ('01100000-0000-4000-8000-000000000001', 'fase3-cliente-a@example.invalid', 'authenticated', 'authenticated'),
  ('01100000-0000-4000-8000-000000000002', 'fase3-cliente-b@example.invalid', 'authenticated', 'authenticated'),
  ('01100000-0000-4000-8000-000000000003', 'fase3-staff-a@example.invalid', 'authenticated', 'authenticated'),
  ('01100000-0000-4000-8000-000000000004', 'fase3-staff-b@example.invalid', 'authenticated', 'authenticated'),
  ('01100000-0000-4000-8000-000000000005', 'fase3-cliente-c@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre, public_qr_code) values
  ('11100000-0000-4000-8000-000000000001', 'fase3-tenant-a', 'Fase 3 tenant A', 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'),
  ('11100000-0000-4000-8000-000000000002', 'fase3-tenant-b', 'Fase 3 tenant B', 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD');

insert into public.fidelizacion_accounts (id, tenant_id, user_id) values
  ('21100000-0000-4000-8000-000000000001', '11100000-0000-4000-8000-000000000001', '01100000-0000-4000-8000-000000000001'),
  ('21100000-0000-4000-8000-000000000002', '11100000-0000-4000-8000-000000000001', '01100000-0000-4000-8000-000000000002'),
  ('21100000-0000-4000-8000-000000000003', '11100000-0000-4000-8000-000000000002', '01100000-0000-4000-8000-000000000001'),
  ('21100000-0000-4000-8000-000000000004', '11100000-0000-4000-8000-000000000001', '01100000-0000-4000-8000-000000000005');

insert into public.fidelizacion_staff (tenant_id, user_id, rol) values
  ('11100000-0000-4000-8000-000000000001', '01100000-0000-4000-8000-000000000003', 'operador'),
  ('11100000-0000-4000-8000-000000000002', '01100000-0000-4000-8000-000000000004', 'admin');

insert into public.fidelizacion_rewards (id, tenant_id, nombre, puntos_requeridos, activa) values
  ('31100000-0000-4000-8000-000000000002', '11100000-0000-4000-8000-000000000001', 'Reward activa', 40, true),
  ('31100000-0000-4000-8000-000000000003', '11100000-0000-4000-8000-000000000001', 'Reward inactiva', 10, false),
  ('31100000-0000-4000-8000-000000000004', '11100000-0000-4000-8000-000000000002', 'Reward otro tenant', 10, true),
  ('31100000-0000-4000-8000-000000000005', '11100000-0000-4000-8000-000000000001', 'Reward costosa', 70, true),
  ('31100000-0000-4000-8000-000000000006', '11100000-0000-4000-8000-000000000001', 'Reward concurrente', 60, true),
  ('31100000-0000-4000-8000-000000000007', '11100000-0000-4000-8000-000000000001', 'Reward idempotente', 30, true),
  ('31100000-0000-4000-8000-000000000008', '11100000-0000-4000-8000-000000000001', 'Reward reserva', 100, true);

-- Saldo inicial de 100 para ambos clientes, derivado exclusivamente del ledger.
insert into public.fidelizacion_operations (id, tenant_id, account_id, tipo, puntos, estado, confirmed_at, idempotency_key) values
  ('41100000-0000-4000-8000-000000000001', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001', 'earn', 100, 'confirmed', now(), 'fase3-earn-a'),
  ('41100000-0000-4000-8000-000000000002', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000002', 'earn', 100, 'confirmed', now(), 'fase3-earn-b'),
  ('41100000-0000-4000-8000-000000000006', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000004', 'earn', 180, 'confirmed', now(), 'fase3-earn-c');
insert into public.fidelizacion_point_movements (tenant_id, account_id, tipo, puntos, operation_id) values
  ('11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001', 'earn', 100, '41100000-0000-4000-8000-000000000001'),
  ('11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000002', 'earn', 100, '41100000-0000-4000-8000-000000000002'),
  ('11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000004', 'earn', 180, '41100000-0000-4000-8000-000000000006');

-- Cliente A crea una intencion, repite idempotentemente y conserva el costo original.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000002', 'fase3-redeem-a', null);
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000002', 'fase3-redeem-a', null);
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000004', 'fase3-redeem-b', null);

do $$
declare
  v_expires_at timestamptz;
begin
  select expires_at into v_expires_at
  from public.fidelizacion_operations
  where tenant_id = '11100000-0000-4000-8000-000000000001'
    and idempotency_key = 'fase3-redeem-a';

  if v_expires_at not between pg_catalog.now() + interval '14 minutes'
    and pg_catalog.now() + interval '16 minutes' then
    raise exception 'El redeem sin expiracion no recibio el vencimiento server-side esperado.';
  end if;
end $$;

do $$
begin
  begin
    perform * from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000003', 'fase3-inactiva', null);
    raise exception 'Una recompensa inactiva fue aceptada.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  begin
    perform * from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000004', 'fase3-otro-tenant', null);
    raise exception 'Una recompensa sin cuenta activa en su tenant fue aceptada.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

do $$
begin
  if not exists (
    select 1 from public.fidelizacion_operations
    where idempotency_key = 'fase3-redeem-a'
      and tenant_id = '11100000-0000-4000-8000-000000000001'
      and account_id = '21100000-0000-4000-8000-000000000001'
  ) or not exists (
    select 1 from public.fidelizacion_operations
    where idempotency_key = 'fase3-redeem-b'
      and tenant_id = '11100000-0000-4000-8000-000000000002'
      and account_id = '21100000-0000-4000-8000-000000000003'
  ) then
    raise exception 'La recompensa no resolvio la cuenta activa del tenant correcto.';
  end if;
end $$;

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

-- Un reintento idempotente no depende de que la recompensa siga activa.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000007', 'fase3-recompensa-desactivada', null);
reset role;
update public.fidelizacion_rewards set activa = false where id = '31100000-0000-4000-8000-000000000007';
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$
declare
  v_operacion_original uuid;
  v_operacion_reintentada uuid;
begin
  select id into v_operacion_original
  from public.fidelizacion_operations
  where idempotency_key = 'fase3-recompensa-desactivada';
  select operation_id into v_operacion_reintentada
  from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000007', 'fase3-recompensa-desactivada', null);
  if v_operacion_reintentada is distinct from v_operacion_original then
    raise exception 'El reintento no devolvio la operacion original.';
  end if;
  begin
    perform * from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000007', 'fase3-recompensa-inactiva-nueva', null);
    raise exception 'Una recompensa desactivada creo una operacion nueva.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$
begin
  if (select count(*) from public.fidelizacion_operations where idempotency_key = 'fase3-recompensa-desactivada' and puntos = 30) <> 1 then
    raise exception 'El reintento con recompensa desactivada no devolvio la operacion original.';
  end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select * from public.fidelizacion_cancelar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-recompensa-desactivada'));
reset role;

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

insert into public.fidelizacion_operations (id, tenant_id, account_id, tipo, puntos, reward_id, estado, expires_at, created_at, idempotency_key) values
  ('41100000-0000-4000-8000-000000000003', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001', 'redeem', 40, '31100000-0000-4000-8000-000000000002', 'pending_customer', now() - interval '1 hour', now() - interval '2 hours', 'fase3-expirada');
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', '41100000-0000-4000-8000-000000000003');
    raise exception 'Una operacion expirada fue escaneada.';
  exception when object_not_in_prerequisite_state then null; end;
end $$;
reset role;

-- La reserva pendiente reduce el saldo disponible, pero no el saldo contable.
insert into public.fidelizacion_operations (id, tenant_id, account_id, tipo, puntos, reward_id, estado, expires_at, idempotency_key) values
  ('41100000-0000-4000-8000-000000000007', '11100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000004', 'redeem', 100, '31100000-0000-4000-8000-000000000008', 'pending_customer', now() - interval '1 minute', 'fase3-reserva-expirada');
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000005","role":"authenticated"}', true);
set local role authenticated;
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000008', 'fase3-reserva-primera', null);
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000008', 'fase3-reserva-primera', null);
do $$
declare
  v_saldo_confirmado bigint;
  v_reservado bigint;
begin
  select coalesce(sum(puntos), 0) into v_saldo_confirmado
  from public.fidelizacion_point_movements
  where account_id = '21100000-0000-4000-8000-000000000004';
  select coalesce(sum(puntos), 0) into v_reservado
  from public.fidelizacion_operations
  where account_id = '21100000-0000-4000-8000-000000000004'
    and tipo = 'redeem'
    and estado in ('pending_customer', 'pending_staff')
    and (expires_at is null or expires_at > now());
  if v_saldo_confirmado <> 180 or v_reservado <> 100 or v_saldo_confirmado - v_reservado <> 80 then
    raise exception 'La reserva no dejo 180 confirmados y 80 disponibles.';
  end if;
  begin
    perform * from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000008', 'fase3-reserva-segunda', null);
    raise exception 'Un segundo canje supero el saldo disponible.';
  exception when check_violation then null; end;
end $$;
select * from public.fidelizacion_cancelar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-reserva-primera'));
select operation_id from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000008', 'fase3-reserva-liberada', null);
select * from public.fidelizacion_escanear_redeem('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC', (select id from public.fidelizacion_operations where idempotency_key = 'fase3-reserva-liberada'));
reset role;
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select * from public.fidelizacion_confirmar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-reserva-liberada'));
select * from public.fidelizacion_confirmar_redeem((select id from public.fidelizacion_operations where idempotency_key = 'fase3-reserva-liberada'));
reset role;
do $$
declare v_operation_id uuid := (select id from public.fidelizacion_operations where idempotency_key = 'fase3-reserva-liberada');
begin
  if (select count(*) from public.fidelizacion_point_movements where operation_id = v_operation_id and tipo = 'redeem' and puntos = -100) <> 1
    or (select coalesce(sum(puntos), 0) from public.fidelizacion_point_movements where account_id = '21100000-0000-4000-8000-000000000004') <> 80 then
    raise exception 'La confirmacion de la reserva no genero un unico debito de 100 puntos.';
  end if;
end $$;

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

-- Saldo insuficiente se rechaza al crear la reserva y no deja artefactos parciales.
select set_config('request.jwt.claims', '{"sub":"01100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform * from public.fidelizacion_crear_redeem('31100000-0000-4000-8000-000000000005', 'fase3-sin-saldo', null);
    raise exception 'Un canje supero el saldo disponible al crearse.';
  exception when check_violation then null; end;
end $$;
reset role;

do $$
begin
  if exists (select 1 from public.fidelizacion_operations where idempotency_key = 'fase3-sin-saldo') then
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
declare
  v_definicion text;
  v_cuenta_lock integer;
begin
  select pg_catalog.lower(pg_get_functiondef('app_private.fidelizacion_confirmar_redeem(uuid)'::regprocedure)) into v_definicion;
  v_cuenta_lock := pg_catalog.position('perform 1 from public.fidelizacion_accounts' in v_definicion);
  if v_cuenta_lock = 0
    or pg_catalog.position('where o.id = p_operation_id and o.tipo = ''redeem''' in pg_catalog.substr(v_definicion, v_cuenta_lock)) = 0
    or pg_catalog.position('sum(m.puntos)' in v_definicion) < v_cuenta_lock then
    raise exception 'La confirmacion no conserva el orden cuenta-operacion antes de recalcular el saldo.';
  end if;
end $$;

do $$
declare
  v_definicion text;
  v_cuenta_lock integer;
  v_reserva integer;
begin
  select pg_catalog.lower(pg_get_functiondef('app_private.fidelizacion_crear_redeem(uuid,text,timestamp with time zone)'::regprocedure)) into v_definicion;
  v_cuenta_lock := pg_catalog.position('from public.fidelizacion_accounts a' in v_definicion);
  v_reserva := pg_catalog.position('sum(o.puntos)' in v_definicion);
  if v_cuenta_lock = 0
    or pg_catalog.position('for update' in pg_catalog.substr(v_definicion, v_cuenta_lock)) = 0
    or v_reserva < v_cuenta_lock
    or pg_catalog.position('o.estado in (''pending_customer'', ''pending_staff'')' in v_definicion) = 0
    or pg_catalog.position('insert into public.fidelizacion_operations' in v_definicion) < v_reserva then
    raise exception 'La creacion de canje no bloquea la cuenta antes de reservar el saldo disponible.';
  end if;
end $$;

rollback;
