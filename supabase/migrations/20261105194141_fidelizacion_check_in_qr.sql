create extension if not exists pg_cron;
create table app_private.fidelizacion_check_in_intentos (
 intento_id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 issued_at timestamptz not null default clock_timestamp(), tenant_id uuid, account_id uuid, consumed_at timestamptz,
 foreign key (tenant_id, account_id) references public.fidelizacion_accounts(tenant_id,id),
 check ((consumed_at is null and tenant_id is null and account_id is null) or (consumed_at is not null and tenant_id is not null and account_id is not null))
);
revoke all on app_private.fidelizacion_check_in_intentos from public, anon, authenticated;
create index on app_private.fidelizacion_check_in_intentos(user_id,issued_at);
create index on app_private.fidelizacion_check_in_intentos(issued_at);
create index on app_private.fidelizacion_check_in_intentos(tenant_id,consumed_at);
create function app_private.fidelizacion_emitir_intento_check_in() returns table(intento_id uuid, expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare u uuid := auth.uid(); t timestamptz := clock_timestamp();
begin
 if u is null then raise exception using errcode='28000', message='Sesion requerida'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(u::text, 912078));
 if (select count(*) from app_private.fidelizacion_check_in_intentos i where i.user_id=u and i.issued_at > t-interval '1 minute') >= 10 then
 raise exception using errcode='54000', message='Demasiados intentos'; end if;
 return query insert into app_private.fidelizacion_check_in_intentos(user_id,issued_at) values(u,t) returning fidelizacion_check_in_intentos.intento_id, fidelizacion_check_in_intentos.issued_at + interval '5 minutes';
end $$;
create function public.fidelizacion_emitir_intento_check_in() returns table(intento_id uuid, expires_at timestamptz)
language sql security invoker set search_path='' as $$ select * from app_private.fidelizacion_emitir_intento_check_in(); $$;
create function app_private.fidelizacion_registrar_check_in(p_public_qr_code text,p_intento_id uuid)
returns table(account_id uuid,tenant_id uuid,created_at timestamptz,expires_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); i app_private.fidelizacion_check_in_intentos%rowtype; a uuid; t uuid; n timestamptz;
begin
 if u is null then raise exception using errcode='28000', message='Sesion requerida'; end if;
 select * into i from app_private.fidelizacion_check_in_intentos x where x.intento_id=p_intento_id for update;
 if not found or i.user_id<>u then raise exception using errcode='42501',message='Intento no autorizado'; end if;
 if i.consumed_at is not null then
   if not exists(select 1 from public.fidelizacion_tenants z join public.fidelizacion_accounts ac on ac.tenant_id=z.id where z.id=i.tenant_id and z.activo and z.public_qr_code=pg_catalog.btrim(p_public_qr_code) and ac.id=i.account_id and ac.activo and ac.user_id=u) then raise exception using errcode='42501',message='Intento no autorizado'; end if;
   return query select i.account_id,i.tenant_id,i.consumed_at,i.consumed_at+interval '5 minutes'; return;
 end if;
 n:=clock_timestamp();
 if n>=i.issued_at+interval '5 minutes' then raise exception using errcode='55000',message='Intento vencido'; end if;
 select r.account_id,r.tenant_id into a,t from app_private.fidelizacion_registrar_cuenta_cliente(p_public_qr_code) r;
 n:=clock_timestamp();
 if n>=i.issued_at+interval '5 minutes' then raise exception using errcode='55000',message='Intento vencido'; end if;
 update app_private.fidelizacion_check_in_intentos set account_id=a,tenant_id=t,consumed_at=n where intento_id=i.intento_id;
 return query select a,t,n,n+interval '5 minutes';
end $$;
create function public.fidelizacion_registrar_check_in(p_public_qr_code text,p_intento_id uuid) returns table(account_id uuid,tenant_id uuid,created_at timestamptz,expires_at timestamptz)
language sql security invoker set search_path='' as $$ select * from app_private.fidelizacion_registrar_check_in(p_public_qr_code,p_intento_id); $$;
create function app_private.fidelizacion_listar_check_in_staff() returns table(account_id uuid,created_at timestamptz,expires_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); t uuid; c bigint;
begin
 if u is null then raise exception using errcode='28000',message='Sesion requerida'; end if;
 select count(*),(array_agg(s.tenant_id order by s.tenant_id))[1] into c,t from public.fidelizacion_staff s join public.fidelizacion_tenants z on z.id=s.tenant_id and z.activo where s.user_id=u and s.activo and s.rol in ('admin','operador');
 if c<>1 then raise exception using errcode='42501',message='Acceso no autorizado'; end if;
 return query select distinct on(i.account_id) i.account_id,i.consumed_at,i.consumed_at+interval '5 minutes' from app_private.fidelizacion_check_in_intentos i join public.fidelizacion_accounts a on a.id=i.account_id and a.tenant_id=i.tenant_id and a.activo where i.tenant_id=t and i.consumed_at > statement_timestamp()-interval '5 minutes' order by i.account_id,i.consumed_at desc;
end $$;
create function public.fidelizacion_listar_check_in_staff() returns table(account_id uuid,created_at timestamptz,expires_at timestamptz) language sql stable security invoker set search_path='' as $$ select * from app_private.fidelizacion_listar_check_in_staff(); $$;
revoke all on function app_private.fidelizacion_emitir_intento_check_in(),public.fidelizacion_emitir_intento_check_in(),app_private.fidelizacion_registrar_check_in(text,uuid),public.fidelizacion_registrar_check_in(text,uuid),app_private.fidelizacion_listar_check_in_staff(),public.fidelizacion_listar_check_in_staff() from public,anon;
grant execute on function app_private.fidelizacion_emitir_intento_check_in(),public.fidelizacion_emitir_intento_check_in(),app_private.fidelizacion_registrar_check_in(text,uuid),public.fidelizacion_registrar_check_in(text,uuid),app_private.fidelizacion_listar_check_in_staff(),public.fidelizacion_listar_check_in_staff() to authenticated;
select cron.schedule('fidelizacion-check-in-limpieza','0 * * * *',$job$delete from app_private.fidelizacion_check_in_intentos where issued_at < clock_timestamp()-interval '24 hours'$job$);
