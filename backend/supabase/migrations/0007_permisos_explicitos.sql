-- Supabase deja de otorgar permisos automáticos sobre las tablas nuevas del esquema `public`
-- a partir del 30/10/2026. Las tablas que ya existen conservan los suyos, así que el proyecto
-- en marcha no se ve afectado.
--
-- Lo que sí se rompe es rearmar el proyecto de cero, que es justo lo que documenta
-- `backend/README.md`: estas migraciones crean las tablas pero nunca les dieron permisos,
-- porque hasta ahora Supabase lo hacía solo. Sobre un proyecto nuevo creado después de esa
-- fecha, la web contestaría "permission denied" en todas las consultas.
--
-- Esta migración deja los permisos escritos. No reemplaza a las policies RLS: son dos
-- controles distintos y hacen falta los dos. El permiso dice si el rol puede tocar la tabla;
-- la policy dice qué filas. Acá se otorga lo mínimo que cada rol necesita, siguiendo lo que
-- las policies ya permiten.

-- El médico, que entra con su cuenta. Las policies de cada tabla se encargan de que solo
-- vea lo suyo; esto solo habilita las operaciones que esas policies contemplan.
grant select                         on public.dispositivos          to authenticated;
grant select, insert, update, delete on public.pacientes             to authenticated;
grant select, insert, update, delete on public.episodios             to authenticated;
grant select, update                 on public.medicos               to authenticated;
grant select                         on public.indicaciones          to authenticated;
grant select                         on public.resumenes_diarios     to authenticated;
grant select                         on public.registros_minuto      to authenticated;
grant select                         on public.resumenes_con_indices to authenticated;

-- `subir-datos` corre en el servidor con la service_role key y es quien escribe lo que
-- mandan la app y la descarga del consultorio. Saltea RLS por definición del rol.
grant all on public.dispositivos          to service_role;
grant all on public.pacientes             to service_role;
grant all on public.episodios             to service_role;
grant all on public.medicos               to service_role;
grant all on public.indicaciones          to service_role;
grant all on public.resumenes_diarios     to service_role;
grant all on public.registros_minuto      to service_role;
grant all on public.resumenes_con_indices to service_role;

-- `anon` es cualquiera que tenga la anon key, que es pública: viaja en el bundle de la web.
-- No le hace falta leer ninguna tabla. El médico entra con su cuenta y pasa a ser
-- `authenticated`; la app del paciente no lee de Supabase, solo escribe a través de
-- `subir-datos` (decisión 005). Es la misma idea que ya había quedado escrita en la
-- migración 0003: "anon no consulta nada de esas tablas".
--
-- Hasta ahora tenía permiso de lectura y escritura sobre todo por el grant automático de
-- Supabase. Nunca le sirvió de nada, porque las policies le devuelven vacío, pero no hay
-- motivo para dejarlo puesto.
revoke all on public.dispositivos          from anon;
revoke all on public.pacientes             from anon;
revoke all on public.episodios             from anon;
revoke all on public.medicos               from anon;
revoke all on public.indicaciones          from anon;
revoke all on public.resumenes_diarios     from anon;
revoke all on public.registros_minuto      from anon;
revoke all on public.resumenes_con_indices from anon;

-- De acá en adelante, toda migración que cree una tabla en `public` tiene que incluir sus
-- propios grants. Esto fija el valor por defecto para las tablas que cree el rol `postgres`,
-- que es el que corre las migraciones, así que alcanza con no olvidarse de `anon`.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant all on tables to service_role;
