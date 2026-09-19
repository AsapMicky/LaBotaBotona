-- La carga permitida se progresa durante la rehabilitación, y el peso de la persona
-- cambia en meses de tratamiento. Antes no había forma de corregirlo sin cerrar el
-- episodio y abrir otro, lo que partía la serie de datos en dos.
--
-- La dosis de sobrecarga es la integral de lo que excede el límite, así que depende de L:
-- los días de antes y los de después de un cambio no son comparables en dosis. Por eso se
-- guarda cuándo cambió, para poder marcarlo en el gráfico. El cumplimiento y la
-- permanencia en ventana sí siguen siendo comparables: son relativos a su propio límite.

create table public.indicaciones (
  id          uuid primary key default gen_random_uuid(),
  episodio_id uuid not null references public.episodios(id) on delete cascade,
  desde       date not null default current_date,
  limite_sup  numeric(4,1) not null,
  limite_inf  numeric(4,1) not null default 0,
  peso_kg     numeric(5,1),
  nota        text,
  creado      timestamptz not null default now()
);
create index on public.indicaciones (episodio_id, desde);

alter table public.indicaciones enable row level security;
create policy "medico lee las indicaciones de sus episodios" on public.indicaciones
  for select using (public.es_mi_episodio(episodio_id));

-- La historia se escribe sola: ningún camino de la app puede olvidarse de registrarla.
create or replace function public.registrar_indicacion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT'
     or new.limite_sup is distinct from old.limite_sup
     or new.limite_inf is distinct from old.limite_inf
     or new.peso_kg    is distinct from old.peso_kg then
    insert into public.indicaciones (episodio_id, limite_sup, limite_inf, peso_kg)
    values (new.id, new.limite_sup, new.limite_inf, new.peso_kg);
  end if;
  return new;
end $$;

create trigger registrar_indicacion_al_cambiar
  after insert or update on public.episodios
  for each row execute function public.registrar_indicacion();

-- Cambiar la indicación en una sola operación: el episodio y su historia van juntos.
create or replace function public.cambiar_indicacion(
  ep uuid, sup numeric, inf numeric, peso numeric, nota_txt text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.es_mi_episodio(ep) then
    raise exception 'Este tratamiento no es tuyo';
  end if;
  if inf >= sup then
    raise exception 'El mínimo tiene que ser menor que el máximo';
  end if;

  update public.episodios
     set limite_sup = sup, limite_inf = inf, peso_kg = peso
   where id = ep and fin is null;
  if not found then
    raise exception 'El tratamiento está cerrado';
  end if;

  if nota_txt is not null and length(trim(nota_txt)) > 0 then
    update public.indicaciones set nota = trim(nota_txt)
     where id = (select id from public.indicaciones
                  where episodio_id = ep order by creado desc, id desc limit 1);
  end if;
end $$;

-- El trigger no es para llamarse de afuera. `cambiar_indicacion` sí: es la puerta que usa
-- la web, y por eso lo primero que hace es verificar que el episodio sea del médico que
-- llama. El linter de Supabase la marca igual, y es a propósito.
revoke execute on function public.registrar_indicacion() from public, anon, authenticated;
grant execute on function public.registrar_indicacion() to postgres, service_role;
revoke execute on function public.cambiar_indicacion(uuid, numeric, numeric, numeric, text) from public, anon;
grant execute on function public.cambiar_indicacion(uuid, numeric, numeric, numeric, text) to authenticated, postgres, service_role;

-- La indicación inicial de los episodios que ya existían.
insert into public.indicaciones (episodio_id, desde, limite_sup, limite_inf, peso_kg)
select e.id, e.inicio, e.limite_sup, e.limite_inf, e.peso_kg
from public.episodios e
where not exists (select 1 from public.indicaciones i where i.episodio_id = e.id);
