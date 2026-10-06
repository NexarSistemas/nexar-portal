\set ON_ERROR_STOP on

begin;

insert into auth.users (id, email, aud, role)
values
  ('01600000-0000-4000-8000-000000000001', 'pendientes-cliente-a@example.invalid', 'authenticated', 'authenticated'),
  ('01600000-0000-4000-8000-000000000002', 'pendientes-cliente-b@example.invalid', 'authenticated', 'authenticated');

insert into public.fidelizacion_tenants (id, slug, nombre, public_qr_code)
values
  ('11600000-0000-4000-8000-000000000001', 'pendientes-tenant-a', 'Pendientes tenant A', 'PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP'),
  ('11600000-0000-4000-8000-000000000002', 'pendientes-tenant-b', 'Pendientes tenant B', 'QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ');

insert into public.fidelizacion_accounts (id, tenant_id, user_id)
values
  ('21600000-0000-4000-8000-000000000001', '11600000-0000-4000-8000-000000000001', '01600000-0000-4000-8000-000000000001'),
  ('21600000-0000-4000-8000-000000000002', '11600000-0000-4000-8000-000000000002', '01600000-0000-4000-8000-000000000002');

insert into public.fidelizacion_rewards (id, tenant_id, nombre, puntos_requeridos)
values
  ('31600000-0000-4000-8000-000000000001', '11600000-0000-4000-8000-000000000001', 'Recompensa pendientes A', 10),
  ('31600000-0000-4000-8000-000000000002', '11600000-0000-4000-8000-000000000002', 'Recompensa pendientes B', 10);

insert into public.fidelizacion_operations (
  id, tenant_id, account_id, tipo, puntos, reward_id, estado, expires_at, created_at, confirmed_at, idempotency_key
)
values
  ('41600000-0000-4000-8000-000000000001', '11600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'earn', 10, null, 'pending_customer', pg_catalog.now() + interval '1 hour', pg_catalog.now() - interval '1 minute', null, 'pendientes-earn-vigente'),
  ('41600000-0000-4000-8000-000000000002', '11600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'redeem', 10, '31600000-0000-4000-8000-000000000001', 'pending_staff', pg_catalog.now() + interval '2 hours', pg_catalog.now() - interval '2 minutes', null, 'pendientes-redeem-vigente'),
  ('41600000-0000-4000-8000-000000000003', '11600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'earn', 10, null, 'pending_customer', pg_catalog.now() - interval '1 hour', pg_catalog.now() - interval '2 hours', null, 'pendientes-expirada'),
  ('41600000-0000-4000-8000-000000000004', '11600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'earn', 10, null, 'pending_customer', null, pg_catalog.now() - interval '3 minutes', null, 'pendientes-sin-expiracion'),
  ('41600000-0000-4000-8000-000000000005', '11600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'earn', 10, null, 'confirmed', null, pg_catalog.now() - interval '4 minutes', pg_catalog.now() - interval '3 minutes', 'pendientes-confirmada'),
  ('41600000-0000-4000-8000-000000000006', '11600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'earn', 10, null, 'cancelled', null, pg_catalog.now() - interval '5 minutes', null, 'pendientes-cancelada'),
  ('41600000-0000-4000-8000-000000000007', '11600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'earn', 10, null, 'expired', pg_catalog.now() - interval '1 minute', pg_catalog.now() - interval '2 minutes', null, 'pendientes-estado-expired'),
  ('41600000-0000-4000-8000-000000000008', '11600000-0000-4000-8000-000000000002', '21600000-0000-4000-8000-000000000002', 'earn', 10, null, 'pending_customer', pg_catalog.now() + interval '1 hour', pg_catalog.now() - interval '1 minute', null, 'pendientes-otro-tenant');

select set_config(
  'request.jwt.claims',
  '{"sub":"01600000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_ids uuid[];
begin
  select array_agg(o.id order by o.created_at desc, o.id desc)
    into v_ids
  from public.fidelizacion_obtener_operaciones_pendientes(
    '21600000-0000-4000-8000-000000000001'
  ) o;

  if v_ids is distinct from array[
    '41600000-0000-4000-8000-000000000001'::uuid,
    '41600000-0000-4000-8000-000000000002'::uuid,
    '41600000-0000-4000-8000-000000000004'::uuid
  ] then
    raise exception 'La lectura no devolvio exclusivamente pendientes propias vigentes: %.', v_ids;
  end if;

  begin
    perform *
    from public.fidelizacion_obtener_operaciones_pendientes(
      '21600000-0000-4000-8000-000000000002'
    );
    raise exception 'El cliente A pudo consultar una cuenta de otro tenant.';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"01600000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
begin
  begin
    perform *
    from public.fidelizacion_obtener_operaciones_pendientes(
      '21600000-0000-4000-8000-000000000001'
    );
    raise exception 'El cliente B pudo consultar una cuenta ajena.';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;

select set_config('request.jwt.claims', '{}', true);
set local role authenticated;
do $$
begin
  begin
    perform *
    from public.fidelizacion_obtener_operaciones_pendientes(
      '21600000-0000-4000-8000-000000000001'
    );
    raise exception 'Una solicitud authenticated sin usuario obtuvo datos.';
  exception when invalid_authorization_specification then null;
  end;
end
$$;
reset role;

set local role anon;
do $$
begin
  begin
    perform *
    from public.fidelizacion_obtener_operaciones_pendientes(
      '21600000-0000-4000-8000-000000000001'
    );
    raise exception 'anon obtuvo acceso a operaciones pendientes.';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;

rollback;
