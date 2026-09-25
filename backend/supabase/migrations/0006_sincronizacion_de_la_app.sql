-- Hasta acá, escanear el QR no dejaba ningún rastro: la app manda un acuse a `subir-datos`
-- para validar el token, pero ese acuse no escribía nada. Desde el lado del médico, vincular
-- la app y no vincularla se veían exactamente igual.
--
-- Se registra del lado del servidor a propósito: así funciona con los APK que ya están
-- instalados, sin tener que recompilar ni reinstalar nada.

alter table public.episodios
  add column if not exists vinculada_en          timestamptz,
  add column if not exists ultima_sincronizacion timestamptz;

comment on column public.episodios.vinculada_en is
  'Primera vez que la app del paciente usó el token del QR.';
comment on column public.episodios.ultima_sincronizacion is
  'Última vez que la app habló con subir-datos. No cuenta la descarga en la consulta.';

-- Lo que ya pasó: se deduce de cuándo llegaron los resúmenes que subió la app.
update public.episodios e
   set vinculada_en          = sub.primera,
       ultima_sincronizacion = sub.ultima
  from (select episodio_id, min(recibido) as primera, max(recibido) as ultima
          from public.resumenes_diarios
         group by episodio_id) sub
 where sub.episodio_id = e.id
   and e.ultima_sincronizacion is null;

-- Realtime: la web escucha estas dos tablas, filtrando por el episodio que está mirando.
-- Las policies siguen mandando: un médico solo recibe eventos de sus propios pacientes.
alter publication supabase_realtime add table public.resumenes_diarios;
alter publication supabase_realtime add table public.episodios;
