\set ON_ERROR_STOP on
begin;
insert into auth.users (id, email, aud, role) values
  ('01900000-0000-4000-8000-000000000001', 'checkin-cliente@example.invalid', 'authenticated', 'authenticated'),
  ('01900000-0000-4000-8000-000000000002', 'checkin-staff-a@example.invalid', 'authenticated', 'authenticated'),
  ('01900000-0000-4000-8000-000000000003', 'checkin-staff-b@example.invalid', 'authenticated', 'authenticated');
insert into public.fidelizacion_tenants (id, slug, nombre, public_qr_code) values
  ('11900000-0000-4000-8000-000000000001', 'checkin-a', 'Check-in A', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
  ('11900000-0000-4000-8000-000000000002', 'checkin-b', 'Check-in B', 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB');
insert into public.fidelizacion_staff (tenant_id, user_id, rol) values
  ('11900000-0000-4000-8000-000000000001', '01900000-0000-4000-8000-000000000002', 'operador'),
  ('11900000-0000-4000-8000-000000000002', '01900000-0000-4000-8000-000000000003', 'operador');
select set_config('request.jwt.claims', '{"sub":"01900000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $$
declare first_result record; retry_result record; next_result record; attempt1 uuid; attempt2 uuid;
begin
  select intento_id into attempt1 from public.fidelizacion_emitir_intento_check_in();
  select intento_id into attempt2 from public.fidelizacion_emitir_intento_check_in();
  select * into first_result from public.fidelizacion_registrar_check_in('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', attempt1);
  select * into retry_result from public.fidelizacion_registrar_check_in('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', attempt1);
  if first_result.account_id <> retry_result.account_id or first_result.expires_at <> retry_result.expires_at
    or first_result.expires_at <> first_result.created_at + interval '5 minutes' then
    raise exception 'Reintento o vigencia incorrectos';
  end if;
  select * into next_result from public.fidelizacion_registrar_check_in('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', attempt2);
  if next_result.account_id <> first_result.account_id or next_result.expires_at < first_result.expires_at then
    raise exception 'Renovacion incorrecta';
  end if;
  begin
    perform * from public.fidelizacion_registrar_check_in('BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB', attempt1);
    raise exception 'Reutilizacion de intento entre comercios aceptada';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims', '{"sub":"01900000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  if (select count(*) from public.fidelizacion_listar_check_in_staff()) <> 1 then
    raise exception 'Check-in ausente o duplicado';
  end if;
end $$;
reset role;
select set_config('request.jwt.claims', '{"sub":"01900000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  if exists (select 1 from public.fidelizacion_listar_check_in_staff()) then
    raise exception 'Check-in visible en otro comercio';
  end if;
end $$;
reset role;
update app_private.fidelizacion_check_in_intentos set consumed_at = statement_timestamp() - interval '6 minutes' where tenant_id = '11900000-0000-4000-8000-000000000001';
select set_config('request.jwt.claims', '{"sub":"01900000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  if exists (select 1 from public.fidelizacion_listar_check_in_staff()) then
    raise exception 'Check-in vencido visible';
  end if;
end $$;
reset role;
reset role;
do $$ begin
  if exists (select 1 from public.fidelizacion_operations o join public.fidelizacion_accounts a on a.id = o.account_id where a.user_id = '01900000-0000-4000-8000-000000000001') then raise exception 'Se creo una operacion'; end if;
  if exists (select 1 from public.fidelizacion_point_movements m join public.fidelizacion_accounts a on a.id = m.account_id where a.user_id = '01900000-0000-4000-8000-000000000001') then raise exception 'Se creo un movimiento'; end if;
  if has_function_privilege('anon', 'public.fidelizacion_registrar_check_in(text,uuid)', 'execute') or has_function_privilege('anon', 'public.fidelizacion_listar_check_in_staff()', 'execute') then raise exception 'Anon tiene acceso'; end if;
  if has_table_privilege('authenticated', 'app_private.fidelizacion_check_in_intentos', 'select') then raise exception 'Tabla accesible'; end if;
end $$;
rollback;
