-- Lo último que la ortesis informó de sí misma cuando alguien la leyó: serie, firmware,
-- qué episodio tiene cargado y con qué límites y peso está trabajando.
-- Sirve para confirmar que la indicación del médico llegó al equipo y fue confirmada
-- con el pulsador, que es la única forma de que un límite nuevo entre en vigencia.
alter table public.episodios
  add column if not exists equipo_visto    jsonb,
  add column if not exists equipo_visto_en timestamptz;

comment on column public.episodios.equipo_visto is
  'Lo que reportó la ortesis en la última lectura (app o consulta). No lleva datos personales.';
