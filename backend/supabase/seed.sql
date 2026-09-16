-- Datos de prueba. Requiere haber creado al menos un usuario en Authentication.
do $$
declare
  m uuid;
  p1 uuid; p2 uuid; p3 uuid;
  e1 uuid; e2 uuid; e3 uuid; e0 uuid;
  d1 uuid; d2 uuid; d3 uuid;
begin
  select id into m from auth.users order by created_at limit 1;
  if m is null then raise exception 'Crear primero un usuario médico en Authentication'; end if;

  insert into medicos (id, nombre, matricula) values (m, 'Dra. Prueba', 'MN 00000')
    on conflict (id) do nothing;

  insert into dispositivos (serie, version_fw) values ('0001','0.1.0'), ('0002','0.1.0'), ('0003','0.1.0')
    on conflict (serie) do nothing;
  select id into d1 from dispositivos where serie = '0001';
  select id into d2 from dispositivos where serie = '0002';
  select id into d3 from dispositivos where serie = '0003';

  insert into pacientes (nombre, apellido, documento, medico_id) values ('Laura', 'Benítez', '30111222', m) returning id into p1;
  insert into pacientes (nombre, apellido, documento, medico_id) values ('Marcos', 'Ferreyra', '27333444', m) returning id into p2;
  insert into pacientes (nombre, apellido, documento, medico_id) values ('Sofía', 'Ruiz', '41555666', m) returning id into p3;

  -- Episodio anterior de Marcos (re-lesión, decisión 004)
  insert into episodios (paciente_id, miembro, lesion, inicio, fin, limite_sup, limite_inf, peso_kg)
    values (p2, 'derecho', 'Fractura de maléolo lateral', current_date - 420, current_date - 360, 20, 0, 82)
    returning id into e0;

  insert into episodios (paciente_id, dispositivo_id, miembro, lesion, fecha_cirugia, inicio, limite_sup, limite_inf, peso_kg)
    values (p1, d1, 'izquierdo', 'Reparación de tendón de Aquiles', current_date - 23, current_date - 21, 30, 15, 64)
    returning id into e1;
  insert into episodios (paciente_id, dispositivo_id, miembro, lesion, fecha_cirugia, inicio, limite_sup, limite_inf, peso_kg)
    values (p2, d2, 'derecho', 'Fractura bimaleolar', current_date - 16, current_date - 14, 20, 0, 82)
    returning id into e2;
  insert into episodios (paciente_id, dispositivo_id, miembro, lesion, fecha_cirugia, inicio, limite_sup, limite_inf, peso_kg)
    values (p3, d3, 'izquierdo', 'Fractura de diáfisis tibial', current_date - 9, current_date - 7, 20, 10, 58)
    returning id into e3;

  -- Resúmenes diarios sintéticos: Laura mejora, Marcos empeora, Sofía apoya de menos
  insert into resumenes_diarios (episodio_id, fecha, dosis_sobrecarga, dosis_subcarga, t_carga_s, t_exceso_s, t_sub_s, pico, excedencias)
  select e1, current_date - d,
         greatest(5, 260 - 11*(21-d) + (random()*40)::int), 20 + (random()*15)::int,
         9000 + (random()*3000)::int,
         greatest(200, 2400 - 100*(21-d) + (random()*300)::int),
         600 + (random()*400)::int,
         38 + random()*10, greatest(2, 40 - 1.6*(21-d))::int
  from generate_series(1, 21) d;

  insert into resumenes_diarios (episodio_id, fecha, dosis_sobrecarga, dosis_subcarga, t_carga_s, t_exceso_s, t_sub_s, pico, excedencias)
  select e2, current_date - d,
         60 + 18*(14-d) + (random()*30)::int, 0,
         10000 + (random()*2500)::int,
         500 + 140*(14-d) + (random()*200)::int,
         0, 28 + (14-d) + random()*5, 8 + 2*(14-d)
  from generate_series(1, 14) d;

  insert into resumenes_diarios (episodio_id, fecha, dosis_sobrecarga, dosis_subcarga, t_carga_s, t_exceso_s, t_sub_s, pico, excedencias)
  select e3, current_date - d,
         (random()*15)::int, 180 + (random()*60)::int,
         7000 + (random()*1500)::int,
         (random()*150)::int,
         4200 + (random()*800)::int,
         19 + random()*4, (random()*3)::int
  from generate_series(1, 7) d;

  insert into resumenes_diarios (episodio_id, fecha, dosis_sobrecarga, dosis_subcarga, t_carga_s, t_exceso_s, t_sub_s, pico, excedencias)
  select e0, (current_date - 420) + d,
         150 - 2*d + (random()*30)::int, 0, 9500, greatest(300, 2000 - 25*d), 0, 35, greatest(3, 30 - d/2)
  from generate_series(0, 59) d;
end $$;
