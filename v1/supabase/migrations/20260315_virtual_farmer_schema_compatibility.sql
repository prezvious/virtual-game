-- Virtual Farmer compatibility schema for legacy client reads/writes.
-- Restores `profiles`, `player_progress`, and `leaderboard` objects expected by
-- `/farmer-legacy/*` runtime without modifying Fisher schema objects.

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  updated_at timestamp with time zone not null default timezone('utc'::text, now())
);

alter table public.profiles
  add column if not exists display_name text;
alter table public.profiles
  add column if not exists created_at timestamp with time zone not null default timezone('utc'::text, now());
alter table public.profiles
  add column if not exists updated_at timestamp with time zone not null default timezone('utc'::text, now());

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_display_name_length'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_display_name_length
      check (char_length(trim(display_name)) between 3 and 24);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_display_name_safe'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_display_name_safe
      check (display_name ~ '^[A-Za-z0-9 ._''-]{3,24}$');
  end if;
end;
$$;

create table if not exists public.player_progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance double precision not null default 0 check (balance >= 0),
  xp double precision not null default 0 check (xp >= 0),
  total_plants double precision not null default 0 check (total_plants >= 0),
  prestige_level integer not null default 0 check (prestige_level >= 0),
  achievements_count integer not null default 0 check (achievements_count >= 0),
  game_state jsonb not null default '{}'::jsonb,
  stats_state jsonb not null default '{}'::jsonb,
  auto_farm_state jsonb not null default '{}'::jsonb,
  last_saved_at timestamp with time zone not null default timezone('utc'::text, now()),
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  updated_at timestamp with time zone not null default timezone('utc'::text, now())
);

alter table public.player_progress
  add column if not exists balance double precision not null default 0;
alter table public.player_progress
  add column if not exists xp double precision not null default 0;
alter table public.player_progress
  add column if not exists total_plants double precision not null default 0;
alter table public.player_progress
  add column if not exists prestige_level integer not null default 0;
alter table public.player_progress
  add column if not exists achievements_count integer not null default 0;
alter table public.player_progress
  add column if not exists game_state jsonb not null default '{}'::jsonb;
alter table public.player_progress
  add column if not exists stats_state jsonb not null default '{}'::jsonb;
alter table public.player_progress
  add column if not exists auto_farm_state jsonb not null default '{}'::jsonb;
alter table public.player_progress
  add column if not exists last_saved_at timestamp with time zone not null default timezone('utc'::text, now());
alter table public.player_progress
  add column if not exists created_at timestamp with time zone not null default timezone('utc'::text, now());
alter table public.player_progress
  add column if not exists updated_at timestamp with time zone not null default timezone('utc'::text, now());

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'player_progress_balance_nonnegative'
      and conrelid = 'public.player_progress'::regclass
  ) then
    alter table public.player_progress
      add constraint player_progress_balance_nonnegative
      check (balance >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'player_progress_xp_nonnegative'
      and conrelid = 'public.player_progress'::regclass
  ) then
    alter table public.player_progress
      add constraint player_progress_xp_nonnegative
      check (xp >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'player_progress_total_plants_nonnegative'
      and conrelid = 'public.player_progress'::regclass
  ) then
    alter table public.player_progress
      add constraint player_progress_total_plants_nonnegative
      check (total_plants >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'player_progress_prestige_level_nonnegative'
      and conrelid = 'public.player_progress'::regclass
  ) then
    alter table public.player_progress
      add constraint player_progress_prestige_level_nonnegative
      check (prestige_level >= 0);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'player_progress_achievements_count_nonnegative'
      and conrelid = 'public.player_progress'::regclass
  ) then
    alter table public.player_progress
      add constraint player_progress_achievements_count_nonnegative
      check (achievements_count >= 0);
  end if;
end;
$$;

create index if not exists idx_player_progress_total_plants_desc
  on public.player_progress (total_plants desc, updated_at desc);

create index if not exists idx_player_progress_balance_desc
  on public.player_progress (balance desc, updated_at desc);

create index if not exists idx_player_progress_xp_desc
  on public.player_progress (xp desc, updated_at desc);

create or replace function public.set_profiles_updated_at_compat()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

create or replace function public.set_player_progress_updated_at_compat()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists trg_profiles_updated_at_compat on public.profiles;
create trigger trg_profiles_updated_at_compat
before update on public.profiles
for each row
execute function public.set_profiles_updated_at_compat();

drop trigger if exists trg_player_progress_updated_at_compat on public.player_progress;
create trigger trg_player_progress_updated_at_compat
before update on public.player_progress
for each row
execute function public.set_player_progress_updated_at_compat();

alter table public.profiles enable row level security;
alter table public.player_progress enable row level security;

drop policy if exists profiles_select_authenticated on public.profiles;
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
on public.profiles
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
on public.profiles
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
on public.profiles
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists progress_select_authenticated on public.player_progress;
drop policy if exists progress_select_own on public.player_progress;
create policy progress_select_own
on public.player_progress
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists progress_insert_own on public.player_progress;
create policy progress_insert_own
on public.player_progress
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists progress_update_own on public.player_progress;
create policy progress_update_own
on public.player_progress
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create or replace view public.leaderboard as
select
  p.user_id,
  coalesce(pr.display_name, 'Farmer-' || left(p.user_id::text, 8)) as display_name,
  p.total_plants,
  p.balance,
  p.xp,
  p.prestige_level,
  p.achievements_count,
  p.updated_at
from public.player_progress p
left join public.profiles pr
  on pr.user_id = p.user_id;

revoke all on table public.profiles from anon;
revoke all on table public.player_progress from anon;
revoke all on table public.leaderboard from anon;

grant select, insert, update on table public.profiles to authenticated;
grant select, insert, update on table public.player_progress to authenticated;
grant select on table public.leaderboard to authenticated;
