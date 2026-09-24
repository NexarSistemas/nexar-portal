-- Verifica el hardening de RPC de Fase 6 sobre una base ya migrada.
\set ON_ERROR_STOP on

begin;

do $$
declare
  v_rpc regprocedure;
begin
  foreach v_rpc in array array[
    'public.fidelizacion_crear_redeem(uuid,text,timestamptz)'::regprocedure,
    'public.fidelizacion_escanear_redeem(text,uuid)'::regprocedure,
    'public.fidelizacion_confirmar_redeem(uuid)'::regprocedure,
    'public.fidelizacion_cancelar_redeem(uuid)'::regprocedure
  ] loop
    if (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_rpc) then
      raise exception 'El RPC publico de canje % no debe usar SECURITY DEFINER.', v_rpc;
    end if;

    if not has_function_privilege('authenticated', v_rpc, 'EXECUTE')
      or has_function_privilege('anon', v_rpc, 'EXECUTE') then
      raise exception 'Los grants del RPC publico de canje % no son los esperados.', v_rpc;
    end if;
  end loop;
end $$;

rollback;
