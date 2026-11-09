-- NEXUS ARENA schema
-- Run once in the Supabase SQL Editor on a fresh project.

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 18),
  xp integer not null default 0 check (xp >= 0),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  matches_played integer not null default 0 check (matches_played >= 0),
  total_cores integer not null default 0 check (total_cores >= 0),
  unlocked_characters text[] not null default array['guardian','runner','engineer']::text[],
  created_at timestamptz not null default now()
);

create table public.game_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-F0-9]{8}$'),
  host_id uuid not null references auth.users(id) on delete cascade,
  guest_id uuid references auth.users(id) on delete set null,
  status text not null default 'waiting' check (status in ('waiting','playing','finished')),
  created_at timestamptz not null default now(),
  check (guest_id is null or guest_id <> host_id)
);

create table public.match_results (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.game_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  opponent_id uuid references auth.users(id) on delete set null,
  cores integer not null default 0 check (cores between 0 and 999),
  won boolean not null default false,
  character_id text not null check (character_id in ('guardian','runner','engineer','magnetist','illusionist','saboteur','portalero')),
  created_at timestamptz not null default now(),
  unique(room_id,user_id)
);

create table public.achievements (
  id text primary key,
  title text not null,
  description text not null,
  reward_character text
);

create table public.user_achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_id text not null references public.achievements(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  primary key(user_id,achievement_id)
);

insert into public.achievements (id,title,description,reward_character) values
('first_win','Primera victoria','Gana tu primera partida.',null),
('core_hunter','Cazador de núcleos','Entrega 200 núcleos.','magnetist'),
('veteran','Veterano de la arena','Completa 15 partidas.','illusionist'),
('champion','Imparable','Gana 10 partidas.','saboteur'),
('trio_master','Maestro del trío','Juega 5 partidas con cada personaje inicial.','portalero')
on conflict (id) do nothing;

alter table public.profiles enable row level security;
alter table public.game_rooms enable row level security;
alter table public.match_results enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;

grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant insert(id,username) on public.profiles to authenticated;
grant update(username) on public.profiles to authenticated;
grant select on public.game_rooms to authenticated;
grant select on public.match_results to authenticated;
grant select on public.achievements to authenticated;
grant select on public.user_achievements to authenticated;

create policy "Profiles visible to signed-in players" on public.profiles
for select to authenticated using (true);
create policy "Players create their own profile" on public.profiles
for insert to authenticated with check ((select auth.uid())=id);
create policy "Players edit only their own profile" on public.profiles
for update to authenticated using ((select auth.uid())=id)
with check ((select auth.uid())=id);
create policy "Room members can read their room" on public.game_rooms
for select to authenticated using ((select auth.uid())=host_id or (select auth.uid())=guest_id);
create policy "Players read their own match results" on public.match_results
for select to authenticated using ((select auth.uid())=user_id);
create policy "Achievement catalog is visible to signed-in players" on public.achievements
for select to authenticated using (true);
create policy "Players read their own unlocked achievements" on public.user_achievements
for select to authenticated using ((select auth.uid())=user_id);

create or replace function public.create_game_room()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_room public.game_rooms; v_code text; v_attempt integer;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión para crear una sala.'; end if;
  for v_attempt in 1..8 loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text),1,8));
    begin
      insert into public.game_rooms(code,host_id) values(v_code,auth.uid()) returning * into v_room;
      return to_jsonb(v_room);
    exception when unique_violation then
      if v_attempt=8 then raise exception 'No se pudo generar un código. Intenta de nuevo.'; end if;
    end;
  end loop;
  raise exception 'No se pudo crear la sala.';
end;
$$;

create or replace function public.join_game_room(p_code text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_room public.game_rooms;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión para entrar a una sala.'; end if;
  select * into v_room from public.game_rooms where code=upper(trim(p_code)) for update;
  if not found then raise exception 'No existe una sala con ese código.'; end if;
  if v_room.host_id=auth.uid() or v_room.guest_id=auth.uid() then return to_jsonb(v_room); end if;
  if v_room.status<>'waiting' or v_room.guest_id is not null then raise exception 'Esta sala ya está completa.'; end if;
  update public.game_rooms set guest_id=auth.uid(),status='playing' where id=v_room.id returning * into v_room;
  return to_jsonb(v_room);
end;
$$;

create or replace function public.record_match_result(p_code text,p_cores integer,p_won boolean,p_character text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_user_id uuid:=auth.uid();
  v_room public.game_rooms;
  v_profile public.profiles;
  v_inserted integer;
  v_guardian_count integer;
  v_runner_count integer;
  v_engineer_count integer;
begin
  if v_user_id is null then raise exception 'Debes iniciar sesión.'; end if;
  if p_cores<0 or p_cores>999 then raise exception 'Puntuación no válida.'; end if;
  select * into v_room from public.game_rooms where code=upper(trim(p_code)) for update;
  if not found or (v_user_id<>v_room.host_id and v_user_id<>v_room.guest_id) then raise exception 'No perteneces a esta partida.'; end if;
  if v_room.status not in ('playing','finished') then raise exception 'La partida todavía no ha comenzado.'; end if;
  select * into v_profile from public.profiles where id=v_user_id for update;
  if not found then raise exception 'No existe el perfil del jugador.'; end if;
  if not (p_character=any(v_profile.unlocked_characters)) then raise exception 'Ese personaje todavía está bloqueado.'; end if;

  insert into public.match_results(room_id,user_id,opponent_id,cores,won,character_id)
  values(v_room.id,v_user_id,case when v_user_id=v_room.host_id then v_room.guest_id else v_room.host_id end,p_cores,p_won,p_character)
  on conflict(room_id,user_id) do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then return to_jsonb(v_profile); end if;

  update public.profiles set matches_played=matches_played+1,total_cores=total_cores+p_cores,
    wins=wins+case when p_won then 1 else 0 end,
    losses=losses+case when p_won then 0 else 1 end,
    xp=xp+25+(p_cores*10)+case when p_won then 75 else 0 end
  where id=v_user_id returning * into v_profile;

  if v_profile.wins>=1 then
    insert into public.user_achievements(user_id,achievement_id) values(v_user_id,'first_win') on conflict do nothing;
  end if;
  if v_profile.total_cores>=200 then
    update public.profiles set unlocked_characters=array(select distinct unnest(unlocked_characters||array['magnetist'])) where id=v_user_id returning * into v_profile;
    insert into public.user_achievements(user_id,achievement_id) values(v_user_id,'core_hunter') on conflict do nothing;
  end if;
  if v_profile.matches_played>=15 then
    update public.profiles set unlocked_characters=array(select distinct unnest(unlocked_characters||array['illusionist'])) where id=v_user_id returning * into v_profile;
    insert into public.user_achievements(user_id,achievement_id) values(v_user_id,'veteran') on conflict do nothing;
  end if;
  if v_profile.wins>=10 then
    update public.profiles set unlocked_characters=array(select distinct unnest(unlocked_characters||array['saboteur'])) where id=v_user_id returning * into v_profile;
    insert into public.user_achievements(user_id,achievement_id) values(v_user_id,'champion') on conflict do nothing;
  end if;

  select count(*) filter(where character_id='guardian'),
         count(*) filter(where character_id='runner'),
         count(*) filter(where character_id='engineer')
  into v_guardian_count,v_runner_count,v_engineer_count
  from public.match_results where user_id=v_user_id;
  if v_guardian_count>=5 and v_runner_count>=5 and v_engineer_count>=5 then
    update public.profiles set unlocked_characters=array(select distinct unnest(unlocked_characters||array['portalero'])) where id=v_user_id returning * into v_profile;
    insert into public.user_achievements(user_id,achievement_id) values(v_user_id,'trio_master') on conflict do nothing;
  end if;

  if (select count(*) from public.match_results where room_id=v_room.id)>=(case when v_room.guest_id is null then 1 else 2 end) then
    update public.game_rooms set status='finished' where id=v_room.id;
  end if;
  return to_jsonb(v_profile);
end;
$$;

revoke all on function public.create_game_room() from public,anon;
revoke all on function public.join_game_room(text) from public,anon;
revoke all on function public.record_match_result(text,integer,boolean,text) from public,anon;
grant execute on function public.create_game_room() to authenticated;
grant execute on function public.join_game_room(text) to authenticated;
grant execute on function public.record_match_result(text,integer,boolean,text) to authenticated;

create index if not exists game_rooms_host_id_idx on public.game_rooms(host_id);
create index if not exists game_rooms_guest_id_idx on public.game_rooms(guest_id);
create index if not exists match_results_user_id_idx on public.match_results(user_id);
create index if not exists match_results_opponent_id_idx on public.match_results(opponent_id);
create index if not exists user_achievements_achievement_id_idx on public.user_achievements(achievement_id);
