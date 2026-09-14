-- M07: MIGRACION CONDICIONADA. No es apta inmediatamente despues de M06.
-- Requiere, en este orden: provision manual controlada de Auth para RONA596,
-- vinculacion perfiles.vendedor_id, validacion funcional y de RLS, inventario
-- que pruebe ausencia de consumidores legacy y aprobacion de retiro.

do $$
begin
  if current_setting('app.nexar_portal_m07_gate', true) is distinct from 'completed' then
    raise exception using
      message = 'M07 bloqueada: el gate previo no esta completado.',
      hint = 'No retirar portal_vendedor_sessions, passwords, RPC legacy ni constraints nullable antes de la provision Auth y validacion RLS documentadas.';
  end if;

  raise exception using
    message = 'M07 requiere un inventario de consumidores legacy aprobado.',
    hint = 'El repositorio no demuestra los RPC, columnas de password, policies ni consumidores que pueden retirarse. Completar ese inventario antes de sustituir este guard por DDL destructivo revisado.';
end
$$;
