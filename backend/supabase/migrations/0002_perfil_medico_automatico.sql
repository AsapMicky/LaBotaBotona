-- El alta de un médico ocurre en auth.users (Authentication → Users), pero las
-- policies y la clave foránea de pacientes necesitan una fila en public.medicos.
-- Sin esto, un médico recién creado no puede dar de alta pacientes ni ver ortesis.

create or replace function public.crear_perfil_medico()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.medicos (id, nombre, matricula)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'nombre'), ''),
      split_part(new.email, '@', 1)
    ),
    nullif(trim(new.raw_user_meta_data ->> 'matricula'), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger crear_perfil_medico_al_registrarse
  after insert on auth.users
  for each row execute function public.crear_perfil_medico();

-- Los usuarios que ya existían quedan con su perfil.
insert into public.medicos (id, nombre)
select u.id, split_part(u.email, '@', 1)
from auth.users u
where not exists (select 1 from public.medicos m where m.id = u.id)
on conflict (id) do nothing;
