-- Consultas para mirar los datos desde el SQL Editor de Supabase.
-- Se pegan de a una y se aprieta Run (Ctrl+Enter).
-- Panel: https://supabase.com/dashboard/project/uxjqdvfooqqprcsqklat/sql

-- ---------------------------------------------------------------------------
-- 1. Panorama general: qué hay cargado
-- ---------------------------------------------------------------------------
select p.codigo,
       p.nombre || ' ' || p.apellido                         as paciente,
       e.lesion,
       e.limite_inf || ' a ' || e.limite_sup || ' %PC'       as indicacion,
       e.peso_kg,
       d.serie                                               as ortesis,
       case when e.fin is null then 'en curso' else 'cerrado' end as tratamiento,
       (select count(*) from resumenes_diarios r where r.episodio_id = e.id) as dias,
       (select count(*) from registros_minuto  m where m.episodio_id = e.id) as minutos
from pacientes p
join episodios e on e.paciente_id = p.id
left join dispositivos d on d.id = e.dispositivo_id
order by p.codigo, e.inicio;

-- ---------------------------------------------------------------------------
-- 2. Lo que subió la app: cada envío, con la hora de Argentina
--    Es la prueba de que el dato viajó del teléfono al servidor.
-- ---------------------------------------------------------------------------
select p.codigo,
       r.fecha                                               as dia_medido,
       r.recibido at time zone 'America/Argentina/Buenos_Aires' as llego_el,
       round(r.dosis_sobrecarga::numeric, 1)                 as dosis_sobrecarga,
       r.excedencias,
       round(r.t_carga_s / 3600.0, 1)                        as horas_de_apoyo,
       round(100 * (1 - r.t_exceso_s::numeric / nullif(r.t_carga_s, 0)), 1) as cumplimiento
from resumenes_diarios r
join episodios e on e.id = r.episodio_id
join pacientes p on p.id = e.paciente_id
order by r.recibido desc
limit 20;

-- ---------------------------------------------------------------------------
-- 3. El detalle minuto a minuto de un paciente
--    Cambiar el código por el que quieras mirar.
-- ---------------------------------------------------------------------------
select m.ts at time zone 'America/Argentina/Buenos_Aires' as minuto,
       round(m.carga_media::numeric, 1) as carga_media_pc,
       round(m.carga_pico::numeric, 1)  as pico_pc,
       round(m.dosis::numeric, 2)       as dosis_del_minuto,
       m.excedencias,
       m.seg_apoyo                      as segundos_de_apoyo
from registros_minuto m
join episodios e on e.id = m.episodio_id
join pacientes p on p.id = e.paciente_id
where p.codigo = 'P-000005'
order by m.ts desc
limit 30;

-- ---------------------------------------------------------------------------
-- 4. La historia de la indicación: qué se prescribió y cuándo cambió
-- ---------------------------------------------------------------------------
select p.codigo,
       i.desde,
       i.limite_inf || ' a ' || i.limite_sup || ' %PC' as indicacion,
       i.peso_kg,
       i.nota
from indicaciones i
join episodios e on e.id = i.episodio_id
join pacientes p on p.id = e.paciente_id
order by p.codigo, i.desde;

-- ---------------------------------------------------------------------------
-- 5. La cadena completa: cómo se une el paciente con lo que levanta la placa
--    El ID que viaja a la ortesis no dice nada de la persona.
-- ---------------------------------------------------------------------------
select p.codigo                                     as paciente,
       p.id                                         as uuid_del_paciente,
       substr(replace(e.id::text, '-', ''), 1, 16)  as id_que_lleva_la_placa,
       e.peso_kg                                    as peso_que_usa_para_los_calculos,
       e.equipo_visto ->> 'serie'                   as ortesis_que_informo,
       e.equipo_visto_en at time zone 'America/Argentina/Buenos_Aires' as informo_el
from pacientes p
join episodios e on e.paciente_id = p.id
where e.fin is null
order by p.codigo;

-- ---------------------------------------------------------------------------
-- 6. Cuánto pesa todo esto (por si preguntan por el almacenamiento)
-- ---------------------------------------------------------------------------
select 'pacientes'         as tabla, count(*) as filas from pacientes
union all select 'episodios',        count(*) from episodios
union all select 'indicaciones',     count(*) from indicaciones
union all select 'resumenes_diarios',count(*) from resumenes_diarios
union all select 'registros_minuto', count(*) from registros_minuto
order by tabla;
