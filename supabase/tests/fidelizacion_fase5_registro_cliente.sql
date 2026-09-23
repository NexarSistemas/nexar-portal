\set ON_ERROR_STOP on

-- Prueba local transaccional del registro seguro de clientes de Fidelizacion.
begin;

insert into auth.users (id, email, aud, role)
values
  ('01300000-0000-4000-8000-000000000001', 'fase5-cliente-a@example.invalid', 'authenticated', 'authenticated'),
  ('01300000-0000-4000-8000-000000000002', 'fase5-cliente-b@example.invalid', 'authenticated', 'authenticated'),
  ('01300000-0000-4000-8000-000000000003', 'fase5-cuenta-inactiva@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre, activo, public_qr_code)
values
  ('11300000-0000-4000-8000-000000000001', 'fase5-tenant-a', 'Fase 5 tenant A', true, 'GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG'),
  ('11300000-0000-4000-8000-000000000002', 'fase5-tenant-b', 'Fase 5 tenant B', true, 'HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH'),
  ('11300000-0000-4000-8000-000000000003', 'fase5-tenant-inactivo', 'Fase 5 tenant inactivo', false, 'IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII');

insert into public.fidelizacion_accounts (id, tenant_id, user_id, activo)
values (
  '21300000-0000-4000-8000-000000000001',
  '11300000-0000-4000-8000-000000000001',
  '01300000-0000-4000-8000-000000000003',
  false
);

-- El usuario autenticado crea una sola cuenta y los reintentos devuelven la misma asociacion.
select set_config(
  'request.jwt.claims',
  '{"sub":"01300000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_primera record;
  v_repetida record;
begin
  select * into v_primera
  from public.fidelizacion_registrar_cuenta_cliente('GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG');

  select * into v_repetida
  from public.fidelizacion_registrar_cuenta_cliente('GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG');

  if v_primera.account_id is null
    or v_primera.tenant_id <> '11300000-0000-4000-8000-000000000001'
    or v_repetida.account_id <> v_primera.account_id
    or v_repetida.tenant_id <> v_primera.tenant_id
  then
    raise exception 'El registro no creo o repitio la misma asociacion activa.';
  end if;

  if (
    select count(*)
    from public.fidelizacion_accounts
    where tenant_id = '11300000-0000-4000-8000-000000000001'
      and user_id = '01300000-0000-4000-8000-000000000001'
  ) <> 1 then
    raise exception 'El reintento genero cuentas duplicadas.';
  end if;
end
$$;

-- El mismo usuario puede pertenecer a otro tenant sin mezclar asociaciones.
do $$
declare
  v_resultado record;
begin
  select * into v_resultado
  from public.fidelizacion_registrar_cuenta_cliente('HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH');

  if v_resultado.tenant_id <> '11300000-0000-4000-8000-000000000002'
    or (
      select count(*)
      from public.fidelizacion_accounts
      where user_id = '01300000-0000-4000-8000-000000000001'
    ) <> 2
  then
    raise exception 'El registro no preservo las asociaciones aisladas por tenant.';
  end if;
end
$$;

reset role;

-- Otro usuario del mismo tenant obtiene una cuenta distinta.
select set_config(
  'request.jwt.claims',
  '{"sub":"01300000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_resultado record;
begin
  select * into v_resultado
  from public.fidelizacion_registrar_cuenta_cliente('GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG');

  if v_resultado.account_id is null
    or v_resultado.tenant_id <> '11300000-0000-4000-8000-000000000001'
  then
    raise exception 'El segundo usuario no obtuvo una cuenta del tenant esperado.';
  end if;
end
$$;

-- QR malformado, QR inexistente y tenant inactivo se rechazan.
do $$
begin
  begin
    perform * from public.fidelizacion_registrar_cuenta_cliente('qr-invalido');
    raise exception 'Un QR malformado fue aceptado.';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform * from public.fidelizacion_registrar_cuenta_cliente('ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ');
    raise exception 'Un QR inexistente fue aceptado.';
  exception when insufficient_privilege then null;
  end;

  begin
    perform * from public.fidelizacion_registrar_cuenta_cliente('IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII');
    raise exception 'Un tenant inactivo permitio registrar una cuenta.';
  exception when insufficient_privilege then null;
  end;
end
$$;

-- Authenticated conserva SELECT pero no puede insertar ni forzar IDs directamente.
do $$
begin
  begin
    insert into public.fidelizacion_accounts (tenant_id, user_id)
    values (
      '11300000-0000-4000-8000-000000000002',
      '01300000-0000-4000-8000-000000000003'
    );
    raise exception 'Authenticated conservo INSERT directo sobre cuentas.';
  exception when insufficient_privilege then null;
  end;

  if to_regprocedure('public.fidelizacion_registrar_cuenta_cliente(text,uuid)') is not null
    or to_regprocedure('public.fidelizacion_registrar_cuenta_cliente(text,uuid,uuid)') is not null
  then
    raise exception 'La RPC permite forzar identificadores internos.';
  end if;
end
$$;

reset role;

do $$
declare
  v_cuenta_usuario_a uuid;
  v_cuenta_usuario_b uuid;
begin
  select id into v_cuenta_usuario_a
  from public.fidelizacion_accounts
  where tenant_id = '11300000-0000-4000-8000-000000000001'
    and user_id = '01300000-0000-4000-8000-000000000001';

  select id into v_cuenta_usuario_b
  from public.fidelizacion_accounts
  where tenant_id = '11300000-0000-4000-8000-000000000001'
    and user_id = '01300000-0000-4000-8000-000000000002';

  if v_cuenta_usuario_a is null
    or v_cuenta_usuario_b is null
    or v_cuenta_usuario_a = v_cuenta_usuario_b
  then
    raise exception 'Dos usuarios del mismo tenant no conservaron cuentas distintas.';
  end if;
end
$$;

-- Sin sesion, el helper rechaza aunque el rol tenga EXECUTE sobre la RPC.
select set_config('request.jwt.claims', '{}', true);
set local role authenticated;

do $$
begin
  begin
    perform * from public.fidelizacion_registrar_cuenta_cliente(
      'GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG'
    );
    raise exception 'Una llamada sin sesion registro una cuenta.';
  exception when invalid_authorization_specification then null;
  end;
end
$$;

reset role;

-- Una asociacion existente pero inactiva no se reactiva mediante el registro.
select set_config(
  'request.jwt.claims',
  '{"sub":"01300000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  begin
    perform * from public.fidelizacion_registrar_cuenta_cliente(
      'GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG'
    );
    raise exception 'Una cuenta inactiva fue aceptada o reactivada.';
  exception when object_not_in_prerequisite_state then null;
  end;
end
$$;

reset role;

-- La suite no abre dos sesiones; verifica la primitive usada por la carrera concurrente.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.fidelizacion_accounts'::regclass
      and conname = 'fidelizacion_accounts_tenant_user_key'
      and contype = 'u'
  ) then
    raise exception 'Falta la unicidad usada para idempotencia y concurrencia.';
  end if;

  if pg_catalog.position(
    'on conflict on constraint fidelizacion_accounts_tenant_user_key'
    in pg_catalog.lower(
      pg_get_functiondef(
        'app_private.fidelizacion_registrar_cuenta_cliente(text)'::regprocedure
      )
    )
  ) = 0 then
    raise exception 'La RPC no usa la unicidad existente para resolver carreras.';
  end if;
end
$$;

rollback;
