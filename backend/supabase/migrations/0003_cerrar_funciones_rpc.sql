-- El linter de Supabase avisa que las funciones security definer quedan expuestas como
-- RPC en /rest/v1/rpc/... Ninguna de las dos está pensada para llamarse desde afuera.

-- Función de trigger: la ejecuta supabase_auth_admin al insertar en auth.users.
revoke execute on function public.crear_perfil_medico() from public, anon, authenticated;
grant execute on function public.crear_perfil_medico() to supabase_auth_admin, postgres, service_role;

-- La usan las policies de resumenes y registros: la evalúa el rol que consulta, así que
-- authenticated la necesita. anon no consulta nada de esas tablas.
--
-- Queda una advertencia del linter por esto, y es a propósito: sacarle el permiso a
-- authenticated rompería las policies. Lo único que puede averiguar un médico llamándola
-- es si un UUID de episodio es suyo, cosa que ya sabe.
revoke execute on function public.es_mi_episodio(uuid) from public, anon;
grant execute on function public.es_mi_episodio(uuid) to authenticated, postgres, service_role;
