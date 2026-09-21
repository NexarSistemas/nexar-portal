\set ON_ERROR_STOP on

-- Prueba local transaccional de la acreditacion earn. Requiere Fase 1 y Fase 2 aplicadas.
begin;

insert into auth.users (id, email, aud, role)
values
  ('01000000-0000-4000-8000-000000000001', 'fase2-cliente-a@example.invalid', 'authenticated', 'authenticated'),
  ('01000000-0000-4000-8000-000000000002', 'fase2-cliente-a2@example.invalid', 'authenticated', 'authenticated'),
  ('01000000-0000-4000-8000-000000000003', 'fase2-staff-a@example.invalid', 'authenticated', 'authenticated'),
  ('01000000-0000-4000-8000-000000000004', 'fase2-sin-permisos@example.invalid', 'authenticated', 'authenticated'),
  ('01000000-0000-4000-8000-000000000005', 'fase2-cliente-b@example.invalid', 'authenticated', 'authenticated'),
  ('01000000-0000-4000-8000-000000000006', 'fase2-staff-b@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre, public_qr_code)
values
  ('11000000-0000-4000-8000-000000000001', 'fase2-tenant-a', 'Fase 2 tenant A', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
  ('11000000-0000-4000-8000-000000000002', 'fase2-tenant-b', 'Fase 2 tenant B', 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB');

insert into public.fidelizacion_accounts (id, tenant_id, user_id, activo)
values
  ('21000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', '01000000-0000-4000-8000-000000000001', true),
  ('21000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000001', '01000000-0000-4000-8000-000000000002', true),
  ('21000000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000002', '01000000-0000-4000-8000-000000000005', true),
  ('21000000-0000-4000-8000-000000000004', '11000000-0000-4000-8000-000000000001', '01000000-0000-4000-8000-000000000004', false);

insert into public.fidelizacion_staff (tenant_id, user_id, rol, activo)
values
  ('11000000-0000-4000-8000-000000000001', '01000000-0000-4000-8000-000000000003', 'operador', true),
  ('11000000-0000-4000-8000-000000000002', '01000000-0000-4000-8000-000000000006', 'admin', true);

insert into public.fidelizacion_operations (
  id, tenant_id, account_id, tipo, puntos, estado, expires_at, created_at, idempotency_key
)
values
  (
    '41000000-0000-4000-8000-000000000002',
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    'earn', 25, 'cancelled', null, now(), 'fase2-cancelada'
  ),
  (
    '41000000-0000-4000-8000-000000000003',
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    'earn', 30, 'pending_customer', now() - interval '1 hour',
    now() - interval '2 hours', 'fase2-expirada'
  ),
  (
    '41000000-0000-4000-8000-000000000004',
    '11000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    'earn', 40, 'pending_customer', now() + interval '1 hour',
    now(), 'fase2-atomicidad'
  );

-- Staff activo del tenant crea earn; repetir la solicitud devuelve la misma operacion.
select set_config(
  'request.jwt.claims',
  '{"sub":"01000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

select operation_id as operacion_creada
from public.fidelizacion_crear_earn(
  '21000000-0000-4000-8000-000000000001',
  120,
  'fase2-creacion-idempotente',
  null
);

select operation_id as misma_operacion
from public.fidelizacion_crear_earn(
  '21000000-0000-4000-8000-000000000001',
  120,
  'fase2-creacion-idempotente',
  null
);

do $$
begin
  begin
    perform *
    from public.fidelizacion_crear_earn(
      '21000000-0000-4000-8000-000000000001',
      121,
      'fase2-creacion-idempotente',
      null
    );
    raise exception 'Un idempotency_key acepto datos distintos.';
  exception
    when unique_violation then null;
  end;

  begin
    perform *
    from public.fidelizacion_crear_earn(
      '21000000-0000-4000-8000-000000000003',
      10,
      'fase2-cross-tenant',
      null
    );
    raise exception 'Staff A creo una operacion para una cuenta del tenant B.';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform *
    from public.fidelizacion_crear_earn(
      '21000000-0000-4000-8000-000000000004',
      10,
      'fase2-cuenta-inactiva',
      null
    );
    raise exception 'Staff A creo una operacion para una cuenta inactiva.';
  exception
    when insufficient_privilege then null;
  end;
end
$$;

reset role;

do $$
begin
  if (
    select count(*)
    from public.fidelizacion_operations
    where tenant_id = '11000000-0000-4000-8000-000000000001'
      and idempotency_key = 'fase2-creacion-idempotente'
  ) <> 1 then
    raise exception 'La creacion idempotente genero una cantidad inesperada de operaciones.';
  end if;

  if exists (
    select 1
    from public.fidelizacion_point_movements
    where operation_id = (
      select id
      from public.fidelizacion_operations
      where tenant_id = '11000000-0000-4000-8000-000000000001'
        and idempotency_key = 'fase2-creacion-idempotente'
    )
  ) then
    raise exception 'Crear o repetir una earn pendiente genero un movimiento.';
  end if;
end
$$;

-- Un usuario autenticado sin rol de staff no puede crear operaciones.
select set_config(
  'request.jwt.claims',
  '{"sub":"01000000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  begin
    perform *
    from public.fidelizacion_crear_earn(
      '21000000-0000-4000-8000-000000000001',
      10,
      'fase2-no-autorizada',
      null
    );
    raise exception 'Un usuario sin rol de staff creo una earn.';
  exception
    when insufficient_privilege then null;
  end;
end
$$;

reset role;

-- Escanear el QR sin pendientes propios devuelve cero filas y no crea movimientos.
select set_config(
  'request.jwt.claims',
  '{"sub":"01000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if (select count(*) from public.fidelizacion_obtener_earn_pendientes(
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
  )) <> 0 then
    raise exception 'El cliente sin pendientes obtuvo una operacion ajena.';
  end if;

  if exists (
    select 1
    from public.fidelizacion_point_movements
    where account_id = '21000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'Escanear un QR sin pendiente genero un movimiento.';
  end if;
end
$$;

-- El cliente incorrecto tampoco puede confirmar una operacion conocida.
do $$
begin
  begin
    perform *
    from public.fidelizacion_confirmar_earn(
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      '41000000-0000-4000-8000-000000000004'
    );
    raise exception 'El cliente incorrecto confirmo una operacion ajena.';
  exception
    when insufficient_privilege then null;
  end;
end
$$;

reset role;

-- El cliente correcto ve solo pendientes validas; canceladas y expiradas no se procesan.
select set_config(
  'request.jwt.claims',
  '{"sub":"01000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  if not exists (
    select 1
    from public.fidelizacion_obtener_earn_pendientes('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
    where puntos = 120
  ) then
    raise exception 'El cliente correcto no obtuvo su earn pendiente.';
  end if;

  if exists (
    select 1
    from public.fidelizacion_obtener_earn_pendientes('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
    where operation_id in (
      '41000000-0000-4000-8000-000000000002',
      '41000000-0000-4000-8000-000000000003'
    )
  ) then
    raise exception 'El resolver devolvio una operacion cancelada o expirada.';
  end if;

  begin
    perform *
    from public.fidelizacion_confirmar_earn(
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      '41000000-0000-4000-8000-000000000002'
    );
    raise exception 'Una operacion cancelada fue confirmada.';
  exception
    when object_not_in_prerequisite_state then null;
  end;

  begin
    perform *
    from public.fidelizacion_confirmar_earn(
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      '41000000-0000-4000-8000-000000000003'
    );
    raise exception 'Una operacion expirada fue confirmada.';
  exception
    when object_not_in_prerequisite_state then null;
  end;
end
$$;

-- Confirmacion correcta y repetida: un solo movimiento positivo y mismo resultado.
do $$
declare
  v_operation_id uuid;
  v_saldo numeric;
begin
  select id into v_operation_id
  from public.fidelizacion_operations
  where tenant_id = '11000000-0000-4000-8000-000000000001'
    and idempotency_key = 'fase2-creacion-idempotente';

  select saldo into v_saldo
  from public.fidelizacion_confirmar_earn(
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    v_operation_id
  );

  if v_saldo <> 120 then
    raise exception 'El saldo derivado esperado era 120 y se obtuvo %.', v_saldo;
  end if;

  perform *
  from public.fidelizacion_confirmar_earn(
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    v_operation_id
  );
end
$$;

reset role;

do $$
declare
  v_operation_id uuid;
begin
  select id into v_operation_id
  from public.fidelizacion_operations
  where tenant_id = '11000000-0000-4000-8000-000000000001'
    and idempotency_key = 'fase2-creacion-idempotente';

  if (
    select count(*)
    from public.fidelizacion_point_movements
    where operation_id = v_operation_id
      and tipo = 'earn'
      and puntos = 120
      and tenant_id = '11000000-0000-4000-8000-000000000001'
      and account_id = '21000000-0000-4000-8000-000000000001'
  ) <> 1 then
    raise exception 'La confirmacion repetida no preservo un unico movimiento consistente.';
  end if;

  if not exists (
    select 1
    from public.fidelizacion_operations
    where id = v_operation_id
      and estado = 'confirmed'
      and confirmed_at is not null
  ) then
    raise exception 'La operacion no quedo confirmada.';
  end if;

  if (
    select coalesce(sum(puntos), 0)
    from public.fidelizacion_point_movements
    where tenant_id = '11000000-0000-4000-8000-000000000001'
      and account_id = '21000000-0000-4000-8000-000000000001'
  ) <> 120 then
    raise exception 'El saldo derivado no coincide con el libro mayor.';
  end if;
end
$$;

-- Fuerza un fallo despues del INSERT del movimiento y comprueba rollback completo.
create function pg_temp.fidelizacion_fase2_fallar_confirmacion()
returns trigger
language plpgsql
as $$
begin
  if new.id = '41000000-0000-4000-8000-000000000004'
    and new.estado = 'confirmed'
  then
    raise exception 'fallo controlado de atomicidad';
  end if;
  return new;
end;
$$;

create trigger fidelizacion_fase2_fallo_atomico
before update of estado on public.fidelizacion_operations
for each row execute function pg_temp.fidelizacion_fase2_fallar_confirmacion();

select set_config(
  'request.jwt.claims',
  '{"sub":"01000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  begin
    perform *
    from public.fidelizacion_confirmar_earn(
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      '41000000-0000-4000-8000-000000000004'
    );
    raise exception 'La confirmacion no activo el fallo controlado.';
  exception
    when raise_exception then
      if sqlerrm <> 'fallo controlado de atomicidad' then
        raise;
      end if;
  end;
end
$$;

reset role;
drop trigger fidelizacion_fase2_fallo_atomico on public.fidelizacion_operations;

do $$
declare
  v_definicion text;
begin
  if exists (
    select 1
    from public.fidelizacion_point_movements
    where operation_id = '41000000-0000-4000-8000-000000000004'
  ) or not exists (
    select 1
    from public.fidelizacion_operations
    where id = '41000000-0000-4000-8000-000000000004'
      and estado = 'pending_customer'
      and confirmed_at is null
  ) then
    raise exception 'El fallo intermedio dejo estado parcial.';
  end if;

  select pg_get_functiondef(
    'app_private.fidelizacion_confirmar_earn(text,uuid)'::regprocedure
  ) into v_definicion;

  if pg_catalog.position('for update of a' in pg_catalog.lower(v_definicion)) = 0 then
    raise exception 'La confirmacion no toma el lock exclusivo de cuenta requerido.';
  end if;

  if pg_catalog.position('for update' in pg_catalog.lower(v_definicion)) = 0 then
    raise exception 'La confirmacion no bloquea la operacion para serializar concurrencia.';
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.fidelizacion_point_movements'::regclass
      and conname = 'fidelizacion_point_movements_operation_id_key'
      and contype = 'u'
  ) then
    raise exception 'Falta la unicidad por operacion que impide doble movimiento concurrente.';
  end if;
end
$$;

rollback;
