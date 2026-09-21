\set ON_ERROR_STOP on

-- Prueba local transaccional: crea fixtures sinteticos, valida RLS/integridad y revierte todo.
begin;

insert into auth.users (id, email, aud, role)
values
  ('00000000-0000-4000-8000-000000000001', 'fidelizacion-cliente-a@example.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000002', 'fidelizacion-cliente-b@example.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000003', 'fidelizacion-staff-a@example.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000004', 'fidelizacion-sin-pertenencia@example.invalid', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-000000000005', 'fidelizacion-staff-b@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre)
values
  ('10000000-0000-4000-8000-000000000001', 'tenant-prueba-a', 'Tenant prueba A'),
  ('10000000-0000-4000-8000-000000000002', 'tenant-prueba-b', 'Tenant prueba B');

insert into public.fidelizacion_accounts (id, tenant_id, user_id)
values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002'),
  ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000002');

insert into public.fidelizacion_staff (tenant_id, user_id, rol, activo)
values
  ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000003', 'admin', true),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000004', 'operador', false),
  ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000005', 'operador', true);

insert into public.fidelizacion_rewards (id, tenant_id, nombre, puntos_requeridos)
values
  ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Recompensa A', 10),
  ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Recompensa B', 20);

insert into public.fidelizacion_operations
  (id, tenant_id, account_id, tipo, puntos, reward_id, estado, confirmed_at, idempotency_key)
values
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'earn', 25, null, 'confirmed', now(), 'prueba-earn-a1'),
  ('40000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', 'earn', 30, null, 'confirmed', now(), 'prueba-earn-a2'),
  ('40000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000003', 'earn', 40, null, 'confirmed', now(), 'prueba-earn-b'),
  ('40000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'redeem', 10, '30000000-0000-4000-8000-000000000001', 'confirmed', now(), 'prueba-redeem-a1');

-- Pares validos: earn 25 -> +25 y redeem 10 -> -10.
insert into public.fidelizacion_point_movements
  (id, tenant_id, account_id, tipo, puntos, operation_id)
values
  ('50000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'earn', 25, '40000000-0000-4000-8000-000000000001'),
  ('50000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', 'earn', 30, '40000000-0000-4000-8000-000000000002'),
  ('50000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000003', 'earn', 40, '40000000-0000-4000-8000-000000000003'),
  ('50000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'redeem', -10, '40000000-0000-4000-8000-000000000004');

insert into public.fidelizacion_redemptions
  (id, tenant_id, account_id, reward_id, operation_id, puntos_requeridos, estado)
values
  ('60000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000004', 10, 'confirmed');

do $$
declare
  codigos_distintos boolean;
begin
  select count(distinct public_qr_code) = 2
         and bool_and(length(public_qr_code) = 32)
         and bool_and(public_qr_code ~ '^[A-Za-z0-9_-]{32}$')
  into codigos_distintos
  from public.fidelizacion_tenants;

  if not codigos_distintos then
    raise exception 'Los public_qr_code deben ser unicos y base64url de 192 bits sin padding.';
  end if;
end
$$;

-- Cliente A: solo su cuenta y sus datos privados, aun con IDs ajenos conocidos.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.fidelizacion_tenants) <> 1
    or (select count(*) from public.fidelizacion_accounts) <> 1
    or (select count(*) from public.fidelizacion_staff) <> 0
    or (select count(*) from public.fidelizacion_rewards) <> 1
    or (select count(*) from public.fidelizacion_operations) <> 2
    or (select count(*) from public.fidelizacion_point_movements) <> 2
    or (select count(*) from public.fidelizacion_redemptions) <> 1
  then
    raise exception 'RLS no aisla correctamente al cliente A.';
  end if;

  if exists (
    select 1 from public.fidelizacion_accounts
    where id in (
      '20000000-0000-4000-8000-000000000002',
      '20000000-0000-4000-8000-000000000003'
    )
  ) then
    raise exception 'El cliente A pudo leer una cuenta ajena mediante un ID conocido.';
  end if;

  begin
    update public.fidelizacion_accounts set activo = false
    where id = '20000000-0000-4000-8000-000000000001';
    raise exception 'authenticated obtuvo escritura directa indebida.';
  exception
    when insufficient_privilege then null;
  end;
end
$$;

reset role;

-- Staff A: ve todas las filas de su tenant y ninguna del tenant B.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.fidelizacion_tenants) <> 1
    or (select count(*) from public.fidelizacion_accounts) <> 2
    or (select count(*) from public.fidelizacion_staff) <> 1
    or (select count(*) from public.fidelizacion_rewards) <> 1
    or (select count(*) from public.fidelizacion_operations) <> 3
    or (select count(*) from public.fidelizacion_point_movements) <> 3
    or (select count(*) from public.fidelizacion_redemptions) <> 1
  then
    raise exception 'RLS no aisla correctamente al staff del tenant A.';
  end if;

  if exists (
    select 1 from public.fidelizacion_operations
    where id = '40000000-0000-4000-8000-000000000003'
  ) then
    raise exception 'El staff A pudo atravesar al tenant B mediante un ID conocido.';
  end if;
end
$$;

reset role;

-- Staff B operador: solo ve el tenant B; su rol no concede acceso al tenant A.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000005","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.fidelizacion_tenants) <> 1
    or (select count(*) from public.fidelizacion_accounts) <> 1
    or (select count(*) from public.fidelizacion_staff) <> 1
    or (select count(*) from public.fidelizacion_rewards) <> 1
    or (select count(*) from public.fidelizacion_operations) <> 1
    or (select count(*) from public.fidelizacion_point_movements) <> 1
    or (select count(*) from public.fidelizacion_redemptions) <> 0
  then
    raise exception 'RLS no aisla correctamente al staff operador del tenant B.';
  end if;

  if exists (
    select 1 from public.fidelizacion_operations
    where id = '40000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'El staff B pudo atravesar al tenant A mediante un ID conocido.';
  end if;
end
$$;

reset role;

-- Usuario autenticado sin cuenta ni staff: no ve datos privados.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if exists (select 1 from public.fidelizacion_tenants)
    or exists (select 1 from public.fidelizacion_accounts)
    or exists (select 1 from public.fidelizacion_staff)
    or exists (select 1 from public.fidelizacion_rewards)
    or exists (select 1 from public.fidelizacion_operations)
    or exists (select 1 from public.fidelizacion_point_movements)
    or exists (select 1 from public.fidelizacion_redemptions)
  then
    raise exception 'Un usuario sin pertenencia pudo leer datos privados.';
  end if;
end
$$;

reset role;

-- Anon no tiene acceso por grants, antes de que RLS pueda conceder filas.
set local role anon;
do $$
begin
  begin
    perform 1 from public.fidelizacion_tenants limit 1;
    raise exception 'anon obtuvo SELECT indebido.';
  exception
    when insufficient_privilege then null;
  end;
end
$$;
reset role;

-- Integridad: duplicados e IDs cross-tenant fallan incluso como rol privilegiado.
do $$
declare
  v_constraint_name text;
begin
  begin
    insert into public.fidelizacion_accounts (tenant_id, user_id)
    values ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001');
    raise exception 'No se aplico UNIQUE (tenant_id, user_id).';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.fidelizacion_staff (tenant_id, user_id, rol)
    values ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000004', 'gerente');
    raise exception 'fidelizacion_staff acepto un rol fuera de admin/operador.';
  exception
    when check_violation then null;
  end;

  begin
    insert into public.fidelizacion_operations
      (tenant_id, account_id, tipo, puntos, estado, idempotency_key)
    values
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'earn', 1, 'pending_customer', 'prueba-earn-a1');
    raise exception 'No se aplico la idempotencia por tenant.';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.fidelizacion_operations
      (tenant_id, account_id, tipo, puntos, estado, idempotency_key)
    values
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000003', 'earn', 1, 'pending_customer', 'cross-tenant');
    raise exception 'Una operacion acepto una cuenta de otro tenant.';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.fidelizacion_operations
      (tenant_id, account_id, tipo, puntos, reward_id, estado, idempotency_key)
    values
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'redeem', 20, '30000000-0000-4000-8000-000000000002', 'pending_staff', 'cross-tenant-reward');
    raise exception 'Una operacion acepto una recompensa de otro tenant.';
  exception
    when foreign_key_violation then null;
  end;

  insert into public.fidelizacion_operations
    (id, tenant_id, account_id, tipo, puntos, estado, confirmed_at, idempotency_key)
  values
    ('40000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'earn', 5, 'confirmed', now(), 'cross-account-movement');

  -- Operacion redeem sin redencion previa, reservada al test FK cross-tenant.
  insert into public.fidelizacion_operations
    (id, tenant_id, account_id, tipo, puntos, reward_id, estado, confirmed_at, idempotency_key)
  values
    ('40000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'redeem', 10, '30000000-0000-4000-8000-000000000001', 'confirmed', now(), 'cross-tenant-redemption');

  insert into public.fidelizacion_operations
    (id, tenant_id, account_id, tipo, puntos, reward_id, estado, confirmed_at, idempotency_key)
  values
    ('40000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'earn', 25, null, 'confirmed', now(), 'earn-points-mismatch'),
    ('40000000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'redeem', 10, '30000000-0000-4000-8000-000000000001', 'confirmed', now(), 'redeem-points-mismatch');

  begin
    insert into public.fidelizacion_point_movements
      (tenant_id, account_id, tipo, puntos, operation_id)
    values
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002', 'earn', 5, '40000000-0000-4000-8000-000000000005');
    raise exception 'Un movimiento acepto una cuenta distinta de su operacion.';
  exception
    when foreign_key_violation then null;
  end;

  begin
    insert into public.fidelizacion_point_movements
      (tenant_id, account_id, tipo, puntos, operation_id)
    values
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'earn', 25, '40000000-0000-4000-8000-000000000001');
    raise exception 'Una operacion confirmada genero un segundo movimiento.';
  exception
    when unique_violation then null;
  end;

  begin
    insert into public.fidelizacion_point_movements
      (tenant_id, account_id, tipo, puntos, operation_id)
    values
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'earn', 1, '40000000-0000-4000-8000-000000000007');
    raise exception 'Un movimiento earn acepto puntos distintos de su operacion.';
  exception
    when foreign_key_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name <> 'fidelizacion_point_movements_operation_fkey' then
        raise exception 'El earn fallo por una constraint inesperada: %.', v_constraint_name;
      end if;
  end;

  begin
    insert into public.fidelizacion_point_movements
      (tenant_id, account_id, tipo, puntos, operation_id)
    values
      ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'redeem', -5, '40000000-0000-4000-8000-000000000008');
    raise exception 'Un movimiento redeem acepto puntos distintos de su operacion.';
  exception
    when foreign_key_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name <> 'fidelizacion_point_movements_operation_fkey' then
        raise exception 'El redeem fallo por una constraint inesperada: %.', v_constraint_name;
      end if;
  end;

  begin
    insert into public.fidelizacion_redemptions
      (tenant_id, account_id, reward_id, operation_id, puntos_requeridos, estado)
    values
      ('10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000006', 20, 'confirmed');
    raise exception 'Una redencion acepto una operacion de otro tenant.';
  exception
    when foreign_key_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name <> 'fidelizacion_redemptions_operation_fkey' then
        raise exception 'La redencion cross-tenant fallo por una constraint inesperada: %.', v_constraint_name;
      end if;
  end;

  begin
    insert into public.fidelizacion_tenants (slug, nombre, public_qr_code)
    select 'tenant-qr-duplicado', 'Tenant QR duplicado', public_qr_code
    from public.fidelizacion_tenants
    where id = '10000000-0000-4000-8000-000000000001';
    raise exception 'public_qr_code no es unico.';
  exception
    when unique_violation then null;
  end;
end
$$;

rollback;
