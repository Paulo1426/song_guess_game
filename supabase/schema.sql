create type public.dificultad as enum ('facil', 'medio', 'avanzado');
create type public.tipo_instrumento as enum (
  'caja', 'guacharaca', 'acordeon', 'piano',
  'guitarra', 'bajo', 'trompeta'
);

create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  nombre text,
  insignias text[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.progreso_usuario (
  usuario_id uuid not null references public.perfiles(id) on delete cascade,
  dificultad public.dificultad not null,
  nivel_actual int not null default 1 check (nivel_actual between 1 and 21),
  niveles_completados int[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (usuario_id, dificultad)
);

create table public.canciones (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  artista text,
  created_at timestamptz not null default now()
);

create table public.niveles (
  id text primary key,
  numero int not null check (numero between 1 and 20),
  dificultad public.dificultad not null,
  cancion_id uuid not null references public.canciones(id),
  instrumento_melodia public.tipo_instrumento not null,
  puntos_inicio int[] not null default '{}',
  unique (dificultad, numero)
);

create table public.nivel_instrumentos (
  nivel_id text not null references public.niveles(id) on delete cascade,
  tipo public.tipo_instrumento not null,
  precio int not null check (precio in (100000, 200000, 300000, 400000)),
  audio_path text not null,
  primary key (nivel_id, tipo)
);

create or replace function public.validar_nivel_instrumentos()
returns trigger language plpgsql as $$
declare total int;
begin
  select coalesce(sum(precio), 0) into total
  from public.nivel_instrumentos where nivel_id = new.nivel_id;
  if total > 2000000 then
    raise exception 'El presupuesto del nivel no puede superar 2000000';
  end if;
  return new;
end;
$$;

create trigger nivel_instrumentos_presupuesto
after insert or update on public.nivel_instrumentos
for each row execute function public.validar_nivel_instrumentos();

create or replace function public.crear_perfil_y_progreso()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, email, nombre)
  values (new.id, new.email, new.raw_user_meta_data ->> 'nombre');
  insert into public.progreso_usuario (usuario_id, dificultad)
  values (new.id, 'facil'), (new.id, 'medio'), (new.id, 'avanzado');
  return new;
end;
$$;

create trigger usuario_registrado
after insert on auth.users
for each row execute function public.crear_perfil_y_progreso();

alter table public.perfiles enable row level security;
alter table public.progreso_usuario enable row level security;
alter table public.canciones enable row level security;
alter table public.niveles enable row level security;
alter table public.nivel_instrumentos enable row level security;

create policy "perfil propio" on public.perfiles
for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "progreso propio" on public.progreso_usuario
for all using (auth.uid() = usuario_id) with check (auth.uid() = usuario_id);
create policy "niveles autenticados" on public.niveles
for select to authenticated using (true);
create policy "canciones autenticadas" on public.canciones
for select to authenticated using (true);
create policy "instrumentos autenticados" on public.nivel_instrumentos
for select to authenticated using (true);

insert into storage.buckets (id, name, public)
values ('instrumentos', 'instrumentos', true)
on conflict (id) do nothing;

create policy "audio publico lectura" on storage.objects
for select using (bucket_id = 'instrumentos');
create policy "audio admin escritura" on storage.objects
for insert to authenticated with check (bucket_id = 'instrumentos');
