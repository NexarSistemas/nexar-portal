-- M06.6: hardening del RPC legacy del Portal Vendedor.
-- El Portal Vendedor actual ya no consume este RPC. Se retira su ejecución
-- pública sin eliminar la función ni otros objetos legacy; M07 sigue bloqueada.

do $$
begin
  if to_regprocedure('public.portal_dashboard_vendedor(text)') is null then
    raise exception using
      message = 'M06.6 requiere public.portal_dashboard_vendedor(text).',
      hint = 'Revalide el inventario legacy antes de aplicar este hardening.';
  end if;
end
$$;

revoke execute on function public.portal_dashboard_vendedor(text)
  from public, anon, authenticated;

comment on function public.portal_dashboard_vendedor(text) is
  'RPC legacy preservado sin ejecución pública. Su retirada definitiva sigue condicionada por M07.';
