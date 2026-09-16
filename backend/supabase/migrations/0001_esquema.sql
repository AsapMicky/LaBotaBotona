-- Dosímetro de carga plantar — esquema inicial
-- Ver docs/modelo-datos.md

create extension if not exists pgcrypto;

create table public.medicos (
  id         uuid primary key references auth.users(id) on delete cascade,
  nombre     text not null,
  matricula  text,
  creado     timestamptz not null default now()
);

create sequence public.pacientes_codigo_seq;

create table public.pacientes (
  id                uuid primary key default gen_random_uuid(),
  codigo            text not null unique
                    default 'P-' || lpad(nextval('public.pacientes_codigo_seq')::text, 6, '0'),
  nombre            text not null,
  apellido          text not null,
  documento         text,            -- solo referencia, NO es clave (docs/decisiones/002)
  fecha_nacimiento  date,
  medico_id         uuid not null references public.medicos(id),
  creado            timestamptz not null default now()
);
create index on public.pacientes (medico_id);
create index on public.pacientes (documento);

create table public.dispositivos (
  id          uuid primary key default gen_random_uuid(),
  serie       text not null unique,
  version_fw  text,
  creado      timestamptz not null default now()
);

create table public.episodios (
  id              uuid primary key default gen_random_uuid(),
  paciente_id     uuid not null references public.pacientes(id) on delete cascade,
  dispositivo_id  uuid references public.dispositivos(id),
  miembro         text not null check (miembro in ('izquierdo', 'derecho')),
  lesion          text not null,
  fecha_cirugia   date,
  inicio          date not null default current_date,
  fin             date,
  limite_sup      numeric(4,1) not null check (limite_sup > 0 and limite_sup <= 100),
  limite_inf      numeric(4,1) not null default 0 check (limite_inf >= 0),
  peso_kg         numeric(5,1),
  token_sync      uuid not null unique default gen_random_uuid(),
  notas           text,
  creado          timestamptz not null default now(),
  check (limite_inf < limite_sup),
  check (fin is null or fin >= inicio)
);
-- Una ortesis no puede estar en dos tratamientos abiertos a la vez
create unique index episodios_un_abierto_por_dispositivo
  on public.episodios (dispositivo_id) where fin is null and dispositivo_id is not null;
create index on public.episodios (paciente_id);

-- Lo que baja del equipo (docs/protocolo-ble.md)
create table public.resumenes_diarios (
  episodio_id       uuid not null references public.episodios(id) on delete cascade,
  fecha             date not null,
  dosis_sobrecarga  real not null,   -- %PC·min
  dosis_subcarga    real not null,
  t_carga_s         integer not null,
  t_exceso_s        integer not null,
  t_sub_s           integer not null,
  pico              real not null,   -- %PC
  excedencias       integer not null,
  recibido          timestamptz not null default now(),
  primary key (episodio_id, fecha)
);

create table public.registros_minuto (
  episodio_id   uuid not null references public.episodios(id) on delete cascade,
  ts            timestamptz not null,
  carga_media   real not null,
  carga_pico    real not null,
  dosis         real not null,
  excedencias   smallint not null,
  seg_apoyo     smallint not null,
  primary key (episodio_id, ts)
);

-- Índices derivados (Anexo A)
create view public.resumenes_con_indices
with (security_invoker = true) as
select r.*,
  (r.t_carga_s - r.t_exceso_s - r.t_sub_s)                                   as t_ventana_s,
  case when r.t_carga_s > 0
       then round((100.0 * (1 - r.t_exceso_s::numeric / r.t_carga_s)), 1) end as cumplimiento,
  case when r.t_carga_s > 0
       then round((100.0 * (r.t_carga_s - r.t_exceso_s - r.t_sub_s) / r.t_carga_s), 1) end as permanencia
from public.resumenes_diarios r;

-- ---------------- Seguridad por fila ----------------
alter table public.medicos           enable row level security;
alter table public.pacientes         enable row level security;
alter table public.dispositivos      enable row level security;
alter table public.episodios         enable row level security;
alter table public.resumenes_diarios enable row level security;
alter table public.registros_minuto  enable row level security;

create policy "medico ve su perfil" on public.medicos
  for select using (id = auth.uid());
create policy "medico edita su perfil" on public.medicos
  for update using (id = auth.uid());

create policy "medico gestiona sus pacientes" on public.pacientes
  for all using (medico_id = auth.uid()) with check (medico_id = auth.uid());

create policy "medicos ven dispositivos" on public.dispositivos
  for select using (exists (select 1 from public.medicos m where m.id = auth.uid()));

create or replace function public.es_mi_episodio(ep uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from episodios e join pacientes p on p.id = e.paciente_id
    where e.id = ep and p.medico_id = auth.uid()
  );
$$;

create policy "medico gestiona episodios de sus pacientes" on public.episodios
  for all using (exists (select 1 from public.pacientes p
                         where p.id = paciente_id and p.medico_id = auth.uid()))
  with check (exists (select 1 from public.pacientes p
                      where p.id = paciente_id and p.medico_id = auth.uid()));

create policy "medico lee resumenes" on public.resumenes_diarios
  for select using (public.es_mi_episodio(episodio_id));
create policy "medico lee registros" on public.registros_minuto
  for select using (public.es_mi_episodio(episodio_id));
-- La escritura de resumenes/registros la hace solo la función subir-datos (service role).
