-- LPHONK PLAY: run this in Supabase SQL Editor.
-- Uses Supabase Auth, Row Level Security and a public read-only leaderboard.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null default 'Player' check (char_length(username) between 3 and 20),
  total_score bigint not null default 0 check (total_score >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.game_scores (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  score integer not null check (score between 0 and 1000000),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.game_scores enable row level security;

drop policy if exists "Profiles are publicly readable" on public.profiles;
create policy "Profiles are publicly readable"
on public.profiles for select using (true);

drop policy if exists "Users can create own profile" on public.profiles;
create policy "Users can create own profile"
on public.profiles for insert to authenticated
with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "Scores are publicly readable" on public.game_scores;
create policy "Scores are publicly readable"
on public.game_scores for select using (true);

drop policy if exists "Users can submit own scores" on public.game_scores;
create policy "Users can submit own scores"
on public.game_scores for insert to authenticated
with check (auth.uid() = user_id);

-- Maintain aggregate scores server-side after inserts.
create or replace function public.update_profile_score()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, total_score)
  values (new.user_id, 'Player', new.score)
  on conflict (id) do update
  set total_score = public.profiles.total_score + new.score;
  return new;
end;
$$;

drop trigger if exists on_game_score_insert on public.game_scores;
create trigger on_game_score_insert
after insert on public.game_scores
for each row execute function public.update_profile_score();

create or replace view public.leaderboard
with (security_invoker = true)
as
select username, total_score
from public.profiles
order by total_score desc, username asc;

grant select on public.leaderboard to anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select on public.profiles to anon;
grant select, insert on public.game_scores to authenticated;
grant select on public.game_scores to anon;

-- Realtime presence/broadcast is enabled by Supabase Realtime channels.
-- The browser client uses a public room channel; no database table is required.
