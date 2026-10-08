-- Migracion para agregar fragmentos, partidas y compras.
-- Ejecutar despues de supabase/schema.sql.
--
-- Requisitos creados por schema.sql:
-- public.canciones
-- public.niveles
-- public.perfiles
-- public.nivel_instrumentos
-- public.tipo_instrumento

begin;

-- 1. Un fragmento normal dura 30 segundos; el modo de prueba admite 20.
create table if not exists public.fragmentos_audio (
  id uuid primary key default gen_random_uuid(),
  cancion_id uuid not null
    references public.canciones(id) on delete cascade,
  numero integer not null
    check (numero > 0),
  inicio_segundos integer not null
    check (inicio_segundos >= 0),
  duracion_segundos integer not null default 30,
  created_at timestamptz not null default now(),
  unique (cancion_id, numero)
);

alter table public.fragmentos_audio
  drop constraint if exists fragmentos_audio_duracion_segundos_check;
alter table public.fragmentos_audio
  add constraint fragmentos_audio_duracion_segundos_check
  check (duracion_segundos in (20, 30)) not valid;

create index if not exists fragmentos_audio_cancion_idx
  on public.fragmentos_audio(cancion_id);

-- 2. Cada instrumento de un nivel puede apuntar a su archivo del fragmento.
alter table public.nivel_instrumentos
  add column if not exists fragmento_id uuid
    references public.fragmentos_audio(id) on delete restrict;

create index if not exists nivel_instrumentos_fragmento_idx
  on public.nivel_instrumentos(fragmento_id);

-- 3. Una partida pertenece a un usuario y a un nivel.
create table if not exists public.partidas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null
    references public.perfiles(id) on delete cascade,
  nivel_id text not null
    references public.niveles(id) on delete restrict,
  presupuesto_restante integer not null default 1000000
    check (presupuesto_restante between 0 and 1000000),
  punto_inicio integer not null
    check (punto_inicio >= 0),
  instrumentos_comprados public.tipo_instrumento[] not null default '{}',
  melodia_descubierta boolean not null default false,
  ganada boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists partidas_usuario_idx
  on public.partidas(usuario_id, updated_at desc);

create index if not exists partidas_nivel_idx
  on public.partidas(nivel_id);

-- Actualiza las partidas existentes a la nueva economia de $1.000.000.
update public.partidas
set presupuesto_restante = least(presupuesto_restante, 1000000)
where presupuesto_restante > 1000000;

alter table public.partidas
  drop constraint if exists partidas_presupuesto_restante_check;
alter table public.partidas
  add constraint partidas_presupuesto_restante_check
  check (presupuesto_restante between 0 and 1000000);

-- 4. Las compras dependen de que exista una partida.
alter type public.tipo_instrumento add value if not exists 'bateria';

create table if not exists public.compras_partida (
  id uuid primary key default gen_random_uuid(),
  partida_id uuid not null
    references public.partidas(id) on delete cascade,
  instrumento public.tipo_instrumento not null,
  precio integer not null
    check (precio in (300000, 400000)),
  created_at timestamptz not null default now(),
  unique (partida_id, instrumento)
);

alter table public.compras_partida
  drop constraint if exists compras_partida_precio_check;
-- Conserva registros historicos con precios anteriores; las compras nuevas
-- deben cumplir el rango vigente.
alter table public.compras_partida
  add constraint compras_partida_precio_check
  check (precio in (300000, 400000)) not valid;

create index if not exists compras_partida_partida_idx
  on public.compras_partida(partida_id);

-- Mantiene updated_at actualizado al modificar una partida.
create or replace function public.actualizar_partida_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists partidas_updated_at on public.partidas;
create trigger partidas_updated_at
before update on public.partidas
for each row
execute function public.actualizar_partida_updated_at();

-- Seguridad: el usuario solo puede consultar y modificar sus propias partidas
-- y sus propias compras. Los fragmentos son informacion publica para usuarios
-- autenticados.
alter table public.fragmentos_audio enable row level security;
alter table public.partidas enable row level security;
alter table public.compras_partida enable row level security;

drop policy if exists "fragmentos autenticados" on public.fragmentos_audio;
create policy "fragmentos autenticados"
on public.fragmentos_audio
for select
to authenticated
using (true);

drop policy if exists "partidas propias select" on public.partidas;
create policy "partidas propias select"
on public.partidas
for select
to authenticated
using (auth.uid() = usuario_id);

drop policy if exists "partidas propias insert" on public.partidas;
create policy "partidas propias insert"
on public.partidas
for insert
to authenticated
with check (auth.uid() = usuario_id);

drop policy if exists "partidas propias update" on public.partidas;
create policy "partidas propias update"
on public.partidas
for update
to authenticated
using (auth.uid() = usuario_id)
with check (auth.uid() = usuario_id);

drop policy if exists "partidas propias delete" on public.partidas;
create policy "partidas propias delete"
on public.partidas
for delete
to authenticated
using (auth.uid() = usuario_id);

drop policy if exists "compras de partidas propias" on public.compras_partida;
create policy "compras de partidas propias"
on public.compras_partida
for all
to authenticated
using (
  exists (
    select 1
    from public.partidas p
    where p.id = compras_partida.partida_id
      and p.usuario_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.partidas p
    where p.id = compras_partida.partida_id
      and p.usuario_id = auth.uid()
  )
);

commit;
