-- M04: saneamiento destructivo de DATOS DE PRUEBA, no de estructuras legacy.
--
-- BLOQUEADA POR DISENO: el repositorio no contiene un relevamiento del schema
-- legacy ni la columna que representa la identidad comercial de RONA596. No se
-- puede emitir DELETE seguro sin inventar esas relaciones. Antes de ejecutar
-- debe existir un plan de borrado revisado que identifique los FK y la columna
-- comercial, y debe habilitarse explicitamente esta migracion en la sesion.

do $$
begin
  if current_setting('app.nexar_portal_m04_approved', true) is distinct from 'approved' then
    raise exception using
      message = 'M04 no esta habilitada para ejecucion.',
      hint = 'Tras aprobar el plan de saneamiento, ejecute en una sesion controlada: SET app.nexar_portal_m04_approved = ''approved''.';
  end if;

  raise exception using
    message = 'M04 requiere el relevamiento legacy aprobado antes de efectuar DELETE.',
    hint = 'El plan debe resolver RONA596 por su identidad comercial, conservar su UUID y ordenar los borrados segun FK reales. No se permite hardcodear su UUID.';
end
$$;

-- Catalogo inicial: pendiente de los codigos, nombres y precios aprobados.
-- No se insertan valores inferidos: precios_planes continua operando durante la coexistencia.
