-- Regresión del contrato de ejecución de wrappers publicos SECURITY INVOKER.
\set ON_ERROR_STOP on

begin;

do $$
declare
  v_rpc regprocedure;
begin
  if not has_schema_privilege('authenticated', 'app_private', 'USAGE')
    or has_schema_privilege('anon', 'app_private', 'USAGE')
    or has_schema_privilege('public', 'app_private', 'USAGE')
  then
    raise exception 'El USAGE de app_private no preserva el contrato de los wrappers RPC.';
  end if;

  foreach v_rpc in array array[
    'public.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'::regprocedure,
    'app_private.fidelizacion_crear_earn(uuid,bigint,text,timestamptz)'::regprocedure,
    'public.fidelizacion_obtener_earn_pendientes(text)'::regprocedure,
    'app_private.fidelizacion_obtener_earn_pendientes(text)'::regprocedure,
    'public.fidelizacion_confirmar_earn(text,uuid)'::regprocedure,
    'app_private.fidelizacion_confirmar_earn(text,uuid)'::regprocedure,
    'public.fidelizacion_crear_redeem(uuid,text,timestamptz)'::regprocedure,
    'app_private.fidelizacion_crear_redeem(uuid,text,timestamptz)'::regprocedure,
    'public.fidelizacion_escanear_redeem(text,uuid)'::regprocedure,
    'app_private.fidelizacion_escanear_redeem(text,uuid)'::regprocedure,
    'public.fidelizacion_confirmar_redeem(uuid)'::regprocedure,
    'app_private.fidelizacion_confirmar_redeem(uuid)'::regprocedure,
    'public.fidelizacion_cancelar_redeem(uuid)'::regprocedure,
    'app_private.fidelizacion_cancelar_redeem(uuid)'::regprocedure,
    'public.fidelizacion_buscar_cuenta_staff(text)'::regprocedure,
    'app_private.fidelizacion_buscar_cuenta_staff(text)'::regprocedure,
    'public.fidelizacion_registrar_cuenta_cliente(text)'::regprocedure,
    'app_private.fidelizacion_registrar_cuenta_cliente(text)'::regprocedure,
    'public.fidelizacion_obtener_saldo_cliente(uuid)'::regprocedure,
    'app_private.fidelizacion_obtener_saldo_cliente(uuid)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated', v_rpc, 'EXECUTE')
      or has_function_privilege('anon', v_rpc, 'EXECUTE')
      or has_function_privilege('public', v_rpc, 'EXECUTE')
    then
      raise exception 'Los grants del RPC % no son los esperados.', v_rpc;
    end if;
  end loop;
end;
$$;

do $$
begin
  if pg_get_function_identity_arguments('public.fidelizacion_buscar_cuenta_staff(text)'::regprocedure) <> 'p_email text'
    or pg_get_function_identity_arguments('public.fidelizacion_registrar_cuenta_cliente(text)'::regprocedure) <> 'p_public_qr_code text'
    or pg_get_function_identity_arguments('public.fidelizacion_obtener_saldo_cliente(uuid)'::regprocedure) <> 'p_account_id uuid'
  then
    raise exception 'Las claves JSON de PostgREST no coinciden con los wrappers publicos.';
  end if;
end;
$$;

-- COALESCE es sintaxis SQL: no puede calificarse como pg_catalog.coalesce,
-- porque el error se manifiesta recien al ejecutar los helpers desde los RPC.
do $$
declare
  v_helper regprocedure;
begin
  foreach v_helper in array array[
    'app_private.fidelizacion_buscar_cuenta_staff(text)'::regprocedure,
    'app_private.fidelizacion_obtener_saldo_cliente(uuid)'::regprocedure
  ] loop
    if pg_get_functiondef(v_helper) ilike '%pg_catalog.coalesce(%' then
      raise exception 'El helper % califica COALESCE y fallaria con 42883 al ejecutarse.', v_helper;
    end if;
  end loop;
end;
$$;

rollback;
