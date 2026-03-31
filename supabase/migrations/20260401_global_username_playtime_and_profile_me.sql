-- Global username + playtime tracking cleanup for Virtual Fisher / Virtual Farmer.
-- 1) Adds additive per-game playtime tracking from April 1, 2026 onward.
-- 2) Switches Virtual Farmer leaderboard identity to public.user_profiles.username.

create table if not exists public.user_game_stats (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_key text not null,
  playtime_seconds bigint not null default 0,
  last_played_at timestamp with time zone not null default timezone('utc'::text, now()),
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  updated_at timestamp with time zone not null default timezone('utc'::text, now()),
  constraint user_game_stats_pkey primary key (user_id, game_key),
  constraint user_game_stats_game_key_check check (game_key in ('fisher', 'farmer')),
  constraint user_game_stats_playtime_nonnegative check (playtime_seconds >= 0)
);

create index if not exists idx_user_game_stats_game_key
  on public.user_game_stats (game_key, playtime_seconds desc, updated_at desc);

create or replace function public.set_user_game_stats_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists trg_user_game_stats_updated_at on public.user_game_stats;
create trigger trg_user_game_stats_updated_at
before update on public.user_game_stats
for each row
execute function public.set_user_game_stats_updated_at();

alter table public.user_game_stats enable row level security;

drop policy if exists user_game_stats_select_own on public.user_game_stats;
create policy user_game_stats_select_own
on public.user_game_stats
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists user_game_stats_insert_own on public.user_game_stats;
create policy user_game_stats_insert_own
on public.user_game_stats
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists user_game_stats_update_own on public.user_game_stats;
create policy user_game_stats_update_own
on public.user_game_stats
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

grant select, insert, update on table public.user_game_stats to authenticated;

create or replace function public.increment_user_game_playtime(p_game_key text, p_delta_seconds integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_game_key text := lower(trim(coalesce(p_game_key, '')));
  v_delta_seconds integer := greatest(0, least(coalesce(p_delta_seconds, 0), 300));
  v_row public.user_game_stats%rowtype;
begin
  if v_uid is null then
    return jsonb_build_object(
      'ok', false,
      'reason', 'You must be signed in.'
    );
  end if;

  if v_game_key not in ('fisher', 'farmer') then
    return jsonb_build_object(
      'ok', false,
      'reason', 'Unsupported game key.'
    );
  end if;

  if v_delta_seconds <= 0 then
    return jsonb_build_object(
      'ok', true,
      'game_key', v_game_key,
      'delta_seconds', 0
    );
  end if;

  insert into public.user_game_stats (
    user_id,
    game_key,
    playtime_seconds,
    last_played_at
  )
  values (
    v_uid,
    v_game_key,
    v_delta_seconds,
    timezone('utc'::text, now())
  )
  on conflict (user_id, game_key) do update
    set playtime_seconds = public.user_game_stats.playtime_seconds + excluded.playtime_seconds,
        last_played_at = excluded.last_played_at
  returning *
  into v_row;

  return jsonb_build_object(
    'ok', true,
    'game_key', v_row.game_key,
    'delta_seconds', v_delta_seconds,
    'playtime_seconds', v_row.playtime_seconds,
    'last_played_at', v_row.last_played_at
  );
end;
$$;

revoke all on function public.increment_user_game_playtime(text, integer) from public;
grant execute on function public.increment_user_game_playtime(text, integer) to authenticated;

alter table public.farmer_leaderboard_cache
  add column if not exists username text;

create or replace function public.refresh_farmer_leaderboard_cache()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refreshed_at timestamp with time zone := timezone('utc'::text, now());
begin
  delete from public.farmer_leaderboard_cache;

  insert into public.farmer_leaderboard_cache (
    user_id,
    display_name,
    username,
    total_plants,
    balance,
    xp,
    prestige_level,
    achievements_count,
    updated_at,
    refreshed_at
  )
  select
    p.user_id,
    up.username,
    up.username,
    greatest(0, coalesce(p.total_plants, 0)),
    greatest(0, coalesce(p.balance, 0)),
    greatest(0, coalesce(p.xp, 0)),
    greatest(0, coalesce(p.prestige_level, 0)),
    greatest(0, coalesce(p.achievements_count, 0)),
    coalesce(p.last_saved_at, p.updated_at, v_refreshed_at),
    v_refreshed_at
  from public.player_progress p
  inner join public.user_profiles up
    on up.user_id = p.user_id
  where up.username is not null;
end;
$$;

create or replace view public.leaderboard as
select
  user_id,
  username,
  username as display_name,
  total_plants,
  balance,
  xp,
  prestige_level,
  achievements_count,
  updated_at,
  refreshed_at
from public.farmer_leaderboard_cache
where username is not null;

grant select on public.leaderboard to authenticated;

select public.refresh_farmer_leaderboard_cache();
