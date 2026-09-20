-- Solo lectura: valida M06.6 sin modificar datos ni objetos.

select
  p.oid::regprocedure as funcion,
  p.prosecdef as security_definer,
  not has_function_privilege('public', p.oid, 'EXECUTE') as public_sin_execute,
  not has_function_privilege('anon', p.oid, 'EXECUTE') as anon_sin_execute,
  not has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_sin_execute,
  has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_conserva_execute
from pg_proc p
where p.oid = 'public.portal_dashboard_vendedor(text)'::regprocedure;

select current_setting('app.nexar_portal_m07_gate', true) as gate_m07,
       current_setting('app.nexar_portal_m07_gate', true) is distinct from 'completed'
         as m07_sigue_bloqueada;
