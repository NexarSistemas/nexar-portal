-- M07: RETIRO LEGACY CONDICIONADO Y BLOQUEADO.
-- El retiro futuro comprende portal_dashboard_vendedor(text), policies
-- portal_secret_*, portal_vendedor_sessions, recuperacion propia de password,
-- vendedores.password_hash, vendedores.password_change_required y
-- vendedores.ultimo_login. vendedores.es_admin permanece por ahora porque
-- conserva consumidores externos. La rotacion o revocacion de secretos
-- compartidos es una operacion externa y no se versiona aqui.

do $$
begin
  if current_setting('app.nexar_portal_m07_gate', true) is distinct from 'completed' then
    raise exception using
      message = 'M07 bloqueada: el gate previo no esta completado.',
      hint = 'Exige Auth provisionado, perfil activo vinculado a RONA596, validacion funcional y RLS, migracion de Portal Vendedor y Nexar Admin, inventario externo revisado y aprobacion explicita.';
  end if;

  raise exception using
    message = 'M07 bloqueada: existen consumidores externos activos de la autenticacion legacy.',
    hint = 'No retirar portal_dashboard_vendedor(text), portal_secret_*, sesiones, recuperacion propia ni columnas de auth hasta migrar Portal Vendedor legacy y Nexar Admin, revalidar inventario y aprobar expresamente el retiro.';
end
$$;
