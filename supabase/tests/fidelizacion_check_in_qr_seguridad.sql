\set ON_ERROR_STOP on
begin;
insert into auth.users (id,email,aud,role) values
 ('02900000-0000-4000-8000-000000000001','qr-test1@example.invalid','authenticated','authenticated'),
 ('02900000-0000-4000-8000-000000000002','qr-test2@example.invalid','authenticated','authenticated'),
 ('02900000-0000-4000-8000-000000000003','qr-staff@example.invalid','authenticated','authenticated');
insert into public.fidelizacion_tenants(id,slug,nombre,public_qr_code) values
 ('12900000-0000-4000-8000-000000000001','qr-test-a','QR A','CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'),
 ('12900000-0000-4000-8000-000000000002','qr-test-b','QR B','DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD');
insert into public.fidelizacion_staff(tenant_id,user_id,rol) values
 ('12900000-0000-4000-8000-000000000001','02900000-0000-4000-8000-000000000003','operador');
do $$
declare f text; p text; r text;
begin
 foreach f in array array['fidelizacion_emitir_intento_check_in()','fidelizacion_registrar_check_in(text,uuid)','fidelizacion_listar_check_in_staff()'] loop
  foreach p in array array['public.','app_private.'] loop
   if has_function_privilege('anon', p||f, 'execute') or not has_function_privilege('authenticated', p||f, 'execute') then raise exception 'Permisos incorrectos: %',p||f; end if;
  end loop;
 end loop;
 foreach r in array array['anon','authenticated'] loop
  if has_table_privilege(r,'app_private.fidelizacion_check_in_intentos','select,insert,update,delete,truncate,references,trigger') then raise exception 'Acceso directo a tabla: %',r; end if;
 end loop;
end $$;
set local role anon;
do $$ begin
 begin perform * from public.fidelizacion_emitir_intento_check_in(); raise exception 'Anon emitio intento'; exception when insufficient_privilege then null; end;
 begin perform * from public.fidelizacion_registrar_check_in('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',gen_random_uuid()); raise exception 'Anon registro check-in'; exception when insufficient_privilege then null; end;
 begin perform * from public.fidelizacion_listar_check_in_staff(); raise exception 'Anon listo check-in'; exception when insufficient_privilege then null; end;
 begin perform * from app_private.fidelizacion_check_in_intentos; raise exception 'Anon leyo tabla'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role authenticated;
do $$ begin
 begin perform * from app_private.fidelizacion_check_in_intentos; raise exception 'Authenticated leyo tabla'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{}',true);
do $$ begin
 begin perform * from public.fidelizacion_emitir_intento_check_in(); raise exception 'Sesion ausente aceptada'; exception when invalid_authorization_specification then null; end;
 begin perform * from public.fidelizacion_registrar_check_in('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',gen_random_uuid()); raise exception 'Sesion ausente aceptada'; exception when invalid_authorization_specification then null; end;
 begin perform * from public.fidelizacion_listar_check_in_staff(); raise exception 'Sesion ausente aceptada'; exception when invalid_authorization_specification then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"02900000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$
declare a uuid; b uuid; i uuid; other_i uuid; result record;
begin
 select account_id into a from public.fidelizacion_registrar_cuenta_cliente('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC');
 select intento_id into i from public.fidelizacion_emitir_intento_check_in();
 select * into result from public.fidelizacion_registrar_check_in('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',i);
 if result.account_id <> a then raise exception 'No reutiliza asociacion'; end if;
 select account_id into b from public.fidelizacion_registrar_cuenta_cliente('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC');
 if a <> b then raise exception 'Asociacion modificada'; end if;
 select intento_id into other_i from public.fidelizacion_emitir_intento_check_in();
 perform set_config('request.jwt.claims','{"sub":"02900000-0000-4000-8000-000000000002","role":"authenticated"}',true);
 begin perform * from public.fidelizacion_registrar_check_in('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',other_i); raise exception 'Intento ajeno aceptado'; exception when insufficient_privilege then null; end;
 begin perform * from public.fidelizacion_registrar_check_in('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',i); raise exception 'Intento consumido ajeno aceptado'; exception when insufficient_privilege then null; end;
 begin perform * from public.fidelizacion_listar_check_in_staff(); raise exception 'Cliente puede listar'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.fidelizacion_accounts set activo=false where user_id='02900000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"02900000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare i uuid; begin
 select intento_id into i from public.fidelizacion_emitir_intento_check_in();
 begin perform * from public.fidelizacion_registrar_check_in('CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',i); raise exception 'Cuenta inactiva aceptada'; exception when object_not_in_prerequisite_state then null; end;
end $$;
reset role;
select set_config('request.jwt.claims','{"sub":"02900000-0000-4000-8000-000000000003","role":"authenticated"}',true);
set local role authenticated;
do $$ begin if exists(select 1 from public.fidelizacion_listar_check_in_staff()) then raise exception 'Cuenta inactiva visible'; end if; end $$;
reset role;
update public.fidelizacion_staff set activo=false where user_id='02900000-0000-4000-8000-000000000003';
set local role authenticated;
do $$ begin begin perform * from public.fidelizacion_listar_check_in_staff(); raise exception 'Staff inactivo aceptado'; exception when insufficient_privilege then null; end; end $$;
reset role;
update public.fidelizacion_staff set activo=true where user_id='02900000-0000-4000-8000-000000000003';
insert into public.fidelizacion_staff(tenant_id,user_id,rol) values ('12900000-0000-4000-8000-000000000002','02900000-0000-4000-8000-000000000003','admin');
set local role authenticated;
do $$ begin begin perform * from public.fidelizacion_listar_check_in_staff(); raise exception 'Membresia ambigua aceptada'; exception when insufficient_privilege then null; end; end $$;
reset role;
update public.fidelizacion_tenants set activo=false where id='12900000-0000-4000-8000-000000000002';
select set_config('request.jwt.claims','{"sub":"02900000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ declare i uuid; begin
 select intento_id into i from public.fidelizacion_emitir_intento_check_in();
 begin perform * from public.fidelizacion_registrar_check_in('DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD',i); raise exception 'Comercio inactivo aceptado'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.fidelizacion_operations o join public.fidelizacion_accounts a on a.id=o.account_id where a.user_id in ('02900000-0000-4000-8000-000000000001','02900000-0000-4000-8000-000000000002')) then raise exception 'Operacion creada'; end if;
 if exists(select 1 from public.fidelizacion_point_movements m join public.fidelizacion_accounts a on a.id=m.account_id where a.user_id in ('02900000-0000-4000-8000-000000000001','02900000-0000-4000-8000-000000000002')) then raise exception 'Movimiento creado'; end if;
end $$;
rollback;
