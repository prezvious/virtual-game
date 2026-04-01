-- Virtual Harvest fresh Supabase setup
-- Generated from supabase/migrations in filename order.
-- Use this file only for a brand-new Supabase database or a full reset.
-- Do not paste this into an existing project that has already applied migrations.
-- Generated at: 2026-04-01T07:08:59.909Z
-- ============================================================================
-- SOURCE MIGRATION: 20260308_create_game_saves.sql
-- ============================================================================

-- Supabase migration for cloud game saves (JSONB-based).
-- Stores the full engine state object (`this.state`) in `save_data`.

create table if not exists public.game_saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  save_data jsonb not null default '{}'::jsonb,
  save_version integer not null default 4,
  checksum integer,
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  updated_at timestamp with time zone not null default timezone('utc'::text, now()),
  constraint game_saves_save_data_is_object check (jsonb_typeof(save_data) = 'object')
);

alter table public.game_saves
  alter column save_version set default 4;

create or replace function public.set_game_saves_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists trg_game_saves_updated_at on public.game_saves;
create trigger trg_game_saves_updated_at
before update on public.game_saves
for each row
execute function public.set_game_saves_updated_at();

alter table public.game_saves enable row level security;

drop policy if exists "game_saves_select_own" on public.game_saves;
create policy "game_saves_select_own"
on public.game_saves
for select
using (auth.uid() = user_id);

drop policy if exists "game_saves_insert_own" on public.game_saves;
create policy "game_saves_insert_own"
on public.game_saves
for insert
with check (auth.uid() = user_id);

drop policy if exists "game_saves_update_own" on public.game_saves;
create policy "game_saves_update_own"
on public.game_saves
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "game_saves_delete_own" on public.game_saves;
create policy "game_saves_delete_own"
on public.game_saves
for delete
using (auth.uid() = user_id);

-- ============================================================================
-- SOURCE MIGRATION: 20260309_fix_username_underscore_validation.sql
-- ============================================================================

-- Fix username validation false positives for consecutive underscores.
-- In SQL LIKE patterns, '_' is a wildcard; use literal substring detection instead.

create or replace function public.validate_username(candidate text)
returns table (
  is_valid boolean,
  normalized text,
  reason text
)
language plpgsql
immutable
as $$
declare
  v_reserved constant text[] := array[
    'admin', 'administrator', 'system', 'support', 'staff',
    'moderator', 'mod', 'owner', 'developer', 'team',
    'supabase', 'postgres', 'root', 'null', 'undefined',
    'fishit', 'virtualfisher'
  ];
begin
  normalized := public.normalize_username(candidate);

  if normalized is null then
    is_valid := false;
    reason := 'Username is required.';
    return next;
    return;
  end if;

  if length(normalized) < 3 or length(normalized) > 20 then
    is_valid := false;
    reason := 'Username must be 3-20 characters.';
    return next;
    return;
  end if;

  if normalized !~ '^[a-z][a-z0-9_]{2,19}$' then
    is_valid := false;
    reason := 'Use letters, numbers, underscores, and start with a letter.';
    return next;
    return;
  end if;

  if position('__' in normalized) > 0 then
    is_valid := false;
    reason := 'Username cannot contain consecutive underscores.';
    return next;
    return;
  end if;

  if normalized = any(v_reserved) then
    is_valid := false;
    reason := 'That username is reserved.';
    return next;
    return;
  end if;

  is_valid := true;
  reason := 'Username is available.';
  return next;
end;
$$;

-- ============================================================================
-- SOURCE MIGRATION: 20260309_leaderboard_access_and_manual_refresh.sql
-- ============================================================================

-- Ensure leaderboard rows are readable from the web client and add
-- an authenticated fallback refresh RPC for environments without pg_cron.

grant select on table public.leaderboard_snapshots to anon, authenticated;

grant select, insert, update on table public.user_profiles to authenticated;

create or replace function public.request_leaderboard_refresh()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamp with time zone := timezone('utc'::text, now());
  v_last_refreshed_at timestamp with time zone;
begin
  if v_uid is null then
    return jsonb_build_object(
      'ok', false,
      'refreshed', false,
      'reason', 'You must be signed in.'
    );
  end if;

  select max(ls.refreshed_at)
  into v_last_refreshed_at
  from public.leaderboard_snapshots ls;

  if v_last_refreshed_at is not null and (v_now - v_last_refreshed_at) < interval '60 seconds' then
    return jsonb_build_object(
      'ok', true,
      'refreshed', false,
      'reason', 'Leaderboard was refreshed recently.'
    );
  end if;

  perform public.refresh_leaderboards();

  return jsonb_build_object(
    'ok', true,
    'refreshed', true
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'refreshed', false,
      'reason', sqlerrm
    );
end;
$$;

revoke all on function public.request_leaderboard_refresh() from public;
grant execute on function public.request_leaderboard_refresh() to authenticated;

-- ============================================================================
-- SOURCE MIGRATION: 20260309_usernames_and_leaderboards.sql
-- ============================================================================

-- Supabase migration: username profiles + leaderboard snapshots
-- Adds:
-- 1) Unique username system with availability + claim RPC helpers.
-- 2) Public leaderboard snapshots for money earned and fish caught.
-- 3) 10-minute cron refresh for leaderboard snapshots.

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text,
  username_normalized text,
  username_set_at timestamp with time zone,
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  updated_at timestamp with time zone not null default timezone('utc'::text, now()),
  constraint user_profiles_username_format
    check (
      username is null
      or username ~ '^[A-Za-z][A-Za-z0-9_]{2,19}$'
    ),
  constraint user_profiles_username_pairing
    check (
      (username is null and username_normalized is null)
      or (username is not null and username_normalized = lower(username))
    )
);

create unique index if not exists user_profiles_username_normalized_unique
  on public.user_profiles (username_normalized)
  where username_normalized is not null;

create index if not exists user_profiles_username_set_idx
  on public.user_profiles (username_set_at desc nulls last);

create or replace function public.set_user_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists trg_user_profiles_updated_at on public.user_profiles;
create trigger trg_user_profiles_updated_at
before update on public.user_profiles
for each row
execute function public.set_user_profiles_updated_at();

create or replace function public.normalize_username(candidate text)
returns text
language sql
immutable
as $$
  select nullif(lower(trim(candidate)), '');
$$;

create or replace function public.validate_username(candidate text)
returns table (
  is_valid boolean,
  normalized text,
  reason text
)
language plpgsql
immutable
as $$
declare
  v_reserved constant text[] := array[
    'admin', 'administrator', 'system', 'support', 'staff',
    'moderator', 'mod', 'owner', 'developer', 'team',
    'supabase', 'postgres', 'root', 'null', 'undefined',
    'fishit', 'virtualfisher'
  ];
begin
  normalized := public.normalize_username(candidate);

  if normalized is null then
    is_valid := false;
    reason := 'Username is required.';
    return next;
    return;
  end if;

  if length(normalized) < 3 or length(normalized) > 20 then
    is_valid := false;
    reason := 'Username must be 3-20 characters.';
    return next;
    return;
  end if;

  if normalized !~ '^[a-z][a-z0-9_]{2,19}$' then
    is_valid := false;
    reason := 'Use letters, numbers, underscores, and start with a letter.';
    return next;
    return;
  end if;

  if position('__' in normalized) > 0 then
    is_valid := false;
    reason := 'Username cannot contain consecutive underscores.';
    return next;
    return;
  end if;

  if normalized = any(v_reserved) then
    is_valid := false;
    reason := 'That username is reserved.';
    return next;
    return;
  end if;

  is_valid := true;
  reason := 'Username is available.';
  return next;
end;
$$;

create or replace function public.check_username_availability(candidate text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_validation record;
  v_exists boolean;
  v_uid uuid := auth.uid();
begin
  select *
  into v_validation
  from public.validate_username(candidate)
  limit 1;

  if coalesce(v_validation.is_valid, false) = false then
    return jsonb_build_object(
      'available', false,
      'normalized', v_validation.normalized,
      'reason', coalesce(v_validation.reason, 'Invalid username.')
    );
  end if;

  select exists(
    select 1
    from public.user_profiles up
    where up.username_normalized = v_validation.normalized
      and (v_uid is null or up.user_id <> v_uid)
  )
  into v_exists;

  return jsonb_build_object(
    'available', not v_exists,
    'normalized', v_validation.normalized,
    'reason', case when v_exists then 'That username is already in use.' else 'Username is available.' end
  );
end;
$$;

create or replace function public._claim_username_for_user(target_user_id uuid, candidate text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_validation record;
  v_conflict_user uuid;
begin
  if target_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing user id.');
  end if;

  select *
  into v_validation
  from public.validate_username(candidate)
  limit 1;

  if coalesce(v_validation.is_valid, false) = false then
    return jsonb_build_object(
      'ok', false,
      'reason', coalesce(v_validation.reason, 'Invalid username.')
    );
  end if;

  select up.user_id
  into v_conflict_user
  from public.user_profiles up
  where up.username_normalized = v_validation.normalized
    and up.user_id <> target_user_id
  limit 1;

  if v_conflict_user is not null then
    return jsonb_build_object('ok', false, 'reason', 'That username is already in use.');
  end if;

  begin
    insert into public.user_profiles (
      user_id,
      username,
      username_normalized,
      username_set_at
    )
    values (
      target_user_id,
      v_validation.normalized,
      v_validation.normalized,
      timezone('utc'::text, now())
    )
    on conflict (user_id) do update
      set username = excluded.username,
          username_normalized = excluded.username_normalized,
          username_set_at = excluded.username_set_at;
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'reason', 'That username is already in use.');
  end;

  return jsonb_build_object(
    'ok', true,
    'username', v_validation.normalized,
    'normalized', v_validation.normalized
  );
end;
$$;

create or replace function public.claim_username(candidate text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'You must be signed in.');
  end if;

  return public._claim_username_for_user(v_uid, candidate);
end;
$$;

create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_candidate text;
  v_result jsonb;
begin
  v_candidate := nullif(trim(coalesce(new.raw_user_meta_data ->> 'username', '')), '');

  if v_candidate is null then
    insert into public.user_profiles (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
    return new;
  end if;

  v_result := public._claim_username_for_user(new.id, v_candidate);

  if coalesce((v_result ->> 'ok')::boolean, false) = false then
    raise exception using message = coalesce(v_result ->> 'reason', 'Username could not be reserved.');
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row
execute function public.handle_new_auth_user_profile();

insert into public.user_profiles (user_id)
select u.id
from auth.users u
on conflict (user_id) do nothing;

alter table public.user_profiles enable row level security;

drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own"
on public.user_profiles
for select
using (auth.uid() = user_id);

drop policy if exists "user_profiles_insert_own" on public.user_profiles;
create policy "user_profiles_insert_own"
on public.user_profiles
for insert
with check (auth.uid() = user_id);

drop policy if exists "user_profiles_update_own" on public.user_profiles;
create policy "user_profiles_update_own"
on public.user_profiles
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

revoke all on function public.check_username_availability(text) from public;
grant execute on function public.check_username_availability(text) to anon, authenticated;

revoke all on function public.claim_username(text) from public;
grant execute on function public.claim_username(text) to authenticated;

create table if not exists public.leaderboard_snapshots (
  metric text not null,
  rank integer not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  username text not null,
  score bigint not null,
  refreshed_at timestamp with time zone not null default timezone('utc'::text, now()),
  constraint leaderboard_metric_check check (metric in ('money_earned', 'fish_caught')),
  constraint leaderboard_rank_check check (rank >= 1 and rank <= 100),
  constraint leaderboard_score_check check (score >= 0),
  primary key (metric, rank),
  unique (metric, user_id)
);

create index if not exists leaderboard_metric_score_idx
  on public.leaderboard_snapshots (metric, score desc, rank asc);

create or replace function public.refresh_leaderboards()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refreshed_at timestamp with time zone := timezone('utc'::text, now());
begin
  delete from public.leaderboard_snapshots;

  with source as (
    select
      gs.user_id,
      up.username,
      up.username_normalized,
      greatest(
        0,
        floor(
          coalesce(
            case when coalesce(gs.save_data ->> 'totalCoinsEarned', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (gs.save_data ->> 'totalCoinsEarned')::numeric end,
            case when coalesce(gs.save_data ->> 'coins', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (gs.save_data ->> 'coins')::numeric end,
            0
          )
        )
      )::bigint as money_earned,
      greatest(
        0,
        floor(
          coalesce(
            case when coalesce(gs.save_data ->> 'totalCatches', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (gs.save_data ->> 'totalCatches')::numeric end,
            0
          )
        )
      )::bigint as fish_caught
    from public.game_saves gs
    inner join public.user_profiles up
      on up.user_id = gs.user_id
    where up.username_normalized is not null
  ),
  ranked_money as (
    select
      s.user_id,
      s.username,
      s.money_earned as score,
      row_number() over (
        order by s.money_earned desc, s.fish_caught desc, s.username_normalized asc
      ) as rank
    from source s
    where s.money_earned > 0
  ),
  ranked_fish as (
    select
      s.user_id,
      s.username,
      s.fish_caught as score,
      row_number() over (
        order by s.fish_caught desc, s.money_earned desc, s.username_normalized asc
      ) as rank
    from source s
    where s.fish_caught > 0
  )
  insert into public.leaderboard_snapshots (
    metric,
    rank,
    user_id,
    username,
    score,
    refreshed_at
  )
  select
    'money_earned',
    rm.rank,
    rm.user_id,
    rm.username,
    rm.score,
    v_refreshed_at
  from ranked_money rm
  where rm.rank <= 100
  union all
  select
    'fish_caught',
    rf.rank,
    rf.user_id,
    rf.username,
    rf.score,
    v_refreshed_at
  from ranked_fish rf
  where rf.rank <= 100;
end;
$$;

alter table public.leaderboard_snapshots enable row level security;

drop policy if exists "leaderboard_snapshots_select_all" on public.leaderboard_snapshots;
create policy "leaderboard_snapshots_select_all"
on public.leaderboard_snapshots
for select
using (true);

select public.refresh_leaderboards();

do $$
declare
  v_job_id bigint;
begin
  if to_regclass('cron.job') is null then
    begin
      create extension if not exists pg_cron with schema extensions;
    exception
      when others then
        raise notice 'pg_cron extension could not be created: %', sqlerrm;
    end;
  end if;

  if to_regclass('cron.job') is null then
    raise notice 'pg_cron is not available. Leaderboard auto-refresh schedule skipped.';
    return;
  end if;

  select j.jobid
  into v_job_id
  from cron.job j
  where j.jobname = 'refresh_leaderboards_every_10_minutes'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'refresh_leaderboards_every_10_minutes',
    '*/10 * * * *',
    'select public.refresh_leaderboards();'
  );
exception
  when others then
    raise notice 'Could not configure leaderboard cron schedule: %', sqlerrm;
end;
$$;

-- ============================================================================
-- SOURCE MIGRATION: 20260313_add_fish_catalog_and_leaderboard_bigint_safety.sql
-- ============================================================================

-- Adds a canonical fish catalog for newly playable biomes.
-- Also hardens leaderboard refresh conversions against bigint overflow.

create table if not exists public.fish_catalog (
  biome_key text not null,
  biome_name text not null,
  rarity text not null,
  fish_name text not null,
  min_weight_kg numeric(20, 3) not null,
  max_weight_kg numeric(20, 3) not null,
  min_price_coins numeric(24, 3) not null,
  max_price_coins numeric(24, 3) not null,
  preferred_bait text not null,
  notable_detail text not null,
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  constraint fish_catalog_weight_range_check check (min_weight_kg > 0 and max_weight_kg >= min_weight_kg),
  constraint fish_catalog_price_range_check check (min_price_coins >= 0 and max_price_coins >= min_price_coins),
  constraint fish_catalog_primary_key primary key (biome_key, rarity, fish_name)
);

create index if not exists fish_catalog_biome_rarity_idx
  on public.fish_catalog (biome_key, rarity);

alter table public.fish_catalog enable row level security;

drop policy if exists "fish_catalog_select_all" on public.fish_catalog;
create policy "fish_catalog_select_all"
on public.fish_catalog
for select
using (true);

grant select on table public.fish_catalog to anon, authenticated;

insert into public.fish_catalog (
  biome_key,
  biome_name,
  rarity,
  fish_name,
  min_weight_kg,
  max_weight_kg,
  min_price_coins,
  max_price_coins,
  preferred_bait,
  notable_detail
) values
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Aurelian Minnow', 0.15, 0.28, 6, 14.4, 'Metallic Larva', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Mercurial Catalyst Smelt', 0.16, 0.37, 6.88, 23.39, 'Mercury Midge', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Cinnabar Retort Chub', 0.18, 0.46, 7.76, 34.14, 'Sulfur Worm', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Verdigris Aurum Carp', 0.19, 0.56, 8.64, 46.66, 'Aurum Pellet', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Athanor Vitriol Gar', 0.2, 0.67, 9.52, 27.61, 'Alkahest Slurry', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Gilded Grouper', 0.22, 0.79, 10.4, 40.56, 'Glassfly', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Runebound Transmute Ray', 0.23, 0.44, 11.28, 55.27, 'Phoenix Scale', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Auric-Stoneborn Barracuda', 0.24, 0.55, 12.16, 29.18, 'Rune Grub', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Philosopher Alembic Marlin', 0.26, 0.67, 13.04, 44.34, 'Copper Nymph', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Chrysic Elixir Coelacanth', 0.27, 0.8, 13.92, 61.25, 'Silver Roe', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Brassbound Minnow', 0.28, 0.94, 14.8, 79.92, 'Catalyst Bait', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Silverflux Alloy Smelt', 0.3, 1.09, 15.68, 45.47, 'Retort Cricket', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Embered Calcine Chub', 0.31, 0.59, 16.56, 64.58, 'Quicksilver Shrimp', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Retort Sunmetal Carp', 0.33, 0.73, 17.44, 85.46, 'Cinder Beetle', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'common', 'Sigiled-Athanor Gar', 0.34, 0.88, 18.32, 43.97, 'Philosopher Crumb', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Mercurial Alembic Loach', 0.55, 1.25, 16.5, 47.85, 'Mercury Midge', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Cinnabar Elixir Shiner', 0.6, 1.57, 18.92, 73.79, 'Sulfur Worm', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Verdigris Sigil Bream', 0.65, 1.93, 21.34, 105, 'Aurum Pellet', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Athanor Alloy Pike', 0.7, 2.32, 23.76, 57.02, 'Alkahest Slurry', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Gilded Snapper', 0.75, 2.75, 26.18, 89.01, 'Glassfly', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Runebound Sunmetal Sturgeon', 0.8, 1.53, 28.6, 126, 'Phoenix Scale', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Auric-Athanor Arowana', 0.85, 1.92, 31.02, 168, 'Rune Grub', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Philosopher Crucible Salmon', 0.9, 2.35, 33.44, 96.98, 'Copper Nymph', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Chrysic Catalyst Shark', 0.95, 2.81, 35.86, 140, 'Silver Roe', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Brassbound Leviathan', 1, 3.31, 38.28, 188, 'Catalyst Bait', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Silverflux Aurum Loach', 1.05, 3.84, 40.7, 97.68, 'Retort Cricket', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Embered Vitriol Shiner', 1.09, 2.1, 43.12, 147, 'Quicksilver Shrimp', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Retort Quicksilver Bream', 1.14, 2.6, 45.54, 200, 'Cinder Beetle', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Sigiled-Transmute Pike', 1.19, 3.13, 47.96, 259, 'Philosopher Crumb', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'uncommon', 'Aurelian Snapper', 1.24, 3.69, 50.38, 146, 'Metallic Larva', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Cinnabar Catalyst Darter', 1.4, 3.7, 52.5, 179, 'Sulfur Worm', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Verdigris Retort Perch', 1.53, 4.56, 60.2, 265, 'Aurum Pellet', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Athanor Aurum Trout', 1.65, 5.52, 67.9, 367, 'Alkahest Slurry', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Gilded Catfish', 1.78, 6.56, 75.6, 219, 'Glassfly', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Runebound Quicksilver Eel', 1.9, 3.69, 83.3, 325, 'Phoenix Scale', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Auric-Transmute Manta', 2.03, 4.65, 91, 446, 'Rune Grub', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Philosopher Stoneborn Mackerel', 2.16, 5.69, 98.7, 237, 'Copper Nymph', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Chrysic Alembic Swordfish', 2.28, 6.82, 106, 362, 'Silver Roe', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Brassbound Tuna', 2.41, 8.04, 114, 502, 'Catalyst Bait', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Silverflux Sigil Guppy', 2.53, 9.35, 122, 658, 'Retort Cricket', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Embered Alloy Darter', 2.66, 5.16, 130, 376, 'Quicksilver Shrimp', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Retort Calcine Perch', 2.79, 6.38, 137, 535, 'Cinder Beetle', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Sigiled-Sunmetal Trout', 2.91, 7.69, 145, 710, 'Philosopher Crumb', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Aurelian Catfish', 3.04, 9.08, 153, 366, 'Metallic Larva', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'rare', 'Mercurial Crucible Eel', 3.16, 10.57, 160, 545, 'Mercury Midge', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Verdigris Elixir Chub', 3.8, 11.44, 158, 614, 'Aurum Pellet', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Athanor Sigil Carp', 4.14, 13.92, 181, 885, 'Alkahest Slurry', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Gilded Gar', 4.48, 16.64, 204, 489, 'Glassfly', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Runebound Calcine Grouper', 4.83, 9.46, 227, 771, 'Phoenix Scale', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Auric-Sunmetal Ray', 5.17, 11.94, 250, 1100, 'Rune Grub', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Philosopher Athanor Barracuda', 5.51, 14.66, 273, 1474, 'Copper Nymph', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Chrysic Crucible Marlin', 5.85, 17.61, 296, 859, 'Silver Roe', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Brassbound Coelacanth', 6.19, 20.81, 319, 1245, 'Catalyst Bait', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Silverflux Retort Minnow', 6.54, 24.25, 342, 1677, 'Retort Cricket', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Embered Aurum Smelt', 6.88, 13.48, 365, 877, 'Quicksilver Shrimp', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Retort Vitriol Chub', 7.22, 16.68, 389, 1321, 'Cinder Beetle', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Sigiled-Quicksilver Carp', 7.56, 20.11, 412, 1811, 'Philosopher Crumb', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Aurelian Gar', 7.9, 23.79, 435, 2347, 'Metallic Larva', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Mercurial Stoneborn Grouper', 8.25, 27.71, 458, 1328, 'Mercury Midge', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'epic', 'Cinnabar Alembic Ray', 8.59, 31.86, 481, 1876, 'Sulfur Worm', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Athanor Retort Bream', 9.5, 32.11, 465, 2046, 'Alkahest Slurry', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Gilded Pike', 10.36, 38.62, 533, 2879, 'Glassfly', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Runebound Vitriol Snapper', 11.21, 22.2, 601, 1744, 'Phoenix Scale', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Auric-Quicksilver Sturgeon', 12.07, 28.11, 670, 2611, 'Rune Grub', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Philosopher Transmute Arowana', 12.92, 34.63, 738, 3615, 'Copper Nymph', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Chrysic Stoneborn Salmon', 13.78, 41.74, 806, 1934, 'Silver Roe', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Brassbound Shark', 14.63, 49.45, 874, 2972, 'Catalyst Bait', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Silverflux Elixir Leviathan', 15.49, 57.76, 942, 4147, 'Retort Cricket', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Embered Sigil Loach', 16.34, 32.35, 1011, 5457, 'Quicksilver Shrimp', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Retort Alloy Shiner', 17.2, 40.06, 1079, 3129, 'Cinder Beetle', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Sigiled-Calcine Bream', 18.05, 48.37, 1147, 4473, 'Philosopher Crumb', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Aurelian Pike', 18.91, 57.28, 1215, 5954, 'Metallic Larva', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Mercurial Athanor Snapper', 19.76, 66.79, 1283, 3080, 'Mercury Midge', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Cinnabar Crucible Sturgeon', 20.62, 76.89, 1352, 4595, 'Sulfur Worm', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'legendary', 'Verdigris Catalyst Arowana', 21.47, 42.51, 1420, 6247, 'Aurum Pellet', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Gilded Trout', 20, 75, 1313, 6431, 'Glassfly', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Runebound Alloy Catfish', 21.8, 43.6, 1505, 3612, 'Phoenix Scale', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Auric-Calcine Eel', 23.6, 55.46, 1698, 5772, 'Rune Grub', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Philosopher Sunmetal Manta', 25.4, 68.58, 1890, 8316, 'Copper Nymph', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Chrysic Athanor Mackerel', 27.2, 82.96, 2083, 11246, 'Silver Roe', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Brassbound Swordfish', 29, 98.6, 2275, 6598, 'Catalyst Bait', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Silverflux Catalyst Tuna', 30.8, 116, 2468, 9623, 'Retort Cricket', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Embered Retort Guppy', 32.6, 65.2, 2660, 13034, 'Quicksilver Shrimp', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Retort Aurum Darter', 34.4, 80.84, 2853, 6846, 'Cinder Beetle', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Sigiled-Vitriol Perch', 36.2, 97.74, 3045, 10353, 'Philosopher Crumb', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Aurelian Trout', 38, 116, 3238, 14245, 'Metallic Larva', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Mercurial Transmute Catfish', 39.8, 135, 3430, 18522, 'Mercury Midge', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Cinnabar Stoneborn Eel', 41.6, 156, 3623, 10505, 'Sulfur Worm', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Verdigris Alembic Manta', 43.4, 86.8, 3815, 14878, 'Aurum Pellet', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'liminal', 'Athanor Elixir Mackerel', 45.2, 106, 4008, 19637, 'Alkahest Slurry', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Runebound Aurum Gar', 43, 86.86, 3675, 19845, 'Phoenix Scale', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Auric-Vitriol Grouper', 46.87, 111, 4214, 12221, 'Rune Grub', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Philosopher Quicksilver Ray', 50.74, 138, 4753, 18537, 'Copper Nymph', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Chrysic Transmute Barracuda', 54.61, 168, 5292, 25931, 'Silver Roe', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Brassbound Marlin', 58.48, 200, 5831, 13994, 'Catalyst Bait', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Silverflux Alembic Coelacanth', 62.35, 235, 6370, 21658, 'Retort Cricket', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Embered Elixir Minnow', 66.22, 134, 6909, 30400, 'Quicksilver Shrimp', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Retort Sigil Smelt', 70.09, 166, 7448, 40219, 'Cinder Beetle', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Sigiled-Alloy Chub', 73.96, 201, 7987, 23162, 'Philosopher Crumb', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Aurelian Carp', 77.83, 239, 8526, 33251, 'Metallic Larva', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Mercurial Sunmetal Gar', 81.7, 279, 9065, 44419, 'Mercury Midge', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Cinnabar Athanor Grouper', 85.57, 323, 9604, 23050, 'Sulfur Worm', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Verdigris Crucible Ray', 89.44, 181, 10143, 34486, 'Aurum Pellet', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Athanor Catalyst Barracuda', 93.31, 221, 10682, 47001, 'Alkahest Slurry', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'mythic', 'Gilded Marlin', 97.18, 264, 11221, 60593, 'Glassfly', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Auric-Alloy Snapper', 90, 215, 10350, 24840, 'Rune Grub', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Philosopher Calcine Sturgeon', 98.1, 269, 11868, 40351, 'Copper Nymph', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Chrysic Sunmetal Arowana', 106, 328, 13386, 58898, 'Silver Roe', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Brassbound Salmon', 114, 393, 14904, 80482, 'Catalyst Bait', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Silverflux Crucible Shark', 122, 464, 16422, 47624, 'Retort Cricket', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Embered Catalyst Leviathan', 131, 266, 17940, 69966, 'Quicksilver Shrimp', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Retort Loach', 139, 331, 19458, 95344, 'Cinder Beetle', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Sigiled-Aurum Shiner', 147, 402, 20976, 50342, 'Philosopher Crumb', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Aurelian Bream', 155, 478, 22494, 76480, 'Metallic Larva', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Mercurial Quicksilver Pike', 163, 560, 24012, 105653, 'Mercury Midge', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Cinnabar Transmute Snapper', 171, 648, 25530, 137862, 'Sulfur Worm', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Verdigris Stoneborn Sturgeon', 179, 365, 27048, 78439, 'Aurum Pellet', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Athanor Alembic Arowana', 187, 447, 28566, 111407, 'Alkahest Slurry', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Gilded Salmon', 195, 535, 30084, 147412, 'Glassfly', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'ascendant', 'Runebound-Sigil Shark', 203, 629, 31602, 75845, 'Phoenix Scale', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Philosopher Vitriol Eel', 190, 524, 29250, 84825, 'Copper Nymph', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Chrysic Quicksilver Manta', 207, 644, 33540, 130806, 'Silver Roe', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Brassbound Mackerel', 224, 776, 37830, 185367, 'Catalyst Bait', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Silverflux Stoneborn Swordfish', 241, 919, 42120, 101088, 'Retort Cricket', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Embered Alembic Tuna', 258, 532, 46410, 157794, 'Quicksilver Shrimp', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Retort Elixir Guppy', 276, 664, 50700, 223080, 'Cinder Beetle', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Sigiled-Sigil Darter', 293, 808, 54990, 296946, 'Philosopher Crumb', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Aurelian Perch', 310, 963, 59280, 171912, 'Metallic Larva', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Mercurial Calcine Trout', 327, 1131, 63570, 247923, 'Mercury Midge', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Cinnabar Sunmetal Catfish', 344, 1310, 67860, 332514, 'Sulfur Worm', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Verdigris Athanor Eel', 361, 744, 72150, 173160, 'Aurum Pellet', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Athanor Crucible Manta', 378, 911, 76440, 259896, 'Alkahest Slurry', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Gilded Mackerel', 395, 1091, 80730, 355212, 'Glassfly', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Runebound-Retort Swordfish', 412, 1282, 85020, 459108, 'Phoenix Scale', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'celestial', 'Auric Aurum Tuna', 429, 1486, 89310, 258999, 'Rune Grub', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Chrysic Calcine Ray', 400, 1252, 82500, 280500, 'Silver Roe', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Brassbound Barracuda', 436, 1517, 94600, 416240, 'Catalyst Bait', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Silverflux Athanor Marlin', 472, 1808, 106700, 576180, 'Retort Cricket', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Embered Crucible Coelacanth', 508, 1057, 118800, 344520, 'Quicksilver Shrimp', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Retort Catalyst Minnow', 544, 1322, 130900, 510510, 'Cinder Beetle', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Sigiled-Retort Smelt', 580, 1612, 143000, 700700, 'Philosopher Crumb', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Aurelian Chub', 616, 1928, 155100, 372240, 'Metallic Larva', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Mercurial Vitriol Carp', 652, 2269, 167200, 568480, 'Mercury Midge', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Cinnabar Quicksilver Gar', 688, 2635, 179300, 788920, 'Sulfur Worm', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Verdigris Transmute Grouper', 724, 1506, 191400, 1033560, 'Aurum Pellet', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Athanor Stoneborn Ray', 760, 1847, 203500, 590150, 'Alkahest Slurry', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Gilded Barracuda', 796, 2213, 215600, 840840, 'Glassfly', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Runebound-Elixir Marlin', 832, 2604, 227700, 1115730, 'Phoenix Scale', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Auric Sigil Coelacanth', 868, 3021, 239800, 575520, 'Rune Grub', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'eldritch', 'Philosopher Alloy Minnow', 904, 3462, 251900, 856460, 'Copper Nymph', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Brassbound Arowana', 850, 2975, 232500, 906750, 'Catalyst Bait', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Silverflux Transmute Salmon', 927, 3567, 266600, 1306340, 'Retort Cricket', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Embered Stoneborn Shark', 1003, 2106, 300700, 721680, 'Quicksilver Shrimp', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Retort Alembic Leviathan', 1080, 2645, 334800, 1138320, 'Cinder Beetle', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Sigiled-Elixir Loach', 1156, 3237, 368900, 1623160, 'Philosopher Crumb', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Aurelian Shiner', 1233, 3882, 403000, 2176200, 'Metallic Larva', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Mercurial Alloy Bream', 1309, 4582, 437100, 1267590, 'Mercury Midge', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Cinnabar Calcine Pike', 1386, 5334, 471200, 1837680, 'Sulfur Worm', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Verdigris Sunmetal Snapper', 1462, 3070, 505300, 2475970, 'Aurum Pellet', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Athanor Sturgeon', 1539, 3769, 539400, 1294560, 'Alkahest Slurry', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Gilded Arowana', 1615, 4522, 573500, 1949900, 'Glassfly', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Runebound-Catalyst Salmon', 1692, 5328, 607600, 2673440, 'Phoenix Scale', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Auric Retort Shark', 1768, 6188, 641700, 3465180, 'Rune Grub', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Philosopher Aurum Leviathan', 1845, 7101, 675800, 1959820, 'Copper Nymph', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'eternal', 'Chrysic Vitriol Loach', 1921, 4034, 709900, 2768610, 'Silver Roe', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Silverflux Sunmetal Mackerel', 1800, 6966, 660000, 2904000, 'Retort Cricket', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Embered Athanor Swordfish', 1962, 4159, 756800, 4086720, 'Quicksilver Shrimp', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Retort Crucible Tuna', 2124, 5246, 853600, 2475440, 'Cinder Beetle', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Sigiled-Catalyst Guppy', 2286, 6447, 950400, 3706560, 'Philosopher Crumb', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Aurelian Darter', 2448, 7760, 1047200, 5131280, 'Metallic Larva', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Mercurial Aurum Perch', 2610, 9187, 1144000, 2745600, 'Mercury Midge', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Cinnabar Vitriol Trout', 2772, 10728, 1240800, 4218720, 'Sulfur Worm', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Verdigris Quicksilver Catfish', 2934, 6220, 1337600, 5885440, 'Aurum Pellet', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Athanor Transmute Eel', 3096, 7647, 1434400, 7745760, 'Alkahest Slurry', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Gilded Manta', 3258, 9188, 1531200, 4440480, 'Glassfly', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Runebound-Alembic Mackerel', 3420, 10841, 1628000, 6349200, 'Phoenix Scale', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Auric Elixir Swordfish', 3582, 12609, 1724800, 8451520, 'Rune Grub', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Philosopher Sigil Tuna', 3744, 14489, 1821600, 4371840, 'Copper Nymph', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Chrysic Alloy Guppy', 3906, 8281, 1918400, 6522560, 'Silver Roe', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'divine', 'Brassbound Darter', 4068, 10048, 2015200, 8866880, 'Catalyst Bait', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Embered Transmute Marlin', 3900, 8346, 1875000, 9187500, 'Quicksilver Shrimp', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Retort Stoneborn Coelacanth', 4251, 10585, 2150000, 5160000, 'Cinder Beetle', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Sigiled-Alembic Minnow', 4602, 13070, 2425000, 8245000, 'Philosopher Crumb', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Aurelian Smelt', 4953, 15800, 2700000, 11880000, 'Metallic Larva', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Mercurial Sigil Chub', 5304, 18776, 2975000, 16065000, 'Mercury Midge', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Cinnabar Alloy Carp', 5655, 21998, 3250000, 9425000, 'Sulfur Worm', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Verdigris Calcine Gar', 6006, 12853, 3525000, 13747500, 'Aurum Pellet', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Athanor Sunmetal Grouper', 6357, 15829, 3800000, 18620000, 'Alkahest Slurry', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Gilded Ray', 6708, 19051, 4075000, 9780000, 'Glassfly', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Runebound-Crucible Barracuda', 7059, 22518, 4350000, 14790000, 'Phoenix Scale', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Auric Catalyst Marlin', 7410, 26231, 4625000, 20350000, 'Rune Grub', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Philosopher Retort Coelacanth', 7761, 30190, 4900000, 26460000, 'Copper Nymph', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Chrysic Aurum Minnow', 8112, 17360, 5175000, 15007500, 'Silver Roe', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Brassbound Smelt', 8463, 21073, 5450000, 21255000, 'Catalyst Bait', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'cosmic', 'Silverflux Quicksilver Chub', 8814, 25032, 5725000, 28052500, 'Retort Cricket', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Retort Athanor Shark', 8400, 21084, 5325000, 28755000, 'Cinder Beetle', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Sigiled-Crucible Leviathan', 9156, 26186, 6106000, 17707400, 'Philosopher Crumb', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Aurelian Loach', 9912, 31818, 6887000, 26859300, 'Metallic Larva', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Mercurial Retort Shiner', 10668, 37978, 7668000, 37573200, 'Mercury Midge', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Cinnabar Aurum Bream', 11424, 44668, 8449000, 20277600, 'Sulfur Worm', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Verdigris Vitriol Pike', 12180, 26309, 9230000, 31382000, 'Aurum Pellet', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Athanor Quicksilver Snapper', 12936, 32469, 10011000, 44048400, 'Alkahest Slurry', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Gilded Sturgeon', 13692, 39159, 10792000, 58276800, 'Glassfly', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Runebound-Stoneborn Arowana', 14448, 46378, 11573000, 33561700, 'Phoenix Scale', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Auric Alembic Salmon', 15204, 54126, 12354000, 48180600, 'Rune Grub', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Philosopher Elixir Shark', 15960, 62404, 13135000, 64361500, 'Copper Nymph', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Chrysic Sigil Leviathan', 16716, 36107, 13916000, 33398400, 'Silver Roe', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Brassbound Loach', 17472, 43855, 14697000, 49969800, 'Catalyst Bait', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Silverflux Calcine Shiner', 18228, 52132, 15478000, 68103200, 'Retort Cricket', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'primordial', 'Embered Sunmetal Bream', 18984, 60939, 16259000, 87798600, 'Quicksilver Shrimp', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Sigiled-Stoneborn Tuna', 18000, 51840, 15000000, 36000000, 'Philosopher Crumb', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Aurelian Guppy', 19620, 63373, 17200000, 58480000, 'Metallic Larva', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Mercurial Elixir Darter', 21240, 76039, 19400000, 85360000, 'Mercury Midge', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Cinnabar Sigil Perch', 22860, 89840, 21600000, 116640000, 'Sulfur Worm', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Verdigris Alloy Trout', 24480, 53366, 23800000, 69020000, 'Aurum Pellet', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Athanor Calcine Catfish', 26100, 66033, 26000000, 101400000, 'Alkahest Slurry', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Gilded Eel', 27720, 79834, 28200000, 138180000, 'Glassfly', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Runebound-Athanor Manta', 29340, 94768, 30400000, 72960000, 'Phoenix Scale', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Auric Crucible Mackerel', 30960, 110837, 32600000, 110840000, 'Rune Grub', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Philosopher Catalyst Swordfish', 32580, 128039, 34800000, 153120000, 'Copper Nymph', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Chrysic Retort Tuna', 34200, 74556, 37000000, 199800000, 'Silver Roe', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Brassbound Guppy', 35820, 90625, 39200000, 113680000, 'Catalyst Bait', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Silverflux Vitriol Darter', 37440, 107827, 41400000, 161460000, 'Retort Cricket', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Embered Quicksilver Perch', 39060, 126164, 43600000, 213640000, 'Quicksilver Shrimp', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'transcendent', 'Retort-Transmute Trout', 40680, 145634, 45800000, 109920000, 'Cinder Beetle', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Aurelian Minnow', 39000, 126750, 42000000, 121800000, 'Metallic Larva', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Mercurial Catalyst Smelt', 42510, 153036, 48160000, 187824000, 'Mercury Midge', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Cinnabar Retort Chub', 46020, 181779, 54320000, 266168000, 'Sulfur Worm', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Verdigris Aurum Carp', 49530, 108966, 60480000, 145152000, 'Aurum Pellet', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Athanor Vitriol Gar', 53040, 135252, 66640000, 226576000, 'Alkahest Slurry', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Gilded Grouper', 56550, 163995, 72800000, 320320000, 'Glassfly', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Runebound-Transmute Ray', 60060, 195195, 78960000, 426384000, 'Phoenix Scale', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Auric Stoneborn Barracuda', 63570, 228852, 85120000, 246848000, 'Rune Grub', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Philosopher Alembic Marlin', 67080, 264966, 91280000, 355992000, 'Copper Nymph', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Chrysic Elixir Coelacanth', 70590, 155298, 97440000, 477456000, 'Silver Roe', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Brassbound Minnow', 74100, 188955, 103600000, 248640000, 'Catalyst Bait', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Silverflux Alloy Smelt', 77610, 225069, 109760000, 373184000, 'Retort Cricket', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Embered Calcine Chub', 81120, 263640, 115920000, 510048000, 'Quicksilver Shrimp', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Retort-Sunmetal Carp', 84630, 304668, 122080000, 659232000, 'Cinder Beetle', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'apotheosis', 'Sigiled Athanor Gar', 88140, 348153, 128240000, 371896000, 'Philosopher Crumb', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Mercurial Alembic Loach', 84000, 304080, 120000000, 408000000, 'Mercury Midge', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Cinnabar Elixir Shiner', 91560, 363493, 137600000, 605440000, 'Sulfur Worm', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Verdigris Sigil Bream', 99120, 220046, 155200000, 838080000, 'Aurum Pellet', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Athanor Alloy Pike', 106680, 274168, 172800000, 501120000, 'Alkahest Slurry', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Gilded Snapper', 114240, 333581, 190400000, 742560000, 'Glassfly', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Runebound-Sunmetal Sturgeon', 121800, 398286, 208000000, 1019200000, 'Phoenix Scale', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Auric Athanor Arowana', 129360, 468283, 225600000, 541440000, 'Rune Grub', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Philosopher Crucible Salmon', 136920, 543572, 243200000, 826880000, 'Copper Nymph', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Chrysic Catalyst Shark', 144480, 320746, 260800000, 1147520000, 'Silver Roe', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Brassbound Leviathan', 152040, 390743, 278400000, 1503360000, 'Catalyst Bait', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Silverflux Aurum Loach', 159600, 466032, 296000000, 858400000, 'Retort Cricket', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Embered Vitriol Shiner', 167160, 546613, 313600000, 1223040000, 'Quicksilver Shrimp', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Retort-Quicksilver Bream', 174720, 632486, 331200000, 1622880000, 'Cinder Beetle', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Sigiled Transmute Pike', 182280, 723652, 348800000, 837120000, 'Philosopher Crumb', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'absolute', 'Aurelian Snapper', 189840, 421445, 366400000, 1245760000, 'Metallic Larva', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Cinnabar Catalyst Darter', 180000, 718200, 337500000, 1316250000, 'Sulfur Worm', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Verdigris Retort Perch', 196200, 439488, 387000000, 1896300000, 'Aurum Pellet', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Athanor Aurum Trout', 212400, 550116, 436500000, 1047600000, 'Alkahest Slurry', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Gilded Catfish', 228600, 672084, 486000000, 1652400000, 'Glassfly', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Runebound-Quicksilver Eel', 244800, 805392, 535500000, 2356200000, 'Phoenix Scale', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Auric Transmute Manta', 261000, 950040, 585000000, 3159000000, 'Rune Grub', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Philosopher Stoneborn Mackerel', 277200, 1106028, 634500000, 1840050000, 'Copper Nymph', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Chrysic Alembic Swordfish', 293400, 657216, 684000000, 2667600000, 'Silver Roe', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Brassbound Tuna', 309600, 801864, 733500000, 3594150000, 'Catalyst Bait', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Silverflux Sigil Guppy', 325800, 957852, 783000000, 1879200000, 'Retort Cricket', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Embered Alloy Darter', 342000, 1125180, 832500000, 2830500000, 'Quicksilver Shrimp', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Retort-Calcine Perch', 358200, 1303848, 882000000, 3880800000, 'Cinder Beetle', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Sigiled Sunmetal Trout', 374400, 1493856, 931500000, 5030100000, 'Philosopher Crumb', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Aurelian Catfish', 390600, 874944, 981000000, 2844900000, 'Metallic Larva', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'singularity', 'Mercurial Crucible Eel', 406800, 1053612, 1030500000, 4018950000, 'Mercury Midge', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Verdigris Elixir Chub', 390000, 881400, 975000000, 4290000000, 'Aurum Pellet', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Athanor Sigil Carp', 425100, 1109511, 1118000000, 6037200000, 'Alkahest Slurry', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Gilded Gar', 460200, 1362192, 1261000000, 3656900000, 'Glassfly', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Runebound-Calcine Grouper', 495300, 1639443, 1404000000, 5475600000, 'Phoenix Scale', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Auric Sunmetal Ray', 530400, 1941264, 1547000000, 7580300000, 'Rune Grub', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Philosopher Athanor Barracuda', 565500, 2267655, 1690000000, 4056000000, 'Copper Nymph', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Chrysic Crucible Marlin', 600600, 1357356, 1833000000, 6232200000, 'Silver Roe', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Brassbound Coelacanth', 635700, 1659177, 1976000000, 8694400000, 'Catalyst Bait', 'Leaves glittering catalyst trails in the wake.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Silverflux Retort Minnow', 670800, 1985568, 2119000000, 11442600000, 'Retort Cricket', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Embered Aurum Smelt', 705900, 2336529, 2262000000, 6559800000, 'Quicksilver Shrimp', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Retort-Vitriol Chub', 741000, 2712060, 2405000000, 9379500000, 'Cinder Beetle', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Sigiled Quicksilver Carp', 776100, 3112161, 2548000000, 12485200000, 'Philosopher Crumb', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Aurelian Gar', 811200, 1833312, 2691000000, 6458400000, 'Metallic Larva', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Mercurial Stoneborn Grouper', 846300, 2208843, 2834000000, 9635600000, 'Mercury Midge', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'paradox', 'Cinnabar Alembic Ray', 881400, 2608944, 2977000000, 13098800000, 'Sulfur Worm', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Athanor Retort Bream', 840000, 2209200, 2775000000, 13597500000, 'Alkahest Slurry', 'Changes hue with local pH.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Gilded Pike', 915600, 2728488, 3182000000, 7636800000, 'Glassfly', 'Often schools around runic stones.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Runebound-Vitriol Snapper', 991200, 3300696, 3589000000, 12202600000, 'Phoenix Scale', 'Tailbeat sparks tiny alchemical flares.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Auric Quicksilver Sturgeon', 1066800, 3925824, 3996000000, 17582400000, 'Rune Grub', 'Bites hardest during furnace storms.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Philosopher Transmute Arowana', 1142400, 4603872, 4403000000, 23776200000, 'Copper Nymph', 'Molts into brighter alloys each season.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Chrysic Stoneborn Salmon', 1218000, 2777040, 4810000000, 13949000000, 'Silver Roe', 'Known to leap when transmutation bells ring.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Brassbound Shark', 1293600, 3402168, 5217000000, 20346300000, 'Catalyst Bait', 'Can temporarily harden scales into bronze plates.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Silverflux Elixir Leviathan', 1369200, 4080216, 5624000000, 27557600000, 'Retort Cricket', 'Feeds near bubbling retort vents.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Embered Sigil Loach', 1444800, 4811184, 6031000000, 14474400000, 'Quicksilver Shrimp', 'Absorbs trace metals from sediment.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Retort-Alloy Shiner', 1520400, 5595072, 6438000000, 21889200000, 'Cinder Beetle', 'Resists corrosive currents.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Sigiled Calcine Bream', 1596000, 6431880, 6845000000, 30118000000, 'Philosopher Crumb', 'Prefers dawn tides rich in mineral foam.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Aurelian Pike', 1671600, 3811248, 7252000000, 39160800000, 'Metallic Larva', 'Stores heat in dense marrow-like tissue.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Mercurial Athanor Snapper', 1747200, 4595136, 7659000000, 22211100000, 'Mercury Midge', 'Smells faintly of clove and sulfur.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Cinnabar Crucible Sturgeon', 1822800, 5431944, 8066000000, 31457400000, 'Sulfur Worm', 'Sheds a metallic sheen when stressed.'),
  ('transmutation_tide', 'Transmutation Tide', 'null', 'Verdigris Catalyst Arowana', 1898400, 6321672, 8473000000, 41517700000, 'Aurum Pellet', 'Leaves glittering catalyst trails in the wake.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Vermilion Minnow', 0.16, 0.35, 6.64, 19.26, 'Linen Larva', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Cerulean Canvas Smelt', 0.17, 0.44, 7.52, 29.33, 'Acrylic Worm', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Ochre Varnish Chub', 0.18, 0.54, 8.4, 41.16, 'Ink Midge', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Cobalt Fresco Carp', 0.2, 0.65, 9.28, 22.27, 'Turpentine Gnat', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Sienna Tint Gar', 0.21, 0.77, 10.16, 34.54, 'Palette Grub', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Ultramarine Grouper', 0.22, 0.43, 11.04, 48.58, 'Gesso Shrimp', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Viridian Glaze Ray', 0.24, 0.54, 11.92, 64.37, 'Varnish Beetle', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Magenta-Oilwash Barracuda', 0.25, 0.66, 12.8, 37.12, 'Canvas Crumb', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Indigo Palette Marlin', 0.27, 0.78, 13.68, 53.35, 'Gouache Fry', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Amberwash Pigment Coelacanth', 0.28, 0.92, 14.56, 71.34, 'Charcoal Nymph', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Charcoal Minnow', 0.29, 1.07, 15.44, 37.06, 'Oildrop Worm', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Pastel Easel Smelt', 0.31, 0.58, 16.32, 55.49, 'Pastel Roe', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Prismatic Huecrest Chub', 0.32, 0.72, 17.2, 75.68, 'Primer Fly', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Lacquer Inkline Carp', 0.33, 0.87, 18.08, 97.63, 'Pigment Pearl', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'common', 'Gouache-Watercolor Gar', 0.35, 1.02, 18.96, 54.98, 'Brush Bristle Worm', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Cerulean Palette Loach', 0.58, 1.51, 18.26, 62.08, 'Acrylic Worm', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Ochre Pigment Shiner', 0.63, 1.86, 20.68, 90.99, 'Ink Midge', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Cobalt Stroke Bream', 0.68, 2.25, 23.1, 125, 'Turpentine Gnat', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Sienna Easel Pike', 0.73, 2.66, 25.52, 74.01, 'Palette Grub', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Ultramarine Snapper', 0.78, 1.49, 27.94, 109, 'Gesso Shrimp', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Viridian Inkline Sturgeon', 0.83, 1.87, 30.36, 149, 'Varnish Beetle', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Magenta-Watercolor Arowana', 0.87, 2.29, 32.78, 78.67, 'Canvas Crumb', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Indigo Brushfin Salmon', 0.92, 2.74, 35.2, 120, 'Gouache Fry', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Amberwash Canvas Shark', 0.97, 3.23, 37.62, 166, 'Charcoal Nymph', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Charcoal Leviathan', 1.02, 3.75, 40.04, 216, 'Oildrop Worm', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Pastel Fresco Loach', 1.07, 2.06, 42.46, 123, 'Pastel Roe', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Prismatic Tint Shiner', 1.12, 2.55, 44.88, 175, 'Primer Fly', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Lacquer Primer Bream', 1.17, 3.07, 47.3, 232, 'Pigment Pearl', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Gouache-Glaze Pike', 1.22, 3.63, 49.72, 119, 'Brush Bristle Worm', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'uncommon', 'Vermilion Snapper', 1.27, 4.22, 52.14, 177, 'Linen Larva', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Ochre Canvas Darter', 1.47, 4.4, 58.1, 227, 'Ink Midge', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Cobalt Varnish Perch', 1.6, 5.33, 65.8, 322, 'Turpentine Gnat', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Sienna Fresco Trout', 1.72, 6.35, 73.5, 176, 'Palette Grub', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Ultramarine Catfish', 1.85, 3.59, 81.2, 276, 'Gesso Shrimp', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Viridian Primer Eel', 1.97, 4.52, 88.9, 391, 'Varnish Beetle', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Magenta-Glaze Manta', 2.1, 5.54, 96.6, 522, 'Canvas Crumb', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Indigo Oilwash Mackerel', 2.23, 6.66, 104, 302, 'Gouache Fry', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Amberwash Palette Swordfish', 2.35, 7.86, 112, 437, 'Charcoal Nymph', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Charcoal Tuna', 2.48, 9.14, 120, 587, 'Oildrop Worm', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Pastel Stroke Guppy', 2.6, 5.05, 127, 306, 'Pastel Roe', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Prismatic Easel Darter', 2.73, 6.25, 135, 459, 'Primer Fly', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Lacquer Huecrest Perch', 2.86, 7.54, 143, 628, 'Pigment Pearl', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Gouache-Inkline Trout', 2.98, 8.92, 151, 813, 'Brush Bristle Worm', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Vermilion Catfish', 3.11, 10.38, 158, 459, 'Linen Larva', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'rare', 'Cerulean Brushfin Eel', 3.23, 11.93, 166, 647, 'Acrylic Worm', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Cobalt Pigment Chub', 3.99, 13.41, 174, 767, 'Turpentine Gnat', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Sienna Stroke Carp', 4.33, 16.07, 197, 1066, 'Palette Grub', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Ultramarine Gar', 4.67, 9.16, 221, 639, 'Gesso Shrimp', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Viridian Huecrest Grouper', 5.02, 11.59, 244, 950, 'Varnish Beetle', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Magenta-Inkline Ray', 5.36, 14.25, 267, 1307, 'Canvas Crumb', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Indigo Watercolor Barracuda', 5.7, 17.16, 290, 696, 'Gouache Fry', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Amberwash Brushfin Marlin', 6.04, 20.3, 313, 1064, 'Charcoal Nymph', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Charcoal Coelacanth', 6.38, 23.68, 336, 1478, 'Oildrop Worm', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Pastel Varnish Minnow', 6.73, 13.18, 359, 1939, 'Pastel Roe', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Prismatic Fresco Smelt', 7.07, 16.33, 382, 1108, 'Primer Fly', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Lacquer Tint Chub', 7.41, 19.71, 405, 1581, 'Pigment Pearl', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Gouache-Primer Carp', 7.75, 23.33, 428, 2099, 'Brush Bristle Worm', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Vermilion Gar', 8.09, 27.2, 452, 1084, 'Linen Larva', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Cerulean Oilwash Grouper', 8.44, 31.3, 475, 1614, 'Acrylic Worm', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'epic', 'Ochre Palette Ray', 8.78, 17.2, 498, 2190, 'Ink Midge', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Sienna Varnish Bream', 9.98, 37.21, 515, 2522, 'Palette Grub', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Ultramarine Pike', 10.83, 21.44, 583, 1399, 'Gesso Shrimp', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Viridian Tint Snapper', 11.69, 27.23, 651, 2213, 'Varnish Beetle', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Magenta-Primer Sturgeon', 12.54, 33.61, 719, 3164, 'Canvas Crumb', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Indigo Glaze Arowana', 13.4, 40.59, 787, 4252, 'Gouache Fry', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Amberwash Oilwash Salmon', 14.25, 48.17, 856, 2481, 'Charcoal Nymph', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Charcoal Shark', 15.11, 56.34, 924, 3603, 'Oildrop Worm', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Pastel Pigment Leviathan', 15.96, 31.6, 992, 4861, 'Pastel Roe', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Prismatic Stroke Loach', 16.82, 39.18, 1060, 2544, 'Primer Fly', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Lacquer Easel Shiner', 17.67, 47.36, 1128, 3837, 'Pigment Pearl', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Gouache-Huecrest Bream', 18.52, 56.13, 1197, 5265, 'Brush Bristle Worm', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Vermilion Pike', 19.38, 65.5, 1265, 6830, 'Linen Larva', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Cerulean Watercolor Snapper', 20.24, 75.48, 1333, 3866, 'Acrylic Worm', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Ochre Brushfin Sturgeon', 21.09, 41.76, 1401, 5465, 'Ink Midge', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'legendary', 'Cobalt Canvas Arowana', 21.94, 51.13, 1469, 7200, 'Turpentine Gnat', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Ultramarine Trout', 21, 42, 1453, 7844, 'Gesso Shrimp', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Viridian Easel Catfish', 22.8, 53.58, 1645, 4771, 'Varnish Beetle', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Magenta-Huecrest Eel', 24.6, 66.42, 1838, 7166, 'Canvas Crumb', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Indigo Inkline Manta', 26.4, 80.52, 2030, 9947, 'Gouache Fry', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Amberwash Watercolor Mackerel', 28.2, 95.88, 2223, 5334, 'Charcoal Nymph', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Charcoal Swordfish', 30, 113, 2415, 8211, 'Oildrop Worm', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Pastel Canvas Tuna', 31.8, 63.6, 2608, 11473, 'Pastel Roe', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Prismatic Varnish Guppy', 33.6, 78.96, 2800, 15120, 'Primer Fly', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Lacquer Fresco Darter', 35.4, 95.58, 2993, 8678, 'Pigment Pearl', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Gouache-Tint Perch', 37.2, 113, 3185, 12422, 'Brush Bristle Worm', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Vermilion Trout', 39, 133, 3378, 16550, 'Linen Larva', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Cerulean Glaze Catfish', 40.8, 153, 3570, 8568, 'Acrylic Worm', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Ochre Oilwash Eel', 42.6, 85.2, 3763, 12793, 'Ink Midge', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Cobalt Palette Manta', 44.4, 104, 3955, 17402, 'Turpentine Gnat', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'liminal', 'Sienna Pigment Mackerel', 46.2, 125, 4148, 22397, 'Palette Grub', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Viridian Fresco Gar', 45.15, 107, 4067, 9761, 'Varnish Beetle', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Magenta-Tint Grouper', 49.02, 133, 4606, 15660, 'Canvas Crumb', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Indigo Primer Ray', 52.89, 162, 5145, 22638, 'Gouache Fry', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Amberwash Glaze Barracuda', 56.76, 194, 5684, 30694, 'Charcoal Nymph', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Charcoal Marlin', 60.63, 229, 6223, 18047, 'Oildrop Worm', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Pastel Palette Coelacanth', 64.5, 130, 6762, 26372, 'Pastel Roe', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Prismatic Pigment Minnow', 68.37, 162, 7301, 35775, 'Primer Fly', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Lacquer Stroke Smelt', 72.24, 196, 7840, 18816, 'Pigment Pearl', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Gouache-Easel Chub', 76.11, 234, 8379, 28489, 'Brush Bristle Worm', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Vermilion Carp', 79.98, 274, 8918, 39239, 'Linen Larva', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Cerulean Inkline Gar', 83.85, 316, 9457, 51068, 'Acrylic Worm', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Ochre Watercolor Grouper', 87.72, 177, 9996, 28988, 'Ink Midge', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Cobalt Brushfin Ray', 91.59, 217, 10535, 41087, 'Turpentine Gnat', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Sienna Canvas Barracuda', 95.46, 260, 11074, 54263, 'Palette Grub', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'mythic', 'Ultramarine Marlin', 99.33, 305, 11613, 27871, 'Gesso Shrimp', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Magenta-Easel Snapper', 94.5, 259, 11454, 33217, 'Canvas Crumb', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Indigo Huecrest Sturgeon', 103, 317, 12972, 50591, 'Gouache Fry', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Amberwash Inkline Arowana', 111, 381, 14490, 71001, 'Charcoal Nymph', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Charcoal Salmon', 119, 450, 16008, 38419, 'Oildrop Worm', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Pastel Brushfin Shark', 127, 259, 17526, 59588, 'Pastel Roe', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Prismatic Canvas Leviathan', 135, 323, 19044, 83794, 'Primer Fly', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Lacquer Varnish Loach', 143, 392, 20562, 111035, 'Pigment Pearl', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Gouache-Fresco Shiner', 151, 467, 22080, 64032, 'Brush Bristle Worm', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Vermilion Bream', 159, 548, 23598, 92032, 'Linen Larva', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Cerulean Primer Pike', 167, 634, 25116, 123068, 'Acrylic Worm', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Ochre Glaze Snapper', 176, 358, 26634, 63922, 'Ink Midge', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Cobalt Oilwash Sturgeon', 184, 439, 28152, 95717, 'Turpentine Gnat', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Sienna Palette Arowana', 192, 525, 29670, 130548, 'Palette Grub', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Ultramarine Salmon', 200, 617, 31188, 168415, 'Gesso Shrimp', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'ascendant', 'Viridian-Stroke Shark', 208, 715, 32706, 94847, 'Varnish Beetle', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Indigo Tint Eel', 200, 620, 32370, 110058, 'Gouache Fry', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Amberwash Primer Manta', 217, 749, 36660, 161304, 'Charcoal Nymph', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Charcoal Mackerel', 234, 890, 40950, 221130, 'Oildrop Worm', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Pastel Oilwash Swordfish', 251, 517, 45240, 131196, 'Pastel Roe', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Prismatic Palette Tuna', 268, 646, 49530, 193167, 'Primer Fly', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Lacquer Pigment Guppy', 285, 787, 53820, 263718, 'Pigment Pearl', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Gouache-Stroke Darter', 302, 940, 58110, 139464, 'Brush Bristle Worm', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Vermilion Perch', 319, 1104, 62400, 212160, 'Linen Larva', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Cerulean Huecrest Trout', 336, 1281, 66690, 293436, 'Acrylic Worm', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Ochre Inkline Catfish', 353, 728, 70980, 383292, 'Ink Midge', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Cobalt Watercolor Eel', 371, 893, 75270, 218283, 'Turpentine Gnat', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Sienna Brushfin Manta', 388, 1070, 79560, 310284, 'Palette Grub', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Ultramarine Mackerel', 405, 1259, 83850, 410865, 'Gesso Shrimp', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Viridian-Varnish Swordfish', 422, 1459, 88140, 211536, 'Varnish Beetle', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'celestial', 'Magenta Fresco Tuna', 439, 1672, 92430, 314262, 'Canvas Crumb', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Amberwash Huecrest Ray', 420, 1462, 91300, 356070, 'Charcoal Nymph', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Charcoal Barracuda', 456, 1746, 103400, 506660, 'Oildrop Worm', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Pastel Watercolor Marlin', 492, 1023, 115500, 277200, 'Pastel Roe', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Prismatic Brushfin Coelacanth', 528, 1283, 127600, 433840, 'Primer Fly', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Lacquer Canvas Minnow', 564, 1568, 139700, 614680, 'Pigment Pearl', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Gouache-Varnish Smelt', 600, 1878, 151800, 819720, 'Brush Bristle Worm', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Vermilion Chub', 636, 2213, 163900, 475310, 'Linen Larva', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Cerulean Tint Carp', 672, 2574, 176000, 686400, 'Acrylic Worm', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Ochre Primer Gar', 708, 1473, 188100, 921690, 'Ink Midge', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Cobalt Glaze Grouper', 744, 1808, 200200, 480480, 'Turpentine Gnat', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Sienna Oilwash Ray', 780, 2168, 212300, 721820, 'Palette Grub', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Ultramarine Barracuda', 816, 2554, 224400, 987360, 'Gesso Shrimp', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Viridian-Pigment Marlin', 852, 2965, 236500, 1277100, 'Varnish Beetle', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Magenta Stroke Coelacanth', 888, 3401, 248600, 720940, 'Canvas Crumb', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eldritch', 'Indigo Easel Minnow', 924, 1922, 260700, 1016730, 'Gouache Fry', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Charcoal Arowana', 893, 3436, 257300, 1132120, 'Oildrop Worm', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Pastel Glaze Salmon', 969, 2035, 291400, 1573560, 'Pastel Roe', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Prismatic Oilwash Shark', 1046, 2561, 325500, 943950, 'Primer Fly', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Lacquer Palette Leviathan', 1122, 3142, 359600, 1402440, 'Pigment Pearl', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Gouache-Pigment Loach', 1199, 3775, 393700, 1929130, 'Brush Bristle Worm', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Vermilion Shiner', 1275, 4463, 427800, 1026720, 'Linen Larva', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Cerulean Easel Bream', 1352, 5203, 461900, 1570460, 'Acrylic Worm', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Ochre Huecrest Pike', 1428, 2999, 496000, 2182400, 'Ink Midge', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Cobalt Inkline Snapper', 1505, 3686, 530100, 2862540, 'Turpentine Gnat', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Sienna Watercolor Sturgeon', 1581, 4427, 564200, 1636180, 'Palette Grub', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Ultramarine Arowana', 1658, 5221, 598300, 2333370, 'Gesso Shrimp', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Viridian-Canvas Salmon', 1734, 6069, 632400, 3098760, 'Varnish Beetle', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Magenta Varnish Shark', 1811, 6970, 666500, 1599600, 'Canvas Crumb', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Indigo Fresco Leviathan', 1887, 3963, 700600, 2382040, 'Gouache Fry', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'eternal', 'Amberwash Tint Loach', 1963, 4811, 734700, 3232680, 'Charcoal Nymph', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Pastel Inkline Mackerel', 1890, 4007, 730400, 3578960, 'Pastel Roe', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Prismatic Watercolor Swordfish', 2052, 5068, 827200, 1985280, 'Primer Fly', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Lacquer Brushfin Tuna', 2214, 6243, 924000, 3141600, 'Pigment Pearl', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Gouache-Canvas Guppy', 2376, 7532, 1020800, 4491520, 'Brush Bristle Worm', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Vermilion Darter', 2538, 8934, 1117600, 6035040, 'Linen Larva', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Cerulean Fresco Perch', 2700, 10449, 1214400, 3521760, 'Acrylic Worm', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Ochre Tint Trout', 2862, 6067, 1311200, 5113680, 'Ink Midge', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Cobalt Primer Catfish', 3024, 7469, 1408000, 6899200, 'Turpentine Gnat', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Sienna Glaze Eel', 3186, 8985, 1504800, 3611520, 'Palette Grub', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Ultramarine Manta', 3348, 10613, 1601600, 5445440, 'Gesso Shrimp', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Viridian-Palette Mackerel', 3510, 12355, 1698400, 7472960, 'Varnish Beetle', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Magenta Pigment Swordfish', 3672, 14211, 1795200, 9694080, 'Canvas Crumb', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Indigo Stroke Tuna', 3834, 8128, 1892000, 5486800, 'Gouache Fry', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Amberwash Easel Guppy', 3996, 9870, 1988800, 7756320, 'Charcoal Nymph', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'divine', 'Charcoal Darter', 4158, 11726, 2085600, 10219440, 'Oildrop Worm', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Prismatic Glaze Marlin', 4095, 10197, 2075000, 11205000, 'Primer Fly', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Lacquer Oilwash Coelacanth', 4446, 12627, 2350000, 6815000, 'Pigment Pearl', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Gouache-Palette Minnow', 4797, 15302, 2625000, 10237500, 'Brush Bristle Worm', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Vermilion Smelt', 5148, 18224, 2900000, 14210000, 'Linen Larva', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Cerulean Stroke Chub', 5499, 21391, 3175000, 7620000, 'Acrylic Worm', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Ochre Easel Carp', 5850, 12519, 3450000, 11730000, 'Ink Midge', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Cobalt Huecrest Gar', 6201, 15440, 3725000, 16390000, 'Turpentine Gnat', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Sienna Inkline Grouper', 6552, 18608, 4000000, 21600000, 'Palette Grub', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Ultramarine Ray', 6903, 22021, 4275000, 12397500, 'Gesso Shrimp', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Viridian-Brushfin Barracuda', 7254, 25679, 4550000, 17745000, 'Varnish Beetle', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Magenta Canvas Marlin', 7605, 29583, 4825000, 23642500, 'Canvas Crumb', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Indigo Varnish Coelacanth', 7956, 17026, 5100000, 12240000, 'Gouache Fry', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Amberwash Fresco Minnow', 8307, 20684, 5375000, 18275000, 'Charcoal Nymph', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Charcoal Smelt', 8658, 24589, 5650000, 24860000, 'Oildrop Worm', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'cosmic', 'Pastel Primer Chub', 9009, 28739, 5925000, 31995000, 'Pastel Roe', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Lacquer Watercolor Shark', 8820, 25225, 5893000, 14143200, 'Pigment Pearl', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Gouache-Brushfin Leviathan', 9576, 30739, 6674000, 22691600, 'Brush Bristle Worm', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Vermilion Loach', 10332, 36782, 7455000, 32802000, 'Linen Larva', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Cerulean Varnish Shiner', 11088, 43354, 8236000, 44474400, 'Acrylic Worm', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Ochre Fresco Bream', 11844, 25583, 9017000, 26149300, 'Ink Midge', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Cobalt Tint Pike', 12600, 31626, 9798000, 38212200, 'Turpentine Gnat', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Sienna Primer Snapper', 13356, 38198, 10579000, 51837100, 'Palette Grub', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Ultramarine Sturgeon', 14112, 45300, 11360000, 27264000, 'Gesso Shrimp', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Viridian-Oilwash Arowana', 14868, 52930, 12141000, 41279400, 'Varnish Beetle', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Magenta Palette Salmon', 15624, 61090, 12922000, 56856800, 'Canvas Crumb', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Indigo Pigment Shark', 16380, 35381, 13703000, 73996200, 'Gouache Fry', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Amberwash Stroke Leviathan', 17136, 43011, 14484000, 42003600, 'Charcoal Nymph', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Charcoal Loach', 17892, 51171, 15265000, 59533500, 'Oildrop Worm', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Pastel Huecrest Shiner', 18648, 59860, 16046000, 78625400, 'Pastel Roe', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'primordial', 'Prismatic Inkline Bream', 19404, 69078, 16827000, 40384800, 'Primer Fly', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Gouache-Oilwash Tuna', 18900, 61047, 16600000, 48140000, 'Brush Bristle Worm', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Vermilion Guppy', 20520, 73462, 18800000, 73320000, 'Linen Larva', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Cerulean Pigment Darter', 22140, 87010, 21000000, 102900000, 'Acrylic Worm', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Ochre Stroke Perch', 23760, 51797, 23200000, 55680000, 'Ink Midge', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Cobalt Easel Trout', 25380, 64211, 25400000, 86360000, 'Turpentine Gnat', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Sienna Huecrest Catfish', 27000, 77760, 27600000, 121440000, 'Palette Grub', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Ultramarine Eel', 28620, 92443, 29800000, 160920000, 'Gesso Shrimp', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Viridian-Watercolor Manta', 30240, 108259, 32000000, 92800000, 'Varnish Beetle', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Magenta Brushfin Mackerel', 31860, 125210, 34200000, 133380000, 'Canvas Crumb', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Indigo Canvas Swordfish', 33480, 72986, 36400000, 178360000, 'Gouache Fry', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Amberwash Varnish Tuna', 35100, 88803, 38600000, 92640000, 'Charcoal Nymph', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Charcoal Guppy', 36720, 105754, 40800000, 138720000, 'Oildrop Worm', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Pastel Tint Darter', 38340, 123838, 43000000, 189200000, 'Pastel Roe', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Prismatic Primer Perch', 39960, 143057, 45200000, 244080000, 'Primer Fly', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'transcendent', 'Lacquer-Glaze Trout', 41580, 163409, 47400000, 137460000, 'Pigment Pearl', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Vermilion Minnow', 40950, 147420, 46480000, 158032000, 'Linen Larva', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Cerulean Canvas Smelt', 44460, 175617, 52640000, 231616000, 'Acrylic Worm', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Ochre Varnish Chub', 47970, 105534, 58800000, 317520000, 'Ink Midge', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Cobalt Fresco Carp', 51480, 131274, 64960000, 188384000, 'Turpentine Gnat', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Sienna Tint Gar', 54990, 159471, 71120000, 277368000, 'Palette Grub', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Ultramarine Grouper', 58500, 190125, 77280000, 378672000, 'Gesso Shrimp', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Viridian-Glaze Ray', 62010, 223236, 83440000, 200256000, 'Varnish Beetle', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Magenta Oilwash Barracuda', 65520, 258804, 89600000, 304640000, 'Canvas Crumb', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Indigo Palette Marlin', 69030, 151866, 95760000, 421344000, 'Gouache Fry', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Amberwash Pigment Coelacanth', 72540, 184977, 101920000, 550368000, 'Charcoal Nymph', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Charcoal Minnow', 76050, 220545, 108080000, 313432000, 'Oildrop Worm', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Pastel Easel Smelt', 79560, 258570, 114240000, 445536000, 'Pastel Roe', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Prismatic Huecrest Chub', 83070, 299052, 120400000, 589960000, 'Primer Fly', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Lacquer-Inkline Carp', 86580, 341991, 126560000, 303744000, 'Pigment Pearl', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'apotheosis', 'Gouache Watercolor Gar', 90090, 198198, 132720000, 451248000, 'Brush Bristle Worm', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Cerulean Palette Loach', 88200, 350154, 132800000, 517920000, 'Acrylic Worm', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Ochre Pigment Shiner', 95760, 212587, 150400000, 736960000, 'Ink Midge', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Cobalt Stroke Bream', 103320, 265532, 168000000, 403200000, 'Turpentine Gnat', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Sienna Easel Pike', 110880, 323770, 185600000, 631040000, 'Palette Grub', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Ultramarine Snapper', 118440, 387299, 203200000, 894080000, 'Gesso Shrimp', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Viridian-Inkline Sturgeon', 126000, 456120, 220800000, 1192320000, 'Varnish Beetle', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Magenta Watercolor Arowana', 133560, 530233, 238400000, 691360000, 'Canvas Crumb', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Indigo Brushfin Salmon', 141120, 313286, 256000000, 998400000, 'Gouache Fry', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Amberwash Canvas Shark', 148680, 382108, 273600000, 1340640000, 'Charcoal Nymph', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Charcoal Leviathan', 156240, 456221, 291200000, 698880000, 'Oildrop Worm', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Pastel Fresco Loach', 163800, 535626, 308800000, 1049920000, 'Pastel Roe', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Prismatic Tint Shiner', 171360, 620323, 326400000, 1436160000, 'Primer Fly', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Lacquer-Primer Bream', 178920, 710312, 344000000, 1857600000, 'Pigment Pearl', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Gouache Glaze Pike', 186480, 413986, 361600000, 1048640000, 'Brush Bristle Worm', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'absolute', 'Vermilion Snapper', 194040, 498683, 379200000, 1478880000, 'Linen Larva', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Ochre Canvas Darter', 189000, 423360, 373500000, 1643400000, 'Ink Midge', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Cobalt Varnish Perch', 205200, 531468, 423000000, 2284200000, 'Turpentine Gnat', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Sienna Fresco Trout', 221400, 650916, 472500000, 1370250000, 'Palette Grub', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Ultramarine Catfish', 237600, 781704, 522000000, 2035800000, 'Gesso Shrimp', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Viridian-Primer Eel', 253800, 923832, 571500000, 2800350000, 'Varnish Beetle', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Magenta Glaze Manta', 270000, 1077300, 621000000, 1490400000, 'Canvas Crumb', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Indigo Oilwash Mackerel', 286200, 641088, 670500000, 2279700000, 'Gouache Fry', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Amberwash Palette Swordfish', 302400, 783216, 720000000, 3168000000, 'Charcoal Nymph', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Charcoal Tuna', 318600, 936684, 769500000, 4155300000, 'Oildrop Worm', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Pastel Stroke Guppy', 334800, 1101492, 819000000, 2375100000, 'Pastel Roe', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Prismatic Easel Darter', 351000, 1277640, 868500000, 3387150000, 'Primer Fly', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Lacquer-Huecrest Perch', 367200, 1465128, 918000000, 4498200000, 'Pigment Pearl', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Gouache Inkline Trout', 383400, 858816, 967500000, 2322000000, 'Brush Bristle Worm', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Vermilion Catfish', 399600, 1034964, 1017000000, 3457800000, 'Linen Larva', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'singularity', 'Cerulean Brushfin Eel', 415800, 1222452, 1066500000, 4692600000, 'Acrylic Worm', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Cobalt Pigment Chub', 409500, 1068795, 1079000000, 5287100000, 'Turpentine Gnat', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Sienna Stroke Carp', 444600, 1316016, 1222000000, 2932800000, 'Palette Grub', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Ultramarine Gar', 479700, 1587807, 1365000000, 4641000000, 'Gesso Shrimp', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Viridian-Huecrest Grouper', 514800, 1884168, 1508000000, 6635200000, 'Varnish Beetle', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Magenta Inkline Ray', 549900, 2205099, 1651000000, 8915400000, 'Canvas Crumb', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Indigo Watercolor Barracuda', 585000, 1322100, 1794000000, 5202600000, 'Gouache Fry', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Amberwash Brushfin Marlin', 620100, 1618461, 1937000000, 7554300000, 'Charcoal Nymph', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Charcoal Coelacanth', 655200, 1939392, 2080000000, 10192000000, 'Oildrop Worm', 'Favours thick acrylic shallows.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Pastel Varnish Minnow', 690300, 2284893, 2223000000, 5335200000, 'Pastel Roe', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Prismatic Fresco Smelt', 725400, 2654964, 2366000000, 8044400000, 'Primer Fly', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Lacquer-Tint Chub', 760500, 3049605, 2509000000, 11039600000, 'Pigment Pearl', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Gouache Primer Carp', 795600, 1798056, 2652000000, 14320800000, 'Brush Bristle Worm', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Vermilion Gar', 830700, 2168127, 2795000000, 8105500000, 'Linen Larva', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Cerulean Oilwash Grouper', 865800, 2562768, 2938000000, 11458200000, 'Acrylic Worm', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'paradox', 'Ochre Palette Ray', 900900, 2981979, 3081000000, 15096900000, 'Ink Midge', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Sienna Varnish Bream', 882000, 2628360, 3071000000, 16583400000, 'Palette Grub', 'Releases a faint turpentine scent when hooked.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Ultramarine Pike', 957600, 3188808, 3478000000, 10086200000, 'Gesso Shrimp', 'Feeds on pigment-rich plankton blooms.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Viridian-Tint Snapper', 1033200, 3802176, 3885000000, 15151500000, 'Varnish Beetle', 'Spooks easily at sudden color flashes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Magenta Primer Sturgeon', 1108800, 4468464, 4292000000, 21030800000, 'Canvas Crumb', 'Schools in complementary color pairs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Indigo Glaze Arowana', 1184400, 2700432, 4699000000, 11277600000, 'Gouache Fry', 'Often found near dripping fresco walls.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Amberwash Oilwash Salmon', 1260000, 3313800, 5106000000, 17360400000, 'Charcoal Nymph', 'Bites aggressively after rain dilutes varnish.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Charcoal Shark', 1335600, 3980088, 5513000000, 24257200000, 'Oildrop Worm', 'Scales shift tone under moving light.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Pastel Pigment Leviathan', 1411200, 4699296, 5920000000, 31968000000, 'Pastel Roe', 'Can camouflage against painted currents.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Prismatic Stroke Loach', 1486800, 5471424, 6327000000, 18348300000, 'Primer Fly', 'Builds nests in rolled canvas reefs.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Lacquer-Easel Shiner', 1562400, 6296472, 6734000000, 26262600000, 'Pigment Pearl', 'Dorsal fins flick like calligraphy strokes.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Gouache Huecrest Bream', 1638000, 3734640, 7141000000, 34990900000, 'Brush Bristle Worm', 'Most active during sunrise palette tides.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Vermilion Pike', 1713600, 4506768, 7548000000, 18115200000, 'Linen Larva', 'Can stain lines if over-fought.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Cerulean Watercolor Snapper', 1789200, 5331816, 7955000000, 27047000000, 'Acrylic Worm', 'Glows softly in ultraviolet wash zones.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Ochre Brushfin Sturgeon', 1864800, 6209784, 8362000000, 36792800000, 'Ink Midge', 'Leaves brushstroke ripples behind each sprint.'),
  ('pigment_peninsula', 'Pigment Peninsula', 'null', 'Cobalt Canvas Arowana', 1940400, 7140672, 8769000000, 47352600000, 'Turpentine Gnat', 'Favours thick acrylic shallows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Ruby Minnow', 0.17, 0.43, 7.28, 24.75, 'Glass Midge', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Cobalt Leadline Smelt', 0.18, 0.53, 8.16, 35.9, 'Candlefly', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Amber Pane Chub', 0.19, 0.63, 9.04, 48.82, 'Rosin Worm', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Jade Window Carp', 0.21, 0.75, 9.92, 28.77, 'Prism Larva', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Sapphire Halo Gar', 0.22, 0.42, 10.8, 42.12, 'Choir Gnat', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Topaz Grouper', 0.23, 0.52, 11.68, 57.23, 'Leadline Beetle', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Opaline Nave Ray', 0.25, 0.64, 12.56, 30.14, 'Incense Shrimp', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Lapis-Aisle Barracuda', 0.26, 0.77, 13.44, 45.7, 'Mosaic Fry', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Garnet Mosaic Marlin', 0.27, 0.9, 14.32, 63.01, 'Sunbeam Roe', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Ivory Rosette Coelacanth', 0.29, 1.05, 15.2, 82.08, 'Halo Nymph', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Sunlit Minnow', 0.3, 0.57, 16.08, 46.63, 'Bell Cricket', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Moonlit Prism Smelt', 0.31, 0.71, 16.96, 66.14, 'Foil Worm', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Cathedral Filigree Chub', 0.33, 0.85, 17.84, 87.42, 'Rosewindow Fly', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Rose Chancel Carp', 0.34, 1, 18.72, 44.93, 'Lattice Grub', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'common', 'Prism-Glazier Gar', 0.35, 1.17, 19.6, 66.64, 'Aisle Midge', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Cobalt Mosaic Loach', 0.61, 1.8, 20.02, 78.08, 'Candlefly', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Amber Rosette Shiner', 0.65, 2.17, 22.44, 110, 'Rosin Worm', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Jade Tracer Bream', 0.7, 2.58, 24.86, 59.66, 'Prism Larva', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Sapphire Prism Pike', 0.75, 1.45, 27.28, 92.75, 'Choir Gnat', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Topaz Snapper', 0.8, 1.82, 29.7, 131, 'Leadline Beetle', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Opaline Chancel Sturgeon', 0.85, 2.23, 32.12, 173, 'Incense Shrimp', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Lapis-Glazier Arowana', 0.9, 2.68, 34.54, 100, 'Mosaic Fry', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Garnet Shard Salmon', 0.95, 3.16, 36.96, 144, 'Sunbeam Roe', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Ivory Leadline Shark', 1, 3.67, 39.38, 193, 'Halo Nymph', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Sunlit Leviathan', 1.05, 2.02, 41.8, 100, 'Bell Cricket', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Moonlit Window Loach', 1.1, 2.5, 44.22, 150, 'Foil Worm', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Cathedral Halo Shiner', 1.15, 3.01, 46.64, 205, 'Rosewindow Fly', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Rose Lattice Bream', 1.2, 3.56, 49.06, 265, 'Lattice Grub', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Prism-Nave Pike', 1.25, 4.15, 51.48, 149, 'Aisle Midge', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'uncommon', 'Ruby Snapper', 1.3, 4.76, 53.9, 210, 'Glass Midge', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Amber Leadline Darter', 1.54, 5.14, 63.7, 280, 'Rosin Worm', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Jade Pane Perch', 1.67, 6.15, 71.4, 386, 'Prism Larva', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Sapphire Window Trout', 1.79, 3.48, 79.1, 229, 'Choir Gnat', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Topaz Catfish', 1.92, 4.39, 86.8, 339, 'Leadline Beetle', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Opaline Lattice Eel', 2.04, 5.4, 94.5, 463, 'Incense Shrimp', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Lapis-Nave Manta', 2.17, 6.49, 102, 245, 'Mosaic Fry', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Garnet Aisle Mackerel', 2.3, 7.67, 110, 374, 'Sunbeam Roe', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Ivory Mosaic Swordfish', 2.42, 8.94, 118, 517, 'Halo Nymph', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Sunlit Tuna', 2.55, 4.94, 125, 677, 'Bell Cricket', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Moonlit Tracer Guppy', 2.67, 6.12, 133, 386, 'Foil Worm', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Cathedral Prism Darter', 2.8, 7.39, 141, 549, 'Rosewindow Fly', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Rose Filigree Perch', 2.93, 8.75, 148, 727, 'Lattice Grub', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Prism-Chancel Trout', 3.05, 10.19, 156, 375, 'Aisle Midge', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Ruby Catfish', 3.18, 11.73, 164, 557, 'Glass Midge', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'rare', 'Cobalt Shard Eel', 3.3, 6.41, 172, 755, 'Candlefly', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Jade Rosette Chub', 4.18, 15.51, 191, 936, 'Prism Larva', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Sapphire Tracer Carp', 4.52, 8.86, 214, 514, 'Choir Gnat', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Topaz Gar', 4.86, 11.24, 237, 807, 'Leadline Beetle', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Opaline Filigree Grouper', 5.21, 13.85, 260, 1146, 'Incense Shrimp', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Lapis-Chancel Ray', 5.55, 16.7, 284, 1531, 'Mosaic Fry', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Garnet Glazier Barracuda', 5.89, 19.79, 307, 889, 'Sunbeam Roe', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Ivory Shard Marlin', 6.23, 23.12, 330, 1286, 'Halo Nymph', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Sunlit Coelacanth', 6.57, 12.89, 353, 1729, 'Bell Cricket', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Moonlit Pane Minnow', 6.92, 15.98, 376, 902, 'Foil Worm', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Cathedral Window Smelt', 7.26, 19.31, 399, 1357, 'Rosewindow Fly', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Rose Halo Chub', 7.6, 22.88, 422, 1857, 'Lattice Grub', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Prism-Lattice Carp', 7.94, 26.69, 445, 2404, 'Aisle Midge', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Ruby Gar', 8.28, 30.73, 468, 1358, 'Glass Midge', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Cobalt Aisle Grouper', 8.63, 16.91, 491, 1916, 'Candlefly', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'epic', 'Amber Mosaic Ray', 8.97, 20.72, 515, 2521, 'Rosin Worm', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Sapphire Pane Bream', 10.45, 20.69, 564, 3047, 'Choir Gnat', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Topaz Pike', 11.31, 26.34, 632, 1834, 'Leadline Beetle', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Opaline Halo Snapper', 12.16, 32.59, 701, 2732, 'Incense Shrimp', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Lapis-Lattice Sturgeon', 13.02, 39.44, 769, 3767, 'Mosaic Fry', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Garnet Nave Arowana', 13.87, 46.88, 837, 2009, 'Sunbeam Roe', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Ivory Aisle Salmon', 14.73, 54.92, 905, 3078, 'Halo Nymph', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Sunlit Shark', 15.58, 30.85, 973, 4283, 'Bell Cricket', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Moonlit Rosette Leviathan', 16.43, 38.29, 1042, 5625, 'Foil Worm', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Cathedral Tracer Loach', 17.29, 46.34, 1110, 3218, 'Rosewindow Fly', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Rose Prism Shiner', 18.15, 54.98, 1178, 4594, 'Lattice Grub', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Prism-Filigree Bream', 19, 64.22, 1246, 6106, 'Aisle Midge', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Ruby Pike', 19.85, 74.06, 1314, 3155, 'Glass Midge', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Cobalt Glazier Snapper', 20.71, 41.01, 1383, 4701, 'Candlefly', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Amber Shard Sturgeon', 21.57, 50.25, 1451, 6384, 'Rosin Worm', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'legendary', 'Jade Leadline Arowana', 22.42, 60.09, 1519, 8203, 'Prism Larva', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Topaz Trout', 22, 51.7, 1593, 3822, 'Leadline Beetle', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Opaline Prism Catfish', 23.8, 64.26, 1785, 6069, 'Incense Shrimp', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Lapis-Filigree Eel', 25.6, 78.08, 1977, 8701, 'Mosaic Fry', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Garnet Chancel Manta', 27.4, 93.16, 2170, 11718, 'Sunbeam Roe', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Ivory Glazier Mackerel', 29.2, 110, 2362, 6851, 'Halo Nymph', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Sunlit Swordfish', 31, 62, 2555, 9965, 'Bell Cricket', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Moonlit Leadline Tuna', 32.8, 77.08, 2748, 13463, 'Foil Worm', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Cathedral Pane Guppy', 34.6, 93.42, 2940, 7056, 'Rosewindow Fly', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Rose Window Darter', 36.4, 111, 3132, 10650, 'Lattice Grub', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Prism-Halo Perch', 38.2, 130, 3325, 14630, 'Aisle Midge', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Ruby Trout', 40, 150, 3518, 18995, 'Glass Midge', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Cobalt Nave Catfish', 41.8, 83.6, 3710, 10759, 'Candlefly', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Amber Aisle Eel', 43.6, 102, 3903, 15220, 'Rosin Worm', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Jade Mosaic Manta', 45.4, 123, 4095, 20066, 'Prism Larva', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'liminal', 'Sapphire Rosette Mackerel', 47.2, 144, 4288, 10290, 'Choir Gnat', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Opaline Window Gar', 47.3, 129, 4459, 12931, 'Incense Shrimp', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Lapis-Halo Grouper', 51.17, 157, 4998, 19492, 'Mosaic Fry', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Garnet Lattice Ray', 55.04, 188, 5537, 27131, 'Sunbeam Roe', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Ivory Nave Barracuda', 58.91, 222, 6076, 14582, 'Halo Nymph', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Sunlit Marlin', 62.78, 127, 6615, 22491, 'Bell Cricket', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Moonlit Mosaic Coelacanth', 66.65, 158, 7154, 31478, 'Foil Worm', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Cathedral Rosette Minnow', 70.52, 192, 7693, 41542, 'Rosewindow Fly', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Rose Tracer Smelt', 74.39, 228, 8232, 23873, 'Lattice Grub', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Prism Chub', 78.26, 268, 8771, 34207, 'Aisle Midge', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Ruby Carp', 82.13, 310, 9310, 45619, 'Glass Midge', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Cobalt Chancel Gar', 86, 174, 9849, 23638, 'Candlefly', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Amber Glazier Grouper', 89.87, 213, 10388, 35319, 'Rosin Worm', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Jade Shard Ray', 93.74, 255, 10927, 48079, 'Prism Larva', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Sapphire Leadline Barracuda', 97.61, 300, 11466, 61916, 'Choir Gnat', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'mythic', 'Topaz Marlin', 101, 347, 12005, 34815, 'Leadline Beetle', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Lapis-Prism Snapper', 99, 306, 12558, 42697, 'Mosaic Fry', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Garnet Filigree Sturgeon', 107, 368, 14076, 61934, 'Sunbeam Roe', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Ivory Chancel Arowana', 115, 437, 15594, 84208, 'Halo Nymph', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Sunlit Salmon', 123, 252, 17112, 49625, 'Bell Cricket', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Moonlit Shard Shark', 131, 314, 18630, 72657, 'Foil Worm', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Cathedral Leadline Leviathan', 140, 382, 20148, 98725, 'Rosewindow Fly', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Rose Pane Loach', 148, 456, 21666, 51998, 'Lattice Grub', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Prism-Window Shiner', 156, 536, 23184, 78826, 'Aisle Midge', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Ruby Bream', 164, 621, 24702, 108689, 'Glass Midge', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Cobalt Lattice Pike', 172, 351, 26220, 141588, 'Candlefly', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Amber Nave Snapper', 180, 430, 27738, 80440, 'Rosin Worm', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Jade Aisle Sturgeon', 188, 515, 29256, 114098, 'Prism Larva', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Sapphire Mosaic Arowana', 196, 606, 30774, 150793, 'Choir Gnat', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Topaz Salmon', 204, 703, 32292, 77501, 'Leadline Beetle', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'ascendant', 'Opaline-Tracer Shark', 212, 805, 33810, 114954, 'Incense Shrimp', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Garnet Halo Eel', 209, 723, 35490, 138411, 'Sunbeam Roe', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Ivory Lattice Manta', 226, 861, 39780, 194922, 'Halo Nymph', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Sunlit Mackerel', 243, 501, 44070, 105768, 'Bell Cricket', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Moonlit Aisle Swordfish', 260, 627, 48360, 164424, 'Foil Worm', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Cathedral Mosaic Tuna', 277, 766, 52650, 231660, 'Rosewindow Fly', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Rose Rosette Guppy', 295, 916, 56940, 307476, 'Lattice Grub', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Prism-Tracer Darter', 312, 1078, 61230, 177567, 'Aisle Midge', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Ruby Perch', 329, 1252, 65520, 255528, 'Glass Midge', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Cobalt Filigree Trout', 346, 712, 69810, 342069, 'Candlefly', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Amber Chancel Catfish', 363, 875, 74100, 177840, 'Rosin Worm', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Jade Glazier Eel', 380, 1049, 78390, 266526, 'Prism Larva', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Sapphire Shard Manta', 397, 1235, 82680, 363792, 'Choir Gnat', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Topaz Mackerel', 414, 1433, 86970, 469638, 'Leadline Beetle', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Opaline-Pane Swordfish', 431, 1643, 91260, 264654, 'Incense Shrimp', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'celestial', 'Lapis Window Tuna', 448, 924, 95550, 372645, 'Mosaic Fry', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Ivory Filigree Ray', 440, 1685, 100100, 440440, 'Halo Nymph', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Sunlit Barracuda', 476, 990, 112200, 605880, 'Bell Cricket', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Moonlit Glazier Marlin', 512, 1244, 124300, 360470, 'Foil Worm', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Cathedral Shard Coelacanth', 548, 1523, 136400, 531960, 'Rosewindow Fly', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Rose Leadline Minnow', 584, 1828, 148500, 727650, 'Lattice Grub', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Prism-Pane Smelt', 620, 2158, 160600, 385440, 'Aisle Midge', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Ruby Chub', 656, 2512, 172700, 587180, 'Glass Midge', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Cobalt Halo Carp', 692, 1439, 184800, 813120, 'Candlefly', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Amber Lattice Gar', 728, 1769, 196900, 1063260, 'Rosin Worm', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Jade Nave Grouper', 764, 2124, 209000, 606100, 'Prism Larva', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Sapphire Aisle Ray', 800, 2504, 221100, 862290, 'Choir Gnat', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Topaz Barracuda', 836, 2909, 233200, 1142680, 'Leadline Beetle', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Opaline-Rosette Marlin', 872, 3340, 245300, 588720, 'Incense Shrimp', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Lapis Tracer Coelacanth', 908, 1889, 257400, 875160, 'Mosaic Fry', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eldritch', 'Garnet Prism Minnow', 944, 2294, 269500, 1185800, 'Sunbeam Roe', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Sunlit Arowana', 935, 1964, 282100, 1382290, 'Bell Cricket', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Moonlit Nave Salmon', 1012, 2478, 316200, 758880, 'Foil Worm', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Cathedral Aisle Shark', 1088, 3046, 350300, 1191020, 'Rosewindow Fly', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Rose Mosaic Leviathan', 1165, 3668, 384400, 1691360, 'Lattice Grub', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Prism-Rosette Loach', 1241, 4344, 418500, 2259900, 'Aisle Midge', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Ruby Shiner', 1318, 5072, 452600, 1312540, 'Glass Midge', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Cobalt Prism Bream', 1394, 2927, 486700, 1898130, 'Candlefly', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Amber Filigree Pike', 1471, 3603, 520800, 2551920, 'Rosin Worm', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Jade Chancel Snapper', 1547, 4332, 554900, 1331760, 'Prism Larva', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Sapphire Glazier Sturgeon', 1624, 5114, 589000, 2002600, 'Choir Gnat', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Topaz Arowana', 1700, 5950, 623100, 2741640, 'Leadline Beetle', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Opaline-Leadline Salmon', 1776, 6840, 657200, 3548880, 'Incense Shrimp', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Lapis Pane Shark', 1853, 3891, 691300, 2004770, 'Mosaic Fry', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Garnet Window Leviathan', 1930, 4727, 725400, 2829060, 'Sunbeam Roe', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'eternal', 'Ivory Halo Loach', 2006, 5617, 759500, 3721550, 'Halo Nymph', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Moonlit Chancel Mackerel', 1980, 4891, 800800, 4324320, 'Foil Worm', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Cathedral Glazier Swordfish', 2142, 6040, 897600, 2603040, 'Rosewindow Fly', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Rose Shard Tuna', 2304, 7304, 994400, 3878160, 'Lattice Grub', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Prism-Leadline Guppy', 2466, 8680, 1091200, 5346880, 'Aisle Midge', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Ruby Darter', 2628, 10170, 1188000, 2851200, 'Glass Midge', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Cobalt Window Perch', 2790, 5915, 1284800, 4368320, 'Candlefly', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Amber Halo Trout', 2952, 7291, 1381600, 6079040, 'Rosin Worm', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Jade Lattice Catfish', 3114, 8781, 1478400, 7983360, 'Prism Larva', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Sapphire Nave Eel', 3276, 10385, 1575200, 4568080, 'Choir Gnat', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Topaz Manta', 3438, 12102, 1672000, 6520800, 'Leadline Beetle', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Opaline-Mosaic Mackerel', 3600, 13932, 1768800, 8667120, 'Incense Shrimp', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Lapis Rosette Swordfish', 3762, 7975, 1865600, 4477440, 'Mosaic Fry', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Garnet Tracer Tuna', 3924, 9692, 1962400, 6672160, 'Sunbeam Roe', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Ivory Prism Guppy', 4086, 11523, 2059200, 9060480, 'Halo Nymph', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'divine', 'Sunlit Darter', 4248, 13466, 2156000, 11642400, 'Bell Cricket', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Cathedral Nave Marlin', 4290, 12184, 2275000, 5460000, 'Rosewindow Fly', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Rose Aisle Coelacanth', 4641, 14805, 2550000, 8670000, 'Lattice Grub', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Prism-Mosaic Minnow', 4992, 17672, 2825000, 12430000, 'Aisle Midge', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Ruby Smelt', 5343, 20784, 3100000, 16740000, 'Glass Midge', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Cobalt Tracer Chub', 5694, 12185, 3375000, 9787500, 'Candlefly', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Amber Prism Carp', 6045, 15052, 3650000, 14235000, 'Rosin Worm', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Jade Filigree Gar', 6396, 18165, 3925000, 19232500, 'Prism Larva', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Sapphire Chancel Grouper', 6747, 21523, 4200000, 10080000, 'Choir Gnat', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Topaz Ray', 7098, 25127, 4475000, 15215000, 'Leadline Beetle', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Opaline-Shard Barracuda', 7449, 28977, 4750000, 20900000, 'Incense Shrimp', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Lapis Leadline Marlin', 7800, 16692, 5025000, 27135000, 'Mosaic Fry', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Garnet Pane Coelacanth', 8151, 20296, 5300000, 15370000, 'Sunbeam Roe', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Ivory Window Minnow', 8502, 24146, 5575000, 21742500, 'Halo Nymph', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Sunlit Smelt', 8853, 28241, 5850000, 28665000, 'Bell Cricket', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'cosmic', 'Moonlit Lattice Chub', 9204, 32582, 6125000, 14700000, 'Foil Worm', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Rose Glazier Shark', 9240, 29660, 6461000, 18736900, 'Lattice Grub', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Prism-Shard Leviathan', 9996, 35586, 7242000, 28243800, 'Aisle Midge', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Ruby Loach', 10752, 42040, 8023000, 39312700, 'Glass Midge', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Cobalt Pane Shiner', 11508, 24857, 8804000, 21129600, 'Candlefly', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Amber Window Bream', 12264, 30783, 9585000, 32589000, 'Rosin Worm', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Jade Halo Pike', 13020, 37237, 10366000, 45610400, 'Prism Larva', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Sapphire Lattice Snapper', 13776, 44221, 11147000, 60193800, 'Choir Gnat', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Topaz Sturgeon', 14532, 51734, 11928000, 34591200, 'Leadline Beetle', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Opaline-Aisle Arowana', 15288, 59776, 12709000, 49565100, 'Incense Shrimp', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Lapis Mosaic Salmon', 16044, 34655, 13490000, 66101000, 'Mosaic Fry', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Garnet Rosette Shark', 16800, 42168, 14271000, 34250400, 'Sunbeam Roe', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Ivory Tracer Leviathan', 17556, 50210, 15052000, 51176800, 'Halo Nymph', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Sunlit Loach', 18312, 58782, 15833000, 69665200, 'Bell Cricket', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Moonlit Filigree Shiner', 19068, 67882, 16614000, 89715600, 'Foil Worm', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'primordial', 'Cathedral Chancel Bream', 19824, 77512, 17395000, 50445500, 'Rosewindow Fly', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Prism-Aisle Tuna', 19800, 70884, 18200000, 61880000, 'Aisle Midge', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Ruby Guppy', 21420, 84181, 20400000, 89760000, 'Glass Midge', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Cobalt Rosette Darter', 23040, 50227, 22600000, 122040000, 'Candlefly', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Amber Tracer Perch', 24660, 62390, 24800000, 71920000, 'Rosin Worm', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Jade Prism Trout', 26280, 75686, 27000000, 105300000, 'Prism Larva', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Sapphire Filigree Catfish', 27900, 90117, 29200000, 143080000, 'Choir Gnat', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Topaz Eel', 29520, 105682, 31400000, 75360000, 'Leadline Beetle', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Opaline-Glazier Manta', 31140, 122380, 33600000, 114240000, 'Incense Shrimp', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Lapis Shard Mackerel', 32760, 71417, 35800000, 157520000, 'Mosaic Fry', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Garnet Leadline Swordfish', 34380, 86981, 38000000, 205200000, 'Sunbeam Roe', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Ivory Pane Tuna', 36000, 103680, 40200000, 116580000, 'Halo Nymph', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Sunlit Guppy', 37620, 121513, 42400000, 165360000, 'Bell Cricket', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Moonlit Halo Darter', 39240, 140479, 44600000, 218540000, 'Foil Worm', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Cathedral Lattice Perch', 40860, 160580, 46800000, 112320000, 'Rosewindow Fly', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'transcendent', 'Rose-Nave Trout', 42480, 92606, 49000000, 166600000, 'Lattice Grub', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Ruby Minnow', 42900, 169455, 50960000, 198744000, 'Glass Midge', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Cobalt Leadline Smelt', 46410, 102102, 57120000, 279888000, 'Candlefly', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Amber Pane Chub', 49920, 127296, 63280000, 151872000, 'Rosin Worm', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Jade Window Carp', 53430, 154947, 69440000, 236096000, 'Prism Larva', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Sapphire Halo Gar', 56940, 185055, 75600000, 332640000, 'Choir Gnat', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Topaz Grouper', 60450, 217620, 81760000, 441504000, 'Leadline Beetle', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Opaline-Nave Ray', 63960, 252642, 87920000, 254968000, 'Incense Shrimp', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Lapis Aisle Barracuda', 67470, 148434, 94080000, 366912000, 'Mosaic Fry', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Garnet Mosaic Marlin', 70980, 180999, 100240000, 491176000, 'Sunbeam Roe', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Ivory Rosette Coelacanth', 74490, 216021, 106400000, 255360000, 'Halo Nymph', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Sunlit Minnow', 78000, 253500, 112560000, 382704000, 'Bell Cricket', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Moonlit Prism Smelt', 81510, 293436, 118720000, 522368000, 'Foil Worm', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Cathedral Filigree Chub', 85020, 335829, 124880000, 674352000, 'Rosewindow Fly', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Rose-Chancel Carp', 88530, 194766, 131040000, 380016000, 'Lattice Grub', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'apotheosis', 'Prism Glazier Gar', 92040, 234702, 137200000, 535080000, 'Aisle Midge', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Cobalt Mosaic Loach', 92400, 205128, 145600000, 640640000, 'Candlefly', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Amber Rosette Shiner', 99960, 256897, 163200000, 881280000, 'Rosin Worm', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Jade Tracer Bream', 107520, 313958, 180800000, 524320000, 'Prism Larva', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Sapphire Prism Pike', 115080, 376312, 198400000, 773760000, 'Choir Gnat', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Topaz Snapper', 122640, 443957, 216000000, 1058400000, 'Leadline Beetle', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Opaline-Chancel Sturgeon', 130200, 516894, 233600000, 560640000, 'Incense Shrimp', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Lapis Glazier Arowana', 137760, 305827, 251200000, 854080000, 'Mosaic Fry', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Garnet Shard Salmon', 145320, 373472, 268800000, 1182720000, 'Sunbeam Roe', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Ivory Leadline Shark', 152880, 446410, 286400000, 1546560000, 'Halo Nymph', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Sunlit Leviathan', 160440, 524639, 304000000, 881600000, 'Bell Cricket', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Moonlit Window Loach', 168000, 608160, 321600000, 1254240000, 'Foil Worm', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Cathedral Halo Shiner', 175560, 696973, 339200000, 1662080000, 'Rosewindow Fly', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Rose-Lattice Bream', 183120, 406526, 356800000, 856320000, 'Lattice Grub', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Prism Nave Pike', 190680, 490048, 374400000, 1272960000, 'Aisle Midge', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'absolute', 'Ruby Snapper', 198240, 578861, 392000000, 1724800000, 'Glass Midge', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Amber Leadline Darter', 198000, 512820, 409500000, 2006550000, 'Rosin Worm', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Jade Pane Perch', 214200, 629748, 459000000, 1101600000, 'Prism Larva', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Sapphire Window Trout', 230400, 758016, 508500000, 1728900000, 'Choir Gnat', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Topaz Catfish', 246600, 897624, 558000000, 2455200000, 'Leadline Beetle', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Opaline-Lattice Eel', 262800, 1048572, 607500000, 3280500000, 'Incense Shrimp', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Lapis Nave Manta', 279000, 624960, 657000000, 1905300000, 'Mosaic Fry', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Garnet Aisle Mackerel', 295200, 764568, 706500000, 2755350000, 'Sunbeam Roe', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Ivory Mosaic Swordfish', 311400, 915516, 756000000, 3704400000, 'Halo Nymph', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Sunlit Tuna', 327600, 1077804, 805500000, 1933200000, 'Bell Cricket', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Moonlit Tracer Guppy', 343800, 1251432, 855000000, 2907000000, 'Foil Worm', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Cathedral Prism Darter', 360000, 1436400, 904500000, 3979800000, 'Rosewindow Fly', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Rose-Filigree Perch', 376200, 842688, 954000000, 5151600000, 'Lattice Grub', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Prism Chancel Trout', 392400, 1016316, 1003500000, 2910150000, 'Aisle Midge', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Ruby Catfish', 408600, 1201284, 1053000000, 4106700000, 'Glass Midge', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'singularity', 'Cobalt Shard Eel', 424800, 1397592, 1102500000, 5402250000, 'Candlefly', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Jade Rosette Chub', 429000, 1269840, 1183000000, 6388200000, 'Prism Larva', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Sapphire Tracer Carp', 464100, 1536171, 1326000000, 3845400000, 'Choir Gnat', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Topaz Gar', 499200, 1827072, 1469000000, 5729100000, 'Leadline Beetle', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Opaline-Filigree Grouper', 534300, 2142543, 1612000000, 7898800000, 'Incense Shrimp', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Lapis Chancel Ray', 569400, 1286844, 1755000000, 4212000000, 'Mosaic Fry', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Garnet Glazier Barracuda', 604500, 1577745, 1898000000, 6453200000, 'Sunbeam Roe', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Ivory Shard Marlin', 639600, 1893216, 2041000000, 8980400000, 'Halo Nymph', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Sunlit Coelacanth', 674700, 2233257, 2184000000, 11793600000, 'Bell Cricket', 'Emits bell-like clicks when schooling.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Moonlit Pane Minnow', 709800, 2597868, 2327000000, 6748300000, 'Foil Worm', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Cathedral Window Smelt', 744900, 2987049, 2470000000, 9633000000, 'Rosewindow Fly', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Rose-Halo Chub', 780000, 1762800, 2613000000, 12803700000, 'Lattice Grub', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Prism Lattice Carp', 815100, 2127411, 2756000000, 6614400000, 'Aisle Midge', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Ruby Gar', 850200, 2516592, 2899000000, 9856600000, 'Glass Midge', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Cobalt Aisle Grouper', 885300, 2930343, 3042000000, 13384800000, 'Candlefly', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'paradox', 'Amber Mosaic Ray', 920400, 3368664, 3185000000, 17199000000, 'Rosin Worm', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Sapphire Pane Bream', 924000, 3076920, 3367000000, 8080800000, 'Choir Gnat', 'Hides along leadline seams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Topaz Pike', 999600, 3678528, 3774000000, 12831600000, 'Leadline Beetle', 'Most active during evening candle haze.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Opaline-Halo Snapper', 1075200, 4333056, 4181000000, 18396400000, 'Incense Shrimp', 'Nests in mosaic alcoves.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Lapis Lattice Sturgeon', 1150800, 2623824, 4588000000, 24775200000, 'Mosaic Fry', 'Turns nearly transparent against clear panes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Garnet Nave Arowana', 1226400, 3225432, 4995000000, 14485500000, 'Sunbeam Roe', 'Tail fins ring like crystal chimes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Ivory Aisle Salmon', 1302000, 3879960, 5402000000, 21067800000, 'Halo Nymph', 'Surges during storm-lit lightning flashes.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Sunlit Shark', 1377600, 4587408, 5809000000, 28464100000, 'Bell Cricket', 'Prefers quiet pools beneath rose windows.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Moonlit Rosette Leviathan', 1453200, 5347776, 6216000000, 14918400000, 'Foil Worm', 'Cuts abrupt angles through shard gardens.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Cathedral Tracer Loach', 1528800, 6161064, 6623000000, 22518200000, 'Rosewindow Fly', 'Flares with sunrise through cathedral glass.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Rose-Prism Shiner', 1604400, 3658032, 7030000000, 30932000000, 'Lattice Grub', 'Can chip brittle scales under heavy drag.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Prism Filigree Bream', 1680000, 4418400, 7437000000, 40159800000, 'Aisle Midge', 'Tracks polarized light with unusual precision.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Ruby Pike', 1755600, 5231688, 7844000000, 22747600000, 'Glass Midge', 'Drawn to incense-rich currents.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Cobalt Glazier Snapper', 1831200, 6097896, 8251000000, 32178900000, 'Candlefly', 'Avoids muddy water and ash blooms.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Amber Shard Sturgeon', 1906800, 7017024, 8658000000, 42424200000, 'Rosin Worm', 'Scales refract light into narrow beams.'),
  ('stained_glass_sanctuary', 'Stained-Glass Sanctuary', 'null', 'Jade Leadline Arowana', 1982400, 7989072, 9065000000, 21756000000, 'Prism Larva', 'Emits bell-like clicks when schooling.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Pitcher Minnow', 0.17, 0.51, 7.92, 30.89, 'Nectar Moth', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Thorned Vine Smelt', 0.19, 0.61, 8.8, 43.12, 'Pollen Worm', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Nectar Anther Chub', 0.2, 0.73, 9.68, 23.23, 'Sap Beetle', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Vinebound Tendril Carp', 0.21, 0.4, 10.56, 35.9, 'Leafhopper', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Sporelit Sepal Gar', 0.23, 0.51, 11.44, 50.34, 'Bog Cricket', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Sapgreen Grouper', 0.24, 0.62, 12.32, 66.53, 'Root Grub', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Briar Frond Ray', 0.25, 0.75, 13.2, 38.28, 'Spore Fry', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Bloomfang-Stalk Barracuda', 0.27, 0.88, 14.08, 54.91, 'Thorn Fly', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Trapleaf Pitcher Marlin', 0.28, 1.02, 14.96, 73.3, 'Petal Nymph', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Pollen Nectar Coelacanth', 0.29, 0.56, 15.84, 38.02, 'Stamen Midge', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Rooted Minnow', 0.31, 0.69, 16.72, 56.85, 'Vine Leech', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Canopy Pod Smelt', 0.32, 0.83, 17.6, 77.44, 'Dew Shrimp', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Stamen Calyx Chub', 0.33, 0.99, 18.48, 99.79, 'Pitcher Larva', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Petal Spine Carp', 0.35, 1.15, 19.36, 56.14, 'Briar Beetle', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'common', 'Verdant-Bud Gar', 0.36, 1.32, 20.24, 78.94, 'Frond Worm', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Thorned Pitcher Loach', 0.63, 2.1, 21.78, 95.83, 'Pollen Worm', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Nectar Shiner', 0.68, 2.5, 24.2, 131, 'Sap Beetle', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Vinebound Bramble Bream', 0.73, 1.4, 26.62, 77.2, 'Leafhopper', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Sporelit Pod Pike', 0.78, 1.77, 29.04, 113, 'Bog Cricket', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Sapgreen Snapper', 0.83, 2.18, 31.46, 154, 'Root Grub', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Briar Spine Sturgeon', 0.88, 2.61, 33.88, 81.31, 'Spore Fry', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Bloomfang-Bud Arowana', 0.93, 3.09, 36.3, 123, 'Thorn Fly', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Trapleaf Flytrap Salmon', 0.98, 3.59, 38.72, 170, 'Petal Nymph', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Pollen Vine Shark', 1.03, 1.97, 41.14, 222, 'Stamen Midge', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Rooted Leviathan', 1.08, 2.45, 43.56, 126, 'Vine Leech', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Canopy Tendril Loach', 1.13, 2.95, 45.98, 179, 'Dew Shrimp', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Stamen Sepal Shiner', 1.18, 3.5, 48.4, 237, 'Pitcher Larva', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Petal Root Bream', 1.23, 4.07, 50.82, 122, 'Briar Beetle', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Verdant-Frond Pike', 1.28, 4.68, 53.24, 181, 'Frond Worm', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'uncommon', 'Pitcher Snapper', 1.33, 2.54, 55.66, 245, 'Nectar Moth', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Nectar Vine Darter', 1.61, 5.94, 69.3, 340, 'Sap Beetle', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Vinebound Anther Perch', 1.74, 3.37, 77, 185, 'Leafhopper', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Sporelit Tendril Trout', 1.86, 4.26, 84.7, 288, 'Bog Cricket', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Sapgreen Catfish', 1.99, 5.25, 92.4, 407, 'Root Grub', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Briar Root Eel', 2.11, 6.32, 100, 541, 'Spore Fry', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Bloomfang-Frond Manta', 2.24, 7.48, 108, 313, 'Thorn Fly', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Trapleaf Stalk Mackerel', 2.37, 8.73, 116, 450, 'Petal Nymph', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Pollen Pitcher Swordfish', 2.49, 4.83, 123, 604, 'Stamen Midge', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Rooted Tuna', 2.62, 6, 131, 314, 'Vine Leech', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Canopy Bramble Guppy', 2.74, 7.24, 139, 471, 'Dew Shrimp', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Stamen Pod Darter', 2.87, 8.58, 146, 644, 'Pitcher Larva', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Petal Calyx Perch', 3, 10.01, 154, 832, 'Briar Beetle', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Verdant-Spine Trout', 3.12, 11.52, 162, 469, 'Frond Worm', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Pitcher Catfish', 3.25, 6.3, 169, 661, 'Nectar Moth', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'rare', 'Thorned Flytrap Eel', 3.37, 7.73, 177, 868, 'Pollen Worm', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Vinebound Nectar Chub', 4.37, 8.57, 208, 1123, 'Leafhopper', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Sporelit Bramble Carp', 4.71, 10.88, 231, 670, 'Bog Cricket', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Sapgreen Gar', 5.05, 13.44, 254, 991, 'Root Grub', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Briar Calyx Grouper', 5.4, 16.24, 277, 1358, 'Spore Fry', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Bloomfang-Spine Ray', 5.74, 19.28, 300, 721, 'Thorn Fly', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Trapleaf Bud Barracuda', 6.08, 22.56, 323, 1100, 'Petal Nymph', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Pollen Flytrap Marlin', 6.42, 12.59, 347, 1525, 'Stamen Midge', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Rooted Coelacanth', 6.76, 15.62, 370, 1996, 'Vine Leech', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Canopy Anther Minnow', 7.11, 18.9, 393, 1139, 'Dew Shrimp', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Stamen Tendril Smelt', 7.45, 22.42, 416, 1622, 'Pitcher Larva', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Petal Sepal Chub', 7.79, 26.17, 439, 2151, 'Briar Beetle', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Verdant-Root Carp', 8.13, 30.17, 462, 1109, 'Frond Worm', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Pitcher Gar', 8.47, 16.61, 485, 1649, 'Nectar Moth', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Thorned Stalk Grouper', 8.82, 20.36, 508, 2236, 'Pollen Worm', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'epic', 'Nectar Pitcher Ray', 9.16, 24.36, 531, 2869, 'Sap Beetle', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Sporelit Anther Bream', 10.93, 25.46, 614, 1473, 'Bog Cricket', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Sapgreen Pike', 11.78, 31.57, 682, 2319, 'Root Grub', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Briar Sepal Snapper', 12.64, 38.28, 750, 3301, 'Spore Fry', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Bloomfang-Root Sturgeon', 13.49, 45.6, 818, 4419, 'Thorn Fly', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Trapleaf Frond Arowana', 14.35, 53.51, 887, 2571, 'Petal Nymph', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Pollen Stalk Salmon', 15.2, 30.1, 955, 3724, 'Stamen Midge', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Rooted Shark', 16.06, 37.41, 1023, 5013, 'Vine Leech', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Canopy Nectar Leviathan', 16.91, 45.32, 1091, 2619, 'Dew Shrimp', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Stamen Bramble Loach', 17.77, 53.83, 1159, 3942, 'Pitcher Larva', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Petal Pod Shiner', 18.62, 62.94, 1228, 5401, 'Briar Beetle', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Verdant-Calyx Bream', 19.47, 72.64, 1296, 6997, 'Frond Worm', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Pitcher Pike', 20.33, 40.25, 1364, 3956, 'Nectar Moth', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Thorned Bud Snapper', 21.19, 49.36, 1432, 5586, 'Pollen Worm', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Nectar Flytrap Sturgeon', 22.04, 59.07, 1500, 7352, 'Sap Beetle', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'legendary', 'Vinebound Vine Arowana', 22.89, 69.37, 1569, 3765, 'Leafhopper', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Sapgreen Trout', 23, 62.1, 1733, 5024, 'Root Grub', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Briar Pod Catfish', 24.8, 75.64, 1925, 7508, 'Spore Fry', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Bloomfang-Calyx Eel', 26.6, 90.44, 2118, 10376, 'Thorn Fly', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Trapleaf Spine Manta', 28.4, 107, 2310, 5544, 'Petal Nymph', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Pollen Bud Mackerel', 30.2, 60.4, 2503, 8509, 'Stamen Midge', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Rooted Swordfish', 32, 75.2, 2695, 11858, 'Vine Leech', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Canopy Vine Tuna', 33.8, 91.26, 2888, 15593, 'Dew Shrimp', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Stamen Anther Guppy', 35.6, 109, 3080, 8932, 'Pitcher Larva', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Petal Tendril Darter', 37.4, 127, 3273, 12763, 'Briar Beetle', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Verdant-Sepal Perch', 39.2, 147, 3465, 16979, 'Frond Worm', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Pitcher Trout', 41, 82, 3657, 8778, 'Nectar Moth', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Thorned Frond Catfish', 42.8, 101, 3850, 13090, 'Pollen Worm', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Nectar Stalk Eel', 44.6, 120, 4043, 17787, 'Sap Beetle', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Vinebound Pitcher Manta', 46.4, 142, 4235, 22869, 'Leafhopper', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'liminal', 'Sporelit Nectar Mackerel', 48.2, 164, 4428, 12840, 'Bog Cricket', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Briar Tendril Gar', 49.45, 152, 4851, 16493, 'Spore Fry', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Bloomfang-Sepal Grouper', 53.32, 182, 5390, 23716, 'Thorn Fly', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Trapleaf Root Ray', 57.19, 216, 5929, 32017, 'Petal Nymph', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Pollen Frond Barracuda', 61.06, 123, 6468, 18757, 'Stamen Midge', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Rooted Marlin', 64.93, 154, 7007, 27327, 'Vine Leech', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Canopy Pitcher Coelacanth', 68.8, 187, 7546, 36975, 'Dew Shrimp', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Stamen Nectar Minnow', 72.67, 223, 8085, 19404, 'Pitcher Larva', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Petal Bramble Smelt', 76.54, 262, 8624, 29322, 'Briar Beetle', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Verdant-Pod Chub', 80.41, 303, 9163, 40317, 'Frond Worm', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Pitcher Carp', 84.28, 170, 9702, 52391, 'Nectar Moth', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Thorned Spine Gar', 88.15, 209, 10241, 29699, 'Pollen Worm', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Nectar Bud Grouper', 92.02, 250, 10780, 42042, 'Sap Beetle', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Vinebound Flytrap Ray', 95.89, 294, 11319, 55463, 'Leafhopper', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Sporelit Vine Barracuda', 99.76, 341, 11858, 28459, 'Bog Cricket', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'mythic', 'Sapgreen Marlin', 104, 391, 12397, 42150, 'Root Grub', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Bloomfang-Pod Snapper', 103, 356, 13662, 53282, 'Thorn Fly', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Trapleaf Calyx Sturgeon', 112, 423, 15180, 74382, 'Petal Nymph', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Pollen Spine Arowana', 120, 244, 16698, 40075, 'Stamen Midge', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Rooted Salmon', 128, 305, 18216, 61934, 'Vine Leech', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Canopy Flytrap Shark', 136, 372, 19734, 86830, 'Dew Shrimp', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Stamen Vine Leviathan', 144, 445, 21252, 114761, 'Pitcher Larva', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Petal Anther Loach', 152, 523, 22770, 66033, 'Briar Beetle', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Verdant-Tendril Shiner', 160, 607, 24288, 94723, 'Frond Worm', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Pitcher Bream', 168, 343, 25806, 126449, 'Nectar Moth', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Thorned Root Pike', 176, 422, 27324, 65578, 'Pollen Worm', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Nectar Frond Snapper', 184, 506, 28842, 98063, 'Sap Beetle', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Vinebound Stalk Sturgeon', 193, 595, 30360, 133584, 'Leafhopper', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Sporelit Pitcher Arowana', 201, 690, 31878, 172141, 'Bog Cricket', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Sapgreen Salmon', 209, 791, 33396, 96848, 'Root Grub', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'ascendant', 'Briar-Bramble Shark', 217, 442, 34914, 136165, 'Spore Fry', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Trapleaf Sepal Eel', 218, 832, 38610, 169884, 'Petal Nymph', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Pollen Root Manta', 236, 485, 42900, 231660, 'Stamen Midge', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Rooted Mackerel', 253, 609, 47190, 136851, 'Vine Leech', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Canopy Stalk Swordfish', 270, 745, 51480, 200772, 'Dew Shrimp', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Stamen Pitcher Tuna', 287, 892, 55770, 273273, 'Pitcher Larva', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Petal Nectar Guppy', 304, 1052, 60060, 144144, 'Briar Beetle', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Verdant-Bramble Darter', 321, 1223, 64350, 218790, 'Frond Worm', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Pitcher Perch', 338, 697, 68640, 302016, 'Nectar Moth', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Thorned Calyx Trout', 355, 856, 72930, 393822, 'Pollen Worm', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Nectar Spine Catfish', 372, 1028, 77220, 223938, 'Sap Beetle', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Vinebound Bud Eel', 389, 1211, 81510, 317889, 'Leafhopper', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Sporelit Flytrap Manta', 407, 1407, 85800, 420420, 'Bog Cricket', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Sapgreen Mackerel', 424, 1614, 90090, 216216, 'Root Grub', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Briar-Anther Swordfish', 441, 908, 94380, 320892, 'Spore Fry', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'celestial', 'Bloomfang Tendril Tuna', 458, 1104, 98670, 434148, 'Thorn Fly', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Pollen Calyx Ray', 460, 957, 108900, 533610, 'Stamen Midge', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Rooted Barracuda', 496, 1205, 121000, 290400, 'Vine Leech', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Canopy Bud Marlin', 532, 1479, 133100, 452540, 'Dew Shrimp', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Stamen Flytrap Coelacanth', 568, 1778, 145200, 638880, 'Pitcher Larva', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Petal Vine Minnow', 604, 2102, 157300, 849420, 'Briar Beetle', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Verdant-Anther Smelt', 640, 2451, 169400, 491260, 'Frond Worm', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Pitcher Chub', 676, 1406, 181500, 707850, 'Nectar Moth', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Thorned Sepal Carp', 712, 1730, 193600, 948640, 'Pollen Worm', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Nectar Root Gar', 748, 2079, 205700, 493680, 'Sap Beetle', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Vinebound Frond Grouper', 784, 2454, 217800, 740520, 'Leafhopper', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Sporelit Stalk Ray', 820, 2854, 229900, 1011560, 'Bog Cricket', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Sapgreen Barracuda', 856, 3278, 242000, 1306800, 'Root Grub', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Briar-Nectar Marlin', 892, 1855, 254100, 736890, 'Spore Fry', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Bloomfang Bramble Coelacanth', 928, 2255, 266200, 1038180, 'Thorn Fly', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eldritch', 'Trapleaf Pod Minnow', 964, 2680, 278300, 1363670, 'Petal Nymph', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Rooted Arowana', 977, 2395, 306900, 1657260, 'Vine Leech', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Canopy Frond Salmon', 1054, 2951, 341000, 988900, 'Dew Shrimp', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Stamen Stalk Shark', 1131, 3561, 375100, 1462890, 'Pitcher Larva', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Petal Pitcher Leviathan', 1207, 4225, 409200, 2005080, 'Briar Beetle', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Verdant-Nectar Loach', 1283, 4941, 443300, 1063920, 'Frond Worm', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Pitcher Shiner', 1360, 2856, 477400, 1623160, 'Nectar Moth', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Thorned Pod Bream', 1437, 3519, 511500, 2250600, 'Pollen Worm', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Nectar Calyx Pike', 1513, 4236, 545600, 2946240, 'Sap Beetle', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Vinebound Spine Snapper', 1590, 5007, 579700, 1681130, 'Leafhopper', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Sporelit Bud Sturgeon', 1666, 5831, 613800, 2393820, 'Bog Cricket', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Sapgreen Arowana', 1742, 6709, 647900, 3174710, 'Root Grub', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Briar-Vine Salmon', 1819, 3820, 682000, 1636800, 'Spore Fry', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Bloomfang Anther Shark', 1896, 4644, 716100, 2434740, 'Thorn Fly', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Trapleaf Tendril Leviathan', 1972, 5522, 750200, 3300880, 'Petal Nymph', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'eternal', 'Pollen Sepal Loach', 2048, 6453, 784300, 4235220, 'Stamen Midge', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Canopy Spine Mackerel', 2070, 5837, 871200, 2090880, 'Dew Shrimp', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Stamen Bud Swordfish', 2232, 7075, 968000, 3291200, 'Pitcher Larva', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Petal Flytrap Tuna', 2394, 8427, 1064800, 4685120, 'Briar Beetle', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Verdant-Vine Guppy', 2556, 9892, 1161600, 6272640, 'Frond Worm', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Pitcher Darter', 2718, 5762, 1258400, 3649360, 'Nectar Moth', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Thorned Tendril Perch', 2880, 7114, 1355200, 5285280, 'Pollen Worm', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Nectar Sepal Trout', 3042, 8578, 1452000, 7114800, 'Sap Beetle', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Vinebound Root Catfish', 3204, 10157, 1548800, 3717120, 'Leafhopper', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Sporelit Frond Eel', 3366, 11848, 1645600, 5595040, 'Bog Cricket', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Sapgreen Manta', 3528, 13653, 1742400, 7666560, 'Root Grub', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Briar-Pitcher Mackerel', 3690, 7823, 1839200, 9931680, 'Spore Fry', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Bloomfang Nectar Swordfish', 3852, 9514, 1936000, 5614400, 'Thorn Fly', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Trapleaf Bramble Tuna', 4014, 11319, 2032800, 7927920, 'Petal Nymph', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Pollen Pod Guppy', 4176, 13238, 2129600, 10435040, 'Stamen Midge', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'divine', 'Rooted Darter', 4338, 15270, 2226400, 5343360, 'Vine Leech', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Stamen Frond Marlin', 4485, 14307, 2475000, 7177500, 'Pitcher Larva', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Petal Stalk Coelacanth', 4836, 17119, 2750000, 10725000, 'Briar Beetle', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Verdant-Pitcher Minnow', 5187, 20177, 3025000, 14822500, 'Frond Worm', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Pitcher Smelt', 5538, 11851, 3300000, 7920000, 'Nectar Moth', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Thorned Bramble Chub', 5889, 14664, 3575000, 12155000, 'Pollen Worm', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Nectar Pod Carp', 6240, 17722, 3850000, 16940000, 'Sap Beetle', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Vinebound Calyx Gar', 6591, 21025, 4125000, 22275000, 'Leafhopper', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Sporelit Spine Grouper', 6942, 24575, 4400000, 12760000, 'Bog Cricket', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Sapgreen Ray', 7293, 28370, 4675000, 18232500, 'Root Grub', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Briar-Flytrap Barracuda', 7644, 16358, 4950000, 24255000, 'Spore Fry', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Bloomfang Vine Marlin', 7995, 19908, 5225000, 12540000, 'Thorn Fly', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Trapleaf Anther Coelacanth', 8346, 23703, 5500000, 18700000, 'Petal Nymph', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Pollen Tendril Minnow', 8697, 27743, 5775000, 25410000, 'Stamen Midge', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Rooted Smelt', 9048, 32030, 6050000, 32670000, 'Vine Leech', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'cosmic', 'Canopy Root Chub', 9399, 36562, 6325000, 18342500, 'Dew Shrimp', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Petal Bud Shark', 9660, 34390, 7029000, 23898600, 'Briar Beetle', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Verdant-Flytrap Leviathan', 10416, 40727, 7810000, 34364000, 'Frond Worm', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Pitcher Loach', 11172, 24132, 8591000, 46391400, 'Nectar Moth', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Thorned Anther Shiner', 11928, 29939, 9372000, 27178800, 'Pollen Worm', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Nectar Tendril Bream', 12684, 36276, 10153000, 39596700, 'Sap Beetle', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Vinebound Sepal Pike', 13440, 43142, 10934000, 53576600, 'Leafhopper', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Sporelit Root Snapper', 14196, 50538, 11715000, 28116000, 'Bog Cricket', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Sapgreen Sturgeon', 14952, 58462, 12496000, 42486400, 'Root Grub', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Briar-Stalk Arowana', 15708, 33929, 13277000, 58418800, 'Spore Fry', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Bloomfang Pitcher Salmon', 16464, 41325, 14058000, 75913200, 'Thorn Fly', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Trapleaf Nectar Shark', 17220, 49249, 14839000, 43033100, 'Petal Nymph', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Pollen Bramble Leviathan', 17976, 57703, 15620000, 60918000, 'Stamen Midge', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Rooted Loach', 18732, 66686, 16401000, 80364900, 'Vine Leech', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Canopy Calyx Shiner', 19488, 76198, 17182000, 41236800, 'Dew Shrimp', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'primordial', 'Stamen Spine Bream', 20244, 43727, 17963000, 61074200, 'Pitcher Larva', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Verdant-Stalk Tuna', 20700, 81351, 19800000, 77220000, 'Frond Worm', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Pitcher Guppy', 22320, 48658, 22000000, 107800000, 'Nectar Moth', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Thorned Nectar Darter', 23940, 60568, 24200000, 58080000, 'Pollen Worm', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Nectar Bramble Perch', 25560, 73613, 26400000, 89760000, 'Sap Beetle', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Vinebound Pod Trout', 27180, 87791, 28600000, 125840000, 'Leafhopper', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Sporelit Calyx Catfish', 28800, 103104, 30800000, 166320000, 'Bog Cricket', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Sapgreen Eel', 30420, 119551, 33000000, 95700000, 'Root Grub', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Briar-Bud Manta', 32040, 69847, 35200000, 137280000, 'Spore Fry', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Bloomfang Flytrap Mackerel', 33660, 85160, 37400000, 183260000, 'Thorn Fly', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Trapleaf Vine Swordfish', 35280, 101606, 39600000, 95040000, 'Petal Nymph', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Pollen Anther Tuna', 36900, 119187, 41800000, 142120000, 'Stamen Midge', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Rooted Guppy', 38520, 137902, 44000000, 193600000, 'Vine Leech', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Canopy Sepal Darter', 40140, 157750, 46200000, 249480000, 'Dew Shrimp', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Stamen Root Perch', 41760, 91037, 48400000, 140360000, 'Pitcher Larva', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'transcendent', 'Petal-Frond Trout', 43380, 109751, 50600000, 197340000, 'Briar Beetle', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Pitcher Minnow', 44850, 98670, 55440000, 243936000, 'Nectar Moth', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Thorned Vine Smelt', 48360, 123318, 61600000, 332640000, 'Pollen Worm', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Nectar Anther Chub', 51870, 150423, 67760000, 196504000, 'Sap Beetle', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Vinebound Tendril Carp', 55380, 179985, 73920000, 288288000, 'Leafhopper', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Sporelit Sepal Gar', 58890, 212004, 80080000, 392392000, 'Bog Cricket', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Sapgreen Grouper', 62400, 246480, 86240000, 206976000, 'Root Grub', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Briar-Frond Ray', 65910, 145002, 92400000, 314160000, 'Spore Fry', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Bloomfang Stalk Barracuda', 69420, 177021, 98560000, 433664000, 'Thorn Fly', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Trapleaf Pitcher Marlin', 72930, 211497, 104720000, 565488000, 'Petal Nymph', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Pollen Nectar Coelacanth', 76440, 248430, 110880000, 321552000, 'Stamen Midge', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Rooted Minnow', 79950, 287820, 117040000, 456456000, 'Vine Leech', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Canopy Pod Smelt', 83460, 329667, 123200000, 603680000, 'Dew Shrimp', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Stamen Calyx Chub', 86970, 191334, 129360000, 310464000, 'Pitcher Larva', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Petal-Spine Carp', 90480, 230724, 135520000, 460768000, 'Briar Beetle', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'apotheosis', 'Verdant Bud Gar', 93990, 272571, 141680000, 623392000, 'Frond Worm', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Thorned Pitcher Loach', 96600, 248262, 158400000, 776160000, 'Pollen Worm', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Nectar Shiner', 104160, 304147, 176000000, 422400000, 'Sap Beetle', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Vinebound Bramble Bream', 111720, 365324, 193600000, 658240000, 'Leafhopper', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Sporelit Pod Pike', 119280, 431794, 211200000, 929280000, 'Bog Cricket', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Sapgreen Snapper', 126840, 503555, 228800000, 1235520000, 'Root Grub', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Briar-Spine Sturgeon', 134400, 298368, 246400000, 714560000, 'Spore Fry', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Bloomfang Bud Arowana', 141960, 364837, 264000000, 1029600000, 'Thorn Fly', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Trapleaf Flytrap Salmon', 149520, 436598, 281600000, 1379840000, 'Petal Nymph', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Pollen Vine Shark', 157080, 513652, 299200000, 718080000, 'Stamen Midge', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Rooted Leviathan', 164640, 595997, 316800000, 1077120000, 'Vine Leech', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Canopy Tendril Loach', 172200, 683634, 334400000, 1471360000, 'Dew Shrimp', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Stamen Sepal Shiner', 179760, 399067, 352000000, 1900800000, 'Pitcher Larva', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Petal-Root Bream', 187320, 481412, 369600000, 1071840000, 'Briar Beetle', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Verdant Frond Pike', 194880, 569050, 387200000, 1510080000, 'Frond Worm', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'absolute', 'Pitcher Snapper', 202440, 661979, 404800000, 1983520000, 'Nectar Moth', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Nectar Vine Darter', 207000, 608580, 445500000, 2405700000, 'Sap Beetle', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Vinebound Anther Perch', 223200, 734328, 495000000, 1435500000, 'Leafhopper', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Sporelit Tendril Trout', 239400, 871416, 544500000, 2123550000, 'Bog Cricket', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Sapgreen Catfish', 255600, 1019844, 594000000, 2910600000, 'Root Grub', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Briar-Root Eel', 271800, 608832, 643500000, 1544400000, 'Spore Fry', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Bloomfang Frond Manta', 288000, 745920, 693000000, 2356200000, 'Thorn Fly', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Trapleaf Stalk Mackerel', 304200, 894348, 742500000, 3267000000, 'Petal Nymph', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Pollen Pitcher Swordfish', 320400, 1054116, 792000000, 4276800000, 'Stamen Midge', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Rooted Tuna', 336600, 1225224, 841500000, 2440350000, 'Vine Leech', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Canopy Bramble Guppy', 352800, 1407672, 891000000, 3474900000, 'Dew Shrimp', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Stamen Pod Darter', 369000, 826560, 940500000, 4608450000, 'Pitcher Larva', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Petal-Calyx Perch', 385200, 997668, 990000000, 2376000000, 'Briar Beetle', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Verdant Spine Trout', 401400, 1180116, 1039500000, 3534300000, 'Frond Worm', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Pitcher Catfish', 417600, 1373904, 1089000000, 4791600000, 'Nectar Moth', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'singularity', 'Thorned Flytrap Eel', 433800, 1579032, 1138500000, 6147900000, 'Pollen Worm', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Vinebound Nectar Chub', 448500, 1484535, 1287000000, 3088800000, 'Leafhopper', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Sporelit Bramble Carp', 483600, 1769976, 1430000000, 4862000000, 'Bog Cricket', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Sapgreen Gar', 518700, 2079987, 1573000000, 6921200000, 'Root Grub', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Briar-Calyx Grouper', 553800, 1251588, 1716000000, 9266400000, 'Spore Fry', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Bloomfang Spine Ray', 588900, 1537029, 1859000000, 5391100000, 'Thorn Fly', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Trapleaf Bud Barracuda', 624000, 1847040, 2002000000, 7807800000, 'Petal Nymph', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Pollen Flytrap Marlin', 659100, 2181621, 2145000000, 10510500000, 'Stamen Midge', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Rooted Coelacanth', 694200, 2540772, 2288000000, 5491200000, 'Vine Leech', 'Can weave through thorn mazes unharmed.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Canopy Anther Minnow', 729300, 2924493, 2431000000, 8265400000, 'Dew Shrimp', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Stamen Tendril Smelt', 764400, 1727544, 2574000000, 11325600000, 'Pitcher Larva', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Petal-Sepal Chub', 799500, 2086695, 2717000000, 14671800000, 'Briar Beetle', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Verdant Root Carp', 834600, 2470416, 2860000000, 8294000000, 'Frond Worm', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Pitcher Gar', 869700, 2878707, 3003000000, 11711700000, 'Nectar Moth', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Thorned Stalk Grouper', 904800, 3311568, 3146000000, 15415400000, 'Pollen Worm', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'paradox', 'Nectar Pitcher Ray', 939900, 3768999, 3289000000, 7893600000, 'Sap Beetle', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Sporelit Anther Bream', 966000, 3554880, 3663000000, 10622700000, 'Bog Cricket', 'Burrows near fibrous root mats.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Sapgreen Pike', 1041600, 4197648, 4070000000, 15873000000, 'Root Grub', 'Stores sugars in gelatinous liver tissue.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Briar-Sepal Snapper', 1117200, 2547216, 4477000000, 21937300000, 'Spore Fry', 'Spawns in warm pollen eddies.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Bloomfang Root Sturgeon', 1192800, 3137064, 4884000000, 11721600000, 'Thorn Fly', 'Can cling to vertical vine walls.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Trapleaf Frond Arowana', 1268400, 3779832, 5291000000, 17989400000, 'Petal Nymph', 'Shrugs off mild digestive enzymes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Pollen Stalk Salmon', 1344000, 4475520, 5698000000, 25071200000, 'Stamen Midge', 'Often follows giant pollinator shadows.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Rooted Shark', 1419600, 5224128, 6105000000, 32967000000, 'Vine Leech', 'Thrives in acidic pitcher pools.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Canopy Nectar Leviathan', 1495200, 6025656, 6512000000, 18884800000, 'Dew Shrimp', 'Lures prey with floral pheromone bursts.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Stamen Bramble Loach', 1570800, 3581424, 6919000000, 26984100000, 'Pitcher Larva', 'Feeds aggressively at dusk bloom.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Petal-Pod Shiner', 1646400, 4330032, 7326000000, 35897400000, 'Briar Beetle', 'Uses tendrils as temporary cover.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Verdant Calyx Bream', 1722000, 5131560, 7733000000, 18559200000, 'Frond Worm', 'Bites hardest after monsoon humidity spikes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Pitcher Pike', 1797600, 5986008, 8140000000, 27676000000, 'Nectar Moth', 'Camouflages as drifting petals.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Thorned Bud Snapper', 1873200, 6893376, 8547000000, 37606800000, 'Pollen Worm', 'Tracks vibration through leaf membranes.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Nectar Flytrap Sturgeon', 1948800, 7853664, 8954000000, 48351600000, 'Sap Beetle', 'Hunts insects trapped on nectar slicks.'),
  ('carnivorous_canopy', 'Carnivorous Canopy', 'null', 'Vinebound Vine Arowana', 2024400, 4615632, 9361000000, 27146900000, 'Leafhopper', 'Can weave through thorn mazes unharmed.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Qubit Minnow', 0.18, 0.59, 8.56, 37.66, 'Muon Midge', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Phase Wave Smelt', 0.19, 0.71, 9.44, 50.98, 'Qubit Worm', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Entangled Orbit Chub', 0.21, 0.39, 10.32, 29.93, 'Photon Fry', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Probabilistic Vector Carp', 0.22, 0.5, 11.2, 43.68, 'Neutrino Gnat', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Waveform Node Gar', 0.23, 0.61, 12.08, 59.19, 'Boson Beetle', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Planck Grouper', 0.25, 0.73, 12.96, 31.1, 'Spin Larva', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Boson Interference Ray', 0.26, 0.86, 13.84, 47.06, 'Phase Nymph', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Neutrino-Cascade Barracuda', 0.27, 1, 14.72, 64.77, 'Wave Shrimp', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Spin Collapse Marlin', 0.29, 0.55, 15.6, 84.24, 'Entangle Roe', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Tunneling Eigen Coelacanth', 0.3, 0.68, 16.48, 47.79, 'Orbit Grub', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Superposed Minnow', 0.32, 0.82, 17.36, 67.7, 'Planck Fly', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Relativistic Singlet Smelt', 0.33, 0.97, 18.24, 89.38, 'Flux Worm', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Uncertain Lattice Chub', 0.34, 1.13, 19.12, 45.89, 'Parity Midge', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Coherent Horizon Carp', 0.36, 1.3, 20, 68, 'Tunnel Shrimp', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'common', 'Decoherent-Duality Gar', 0.37, 0.7, 20.88, 91.87, 'Vector Fry', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Phase Collapse Loach', 0.66, 2.42, 23.54, 115, 'Qubit Worm', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Entangled Eigen Shiner', 0.71, 1.36, 25.96, 62.3, 'Photon Fry', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Probabilistic Parity Bream', 0.76, 1.72, 28.38, 96.49, 'Neutrino Gnat', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Waveform Singlet Pike', 0.81, 2.12, 30.8, 136, 'Boson Beetle', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Planck Snapper', 0.86, 2.55, 33.22, 179, 'Spin Larva', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Boson Horizon Sturgeon', 0.91, 3.01, 35.64, 103, 'Phase Nymph', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Neutrino-Duality Arowana', 0.96, 3.51, 38.06, 148, 'Wave Shrimp', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Spin State Salmon', 1.01, 1.93, 40.48, 198, 'Entangle Roe', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Tunneling Wave Shark', 1.06, 2.4, 42.9, 103, 'Orbit Grub', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Superposed Leviathan', 1.11, 2.9, 45.32, 154, 'Planck Fly', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Relativistic Vector Loach', 1.16, 3.43, 47.74, 210, 'Flux Worm', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Uncertain Node Shiner', 1.2, 4, 50.16, 271, 'Parity Midge', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Coherent Flux Bream', 1.25, 4.6, 52.58, 152, 'Tunnel Shrimp', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Decoherent-Interference Pike', 1.3, 2.5, 55, 214, 'Vector Fry', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'uncommon', 'Qubit Snapper', 1.35, 3.07, 57.42, 281, 'Muon Midge', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Entangled Wave Darter', 1.68, 3.26, 74.9, 404, 'Photon Fry', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Probabilistic Orbit Perch', 1.81, 4.14, 82.6, 240, 'Neutrino Gnat', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Waveform Vector Trout', 1.93, 5.1, 90.3, 352, 'Boson Beetle', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Planck Catfish', 2.06, 6.15, 98, 480, 'Spin Larva', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Boson Flux Eel', 2.18, 7.29, 106, 254, 'Phase Nymph', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Neutrino-Interference Manta', 2.31, 8.52, 113, 386, 'Wave Shrimp', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Spin Cascade Mackerel', 2.44, 4.73, 121, 533, 'Entangle Roe', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Tunneling Collapse Swordfish', 2.56, 5.87, 129, 696, 'Orbit Grub', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Superposed Tuna', 2.69, 7.1, 137, 396, 'Planck Fly', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Relativistic Parity Guppy', 2.81, 8.41, 144, 562, 'Flux Worm', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Uncertain Singlet Darter', 2.94, 9.82, 152, 744, 'Parity Midge', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Coherent Lattice Perch', 3.07, 11.31, 160, 383, 'Tunnel Shrimp', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Decoherent-Horizon Trout', 3.19, 6.19, 167, 569, 'Vector Fry', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Qubit Catfish', 3.32, 7.6, 175, 770, 'Muon Midge', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'rare', 'Phase State Eel', 3.44, 9.09, 183, 987, 'Qubit Worm', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Probabilistic Eigen Chub', 4.56, 10.53, 225, 539, 'Neutrino Gnat', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Waveform Parity Carp', 4.9, 13.04, 248, 843, 'Boson Beetle', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Planck Gar', 5.24, 15.78, 271, 1192, 'Spin Larva', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Boson Lattice Grouper', 5.59, 18.77, 294, 1588, 'Phase Nymph', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Neutrino-Horizon Ray', 5.93, 21.99, 317, 920, 'Wave Shrimp', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Spin Duality Barracuda', 6.27, 12.29, 340, 1327, 'Entangle Roe', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Tunneling State Marlin', 6.61, 15.27, 363, 1780, 'Orbit Grub', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Superposed Coelacanth', 6.95, 18.5, 386, 927, 'Planck Fly', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Relativistic Orbit Minnow', 7.3, 21.96, 410, 1392, 'Flux Worm', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Uncertain Vector Smelt', 7.64, 25.66, 433, 1903, 'Parity Midge', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Coherent Node Chub', 7.98, 29.61, 456, 2461, 'Tunnel Shrimp', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Decoherent-Flux Carp', 8.32, 16.31, 479, 1389, 'Vector Fry', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Qubit Gar', 8.66, 20.01, 502, 1957, 'Muon Midge', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Phase Cascade Grouper', 9.01, 23.96, 525, 2572, 'Qubit Worm', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'epic', 'Entangled Collapse Ray', 9.35, 28.14, 548, 1315, 'Photon Fry', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Waveform Orbit Bream', 11.4, 30.55, 663, 1924, 'Boson Beetle', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Planck Pike', 12.26, 37.13, 732, 2853, 'Spin Larva', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Boson Node Snapper', 13.11, 44.31, 800, 3919, 'Phase Nymph', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Neutrino-Flux Sturgeon', 13.97, 52.09, 868, 2083, 'Wave Shrimp', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Spin Interference Arowana', 14.82, 29.34, 936, 3183, 'Entangle Roe', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Tunneling Cascade Salmon', 15.68, 36.52, 1004, 4419, 'Orbit Grub', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Superposed Shark', 16.53, 44.3, 1073, 5792, 'Planck Fly', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Relativistic Eigen Leviathan', 17.38, 52.68, 1141, 3308, 'Flux Worm', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Uncertain Parity Loach', 18.24, 61.65, 1209, 4715, 'Parity Midge', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Coherent Singlet Shiner', 19.1, 71.22, 1277, 6258, 'Tunnel Shrimp', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Decoherent-Lattice Bream', 19.95, 39.5, 1345, 3229, 'Vector Fry', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Qubit Pike', 20.81, 48.48, 1414, 4806, 'Muon Midge', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Phase Duality Snapper', 21.66, 58.05, 1482, 6520, 'Qubit Worm', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Entangled State Sturgeon', 22.52, 68.22, 1550, 8370, 'Photon Fry', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'legendary', 'Probabilistic Wave Arowana', 23.37, 78.99, 1618, 4693, 'Neutrino Gnat', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Planck Trout', 24, 73.2, 1873, 6367, 'Spin Larva', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Boson Singlet Catfish', 25.8, 87.72, 2065, 9086, 'Phase Nymph', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Neutrino-Lattice Eel', 27.6, 103, 2258, 12191, 'Wave Shrimp', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Spin Horizon Manta', 29.4, 58.8, 2450, 7105, 'Entangle Roe', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Tunneling Duality Mackerel', 31.2, 73.32, 2643, 10306, 'Orbit Grub', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Superposed Swordfish', 33, 89.1, 2835, 13892, 'Planck Fly', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Relativistic Wave Tuna', 34.8, 106, 3028, 7266, 'Flux Worm', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Uncertain Orbit Guppy', 36.6, 124, 3220, 10948, 'Parity Midge', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Coherent Vector Darter', 38.4, 144, 3413, 15015, 'Tunnel Shrimp', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Decoherent-Node Perch', 40.2, 80.4, 3605, 19467, 'Vector Fry', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Qubit Trout', 42, 98.7, 3798, 11013, 'Muon Midge', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Phase Interference Catfish', 43.8, 118, 3990, 15561, 'Qubit Worm', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Entangled Cascade Eel', 45.6, 139, 4183, 20494, 'Photon Fry', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Probabilistic Collapse Manta', 47.4, 161, 4375, 10500, 'Neutrino Gnat', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'liminal', 'Waveform Eigen Mackerel', 49.2, 185, 4568, 15530, 'Boson Beetle', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Boson Vector Gar', 51.6, 176, 5243, 20448, 'Phase Nymph', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Neutrino-Node Grouper', 55.47, 209, 5782, 28332, 'Wave Shrimp', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Spin Flux Ray', 59.34, 120, 6321, 15170, 'Entangle Roe', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Tunneling Interference Barracuda', 63.21, 150, 6860, 23324, 'Orbit Grub', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Superposed Marlin', 67.08, 182, 7399, 32556, 'Planck Fly', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Relativistic Collapse Coelacanth', 70.95, 218, 7938, 42865, 'Flux Worm', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Uncertain Eigen Minnow', 74.82, 256, 8477, 24583, 'Parity Midge', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Coherent Parity Smelt', 78.69, 297, 9016, 35162, 'Tunnel Shrimp', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Decoherent-Singlet Chub', 82.56, 167, 9555, 46820, 'Vector Fry', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Qubit Carp', 86.43, 205, 10094, 24226, 'Muon Midge', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Phase Horizon Gar', 90.3, 246, 10633, 36152, 'Qubit Worm', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Entangled Duality Grouper', 94.17, 289, 11172, 49157, 'Photon Fry', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Probabilistic State Ray', 98.04, 335, 11711, 63239, 'Neutrino Gnat', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Waveform Wave Barracuda', 102, 384, 12250, 35525, 'Boson Beetle', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'mythic', 'Planck Marlin', 106, 214, 12789, 49877, 'Spin Larva', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Neutrino-Singlet Snapper', 108, 409, 14766, 64970, 'Wave Shrimp', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Spin Lattice Sturgeon', 116, 237, 16284, 87934, 'Entangle Roe', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Tunneling Horizon Arowana', 124, 297, 17802, 51626, 'Orbit Grub', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Superposed Salmon', 132, 363, 19320, 75348, 'Planck Fly', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Relativistic State Shark', 140, 434, 20838, 102106, 'Flux Worm', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Uncertain Wave Leviathan', 149, 511, 22356, 53654, 'Parity Midge', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Coherent Orbit Loach', 157, 594, 23874, 81172, 'Tunnel Shrimp', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Decoherent-Vector Shiner', 165, 336, 25392, 111725, 'Vector Fry', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Qubit Bream', 173, 413, 26910, 145314, 'Muon Midge', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Phase Flux Pike', 181, 496, 28428, 82441, 'Qubit Worm', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Entangled Interference Snapper', 189, 584, 29946, 116789, 'Photon Fry', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Probabilistic Cascade Sturgeon', 197, 678, 31464, 154174, 'Neutrino Gnat', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Waveform Collapse Arowana', 205, 778, 32982, 79157, 'Boson Beetle', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Planck Salmon', 213, 435, 34500, 117300, 'Spin Larva', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'ascendant', 'Boson-Parity Shark', 221, 529, 36018, 158479, 'Phase Nymph', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Spin Node Eel', 228, 470, 41730, 204477, 'Entangle Roe', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Tunneling Flux Manta', 245, 591, 46020, 110448, 'Orbit Grub', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Superposed Mackerel', 262, 724, 50310, 171054, 'Planck Fly', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Relativistic Cascade Swordfish', 279, 869, 54600, 240240, 'Flux Worm', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Uncertain Collapse Tuna', 296, 1026, 58890, 318006, 'Parity Midge', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Coherent Eigen Guppy', 314, 1194, 63180, 183222, 'Tunnel Shrimp', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Decoherent-Parity Darter', 331, 681, 67470, 263133, 'Vector Fry', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Qubit Perch', 348, 838, 71760, 351624, 'Muon Midge', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Phase Lattice Trout', 365, 1007, 76050, 182520, 'Qubit Worm', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Entangled Horizon Catfish', 382, 1188, 80340, 273156, 'Photon Fry', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Probabilistic Duality Eel', 399, 1381, 84630, 372372, 'Neutrino Gnat', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Waveform State Manta', 416, 1585, 88920, 480168, 'Boson Beetle', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Planck Mackerel', 433, 892, 93210, 270309, 'Spin Larva', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Boson-Orbit Swordfish', 450, 1085, 97500, 380250, 'Phase Nymph', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'celestial', 'Neutrino Vector Tuna', 467, 1290, 101790, 498771, 'Wave Shrimp', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Tunneling Lattice Ray', 480, 1166, 117700, 635580, 'Orbit Grub', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Superposed Barracuda', 516, 1434, 129800, 376420, 'Planck Fly', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Relativistic Duality Marlin', 552, 1728, 141900, 553410, 'Flux Worm', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Uncertain State Coelacanth', 588, 2046, 154000, 754600, 'Parity Midge', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Coherent Wave Minnow', 624, 2390, 166100, 398640, 'Tunnel Shrimp', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Decoherent-Orbit Smelt', 660, 1373, 178200, 605880, 'Vector Fry', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Qubit Chub', 696, 1691, 190300, 837320, 'Muon Midge', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Phase Node Carp', 732, 2035, 202400, 1092960, 'Qubit Worm', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Entangled Flux Gar', 768, 2404, 214500, 622050, 'Photon Fry', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Probabilistic Interference Grouper', 804, 2798, 226600, 883740, 'Neutrino Gnat', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Waveform Cascade Ray', 840, 3217, 238700, 1169630, 'Boson Beetle', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Planck Barracuda', 876, 1822, 250800, 601920, 'Spin Larva', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Boson-Eigen Marlin', 912, 2216, 262900, 893860, 'Phase Nymph', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Neutrino Parity Coelacanth', 948, 2635, 275000, 1210000, 'Wave Shrimp', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eldritch', 'Spin Singlet Minnow', 984, 3080, 287100, 1550340, 'Entangle Roe', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Superposed Arowana', 1020, 2856, 331700, 796080, 'Planck Fly', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Relativistic Interference Salmon', 1097, 3454, 365800, 1243720, 'Flux Worm', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Uncertain Cascade Shark', 1173, 4106, 399900, 1759560, 'Parity Midge', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Coherent Collapse Leviathan', 1250, 4811, 434000, 2343600, 'Tunnel Shrimp', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Decoherent-Eigen Loach', 1326, 2785, 468100, 1357490, 'Vector Fry', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Qubit Shiner', 1403, 3436, 502200, 1958580, 'Muon Midge', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Phase Singlet Bream', 1479, 4141, 536300, 2627870, 'Qubit Worm', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Entangled Lattice Pike', 1555, 4900, 570400, 1368960, 'Photon Fry', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Probabilistic Horizon Snapper', 1632, 5712, 604500, 2055300, 'Neutrino Gnat', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Waveform Duality Sturgeon', 1709, 6578, 638600, 2809840, 'Boson Beetle', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Planck Arowana', 1785, 3749, 672700, 3632580, 'Spin Larva', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Boson-Wave Salmon', 1862, 4561, 706800, 2049720, 'Phase Nymph', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Neutrino Orbit Shark', 1938, 5426, 740900, 2889510, 'Wave Shrimp', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Spin Vector Leviathan', 2015, 6346, 775000, 3797500, 'Entangle Roe', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'eternal', 'Tunneling Node Loach', 2091, 7319, 809100, 1941840, 'Orbit Grub', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Relativistic Horizon Mackerel', 2160, 6847, 941600, 2730640, 'Flux Worm', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Uncertain Duality Swordfish', 2322, 8173, 1038400, 4049760, 'Parity Midge', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Coherent State Tuna', 2484, 9613, 1135200, 5562480, 'Tunnel Shrimp', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Decoherent-Wave Guppy', 2646, 5610, 1232000, 2956800, 'Vector Fry', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Qubit Darter', 2808, 6936, 1328800, 4517920, 'Muon Midge', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Phase Vector Perch', 2970, 8375, 1425600, 6272640, 'Qubit Worm', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Entangled Node Trout', 3132, 9928, 1522400, 8220960, 'Photon Fry', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Probabilistic Flux Catfish', 3294, 11595, 1619200, 4695680, 'Neutrino Gnat', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Waveform Interference Eel', 3456, 13375, 1716000, 6692400, 'Boson Beetle', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Planck Manta', 3618, 7670, 1812800, 8882720, 'Spin Larva', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Boson-Collapse Mackerel', 3780, 9337, 1909600, 4583040, 'Phase Nymph', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Neutrino Eigen Swordfish', 3942, 11116, 2006400, 6821760, 'Wave Shrimp', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Spin Parity Tuna', 4104, 13010, 2103200, 9254080, 'Entangle Roe', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Tunneling Singlet Guppy', 4266, 15016, 2200000, 11880000, 'Orbit Grub', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'divine', 'Superposed Darter', 4428, 17136, 2296800, 6660720, 'Planck Fly', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Uncertain Interference Marlin', 4680, 16567, 2675000, 9095000, 'Parity Midge', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Coherent Cascade Coelacanth', 5031, 19571, 2950000, 12980000, 'Tunnel Shrimp', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Decoherent-Collapse Minnow', 5382, 11517, 3225000, 17415000, 'Vector Fry', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Qubit Smelt', 5733, 14275, 3500000, 10150000, 'Muon Midge', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Phase Parity Chub', 6084, 17279, 3775000, 14722500, 'Qubit Worm', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Entangled Singlet Carp', 6435, 20528, 4050000, 19845000, 'Photon Fry', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Probabilistic Lattice Gar', 6786, 24022, 4325000, 10380000, 'Neutrino Gnat', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Waveform Horizon Grouper', 7137, 27763, 4600000, 15640000, 'Boson Beetle', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Planck Ray', 7488, 16024, 4875000, 21450000, 'Spin Larva', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Boson-State Barracuda', 7839, 19519, 5150000, 27810000, 'Phase Nymph', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Neutrino Wave Marlin', 8190, 23260, 5425000, 15732500, 'Wave Shrimp', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Spin Orbit Coelacanth', 8541, 27246, 5700000, 22230000, 'Entangle Roe', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Tunneling Vector Minnow', 8892, 31478, 5975000, 29277500, 'Orbit Grub', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Superposed Smelt', 9243, 35955, 6250000, 15000000, 'Planck Fly', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'cosmic', 'Relativistic Flux Chub', 9594, 20531, 6525000, 22185000, 'Flux Worm', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Coherent Duality Shark', 10080, 39413, 7597000, 29628300, 'Tunnel Shrimp', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Decoherent-State Leviathan', 10836, 23406, 8378000, 41052200, 'Vector Fry', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Qubit Loach', 11592, 29096, 9159000, 21981600, 'Muon Midge', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Phase Orbit Shiner', 12348, 35315, 9940000, 33796000, 'Qubit Worm', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Entangled Vector Bream', 13104, 42064, 10721000, 47172400, 'Photon Fry', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Probabilistic Node Pike', 13860, 49342, 11502000, 62110800, 'Neutrino Gnat', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Waveform Flux Snapper', 14616, 57149, 12283000, 35620700, 'Boson Beetle', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Planck Sturgeon', 15372, 33204, 13064000, 50949600, 'Spin Larva', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Boson-Cascade Arowana', 16128, 40481, 13845000, 67840500, 'Phase Nymph', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Neutrino Collapse Salmon', 16884, 48288, 14626000, 35102400, 'Wave Shrimp', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Spin Eigen Shark', 17640, 56624, 15407000, 52383800, 'Entangle Roe', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Tunneling Parity Leviathan', 18396, 65490, 16188000, 71227200, 'Orbit Grub', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Superposed Loach', 19152, 74884, 16969000, 91632600, 'Planck Fly', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Relativistic Lattice Shiner', 19908, 43001, 17750000, 51475000, 'Flux Worm', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'primordial', 'Uncertain Horizon Bream', 20664, 51867, 18531000, 72270900, 'Parity Midge', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Decoherent-Cascade Tuna', 21600, 47088, 21400000, 94160000, 'Vector Fry', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Qubit Guppy', 23220, 58747, 23600000, 127440000, 'Muon Midge', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Phase Eigen Darter', 24840, 71539, 25800000, 74820000, 'Qubit Worm', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Entangled Parity Perch', 26460, 85466, 28000000, 109200000, 'Photon Fry', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Probabilistic Singlet Trout', 28080, 100526, 30200000, 147980000, 'Neutrino Gnat', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Waveform Lattice Catfish', 29700, 116721, 32400000, 77760000, 'Boson Beetle', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Planck Eel', 31320, 68278, 34600000, 117640000, 'Spin Larva', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Boson-Duality Manta', 32940, 83338, 36800000, 161920000, 'Phase Nymph', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Neutrino State Mackerel', 34560, 99533, 39000000, 210600000, 'Wave Shrimp', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Spin Wave Swordfish', 36180, 116861, 41200000, 119480000, 'Entangle Roe', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Tunneling Orbit Tuna', 37800, 135324, 43400000, 169260000, 'Orbit Grub', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Superposed Guppy', 39420, 154921, 45600000, 223440000, 'Planck Fly', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Relativistic Node Darter', 41040, 89467, 47800000, 114720000, 'Flux Worm', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Uncertain Flux Perch', 42660, 107930, 50000000, 170000000, 'Parity Midge', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'transcendent', 'Coherent-Interference Trout', 44280, 127526, 52200000, 229680000, 'Tunnel Shrimp', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Qubit Minnow', 46800, 119340, 59920000, 293608000, 'Muon Midge', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Phase Wave Smelt', 50310, 145899, 66080000, 158592000, 'Qubit Worm', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Entangled Orbit Chub', 53820, 174915, 72240000, 245616000, 'Photon Fry', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Probabilistic Vector Carp', 57330, 206388, 78400000, 344960000, 'Neutrino Gnat', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Waveform Node Gar', 60840, 240318, 84560000, 456624000, 'Boson Beetle', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Planck Grouper', 64350, 141570, 90720000, 263088000, 'Spin Larva', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Boson-Interference Ray', 67860, 173043, 96880000, 377832000, 'Phase Nymph', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Neutrino Cascade Barracuda', 71370, 206973, 103040000, 504896000, 'Wave Shrimp', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Spin Collapse Marlin', 74880, 243360, 109200000, 262080000, 'Entangle Roe', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Tunneling Eigen Coelacanth', 78390, 282204, 115360000, 392224000, 'Orbit Grub', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Superposed Minnow', 81900, 323505, 121520000, 534688000, 'Planck Fly', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Relativistic Singlet Smelt', 85410, 187902, 127680000, 689472000, 'Flux Worm', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Uncertain Lattice Chub', 88920, 226746, 133840000, 388136000, 'Parity Midge', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Coherent-Horizon Carp', 92430, 268047, 140000000, 546000000, 'Tunnel Shrimp', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'apotheosis', 'Decoherent Duality Gar', 95940, 311805, 146160000, 716184000, 'Vector Fry', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Phase Collapse Loach', 100800, 294336, 171200000, 924480000, 'Qubit Worm', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Entangled Eigen Shiner', 108360, 354337, 188800000, 547520000, 'Photon Fry', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Probabilistic Parity Bream', 115920, 419630, 206400000, 804960000, 'Neutrino Gnat', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Waveform Singlet Pike', 123480, 490216, 224000000, 1097600000, 'Boson Beetle', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Planck Snapper', 131040, 290909, 241600000, 579840000, 'Spin Larva', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Boson-Horizon Sturgeon', 138600, 356202, 259200000, 881280000, 'Phase Nymph', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Neutrino Duality Arowana', 146160, 426787, 276800000, 1217920000, 'Wave Shrimp', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Spin State Salmon', 153720, 502664, 294400000, 1589760000, 'Entangle Roe', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Tunneling Wave Shark', 161280, 583834, 312000000, 904800000, 'Orbit Grub', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Superposed Leviathan', 168840, 670295, 329600000, 1285440000, 'Planck Fly', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Relativistic Vector Loach', 176400, 391608, 347200000, 1701280000, 'Flux Worm', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Uncertain Node Shiner', 183960, 472777, 364800000, 875520000, 'Parity Midge', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Coherent-Flux Bream', 191520, 559238, 382400000, 1300160000, 'Tunnel Shrimp', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Decoherent Interference Pike', 199080, 650992, 400000000, 1760000000, 'Vector Fry', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'absolute', 'Qubit Snapper', 206640, 748037, 417600000, 2255040000, 'Muon Midge', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Entangled Wave Darter', 216000, 710640, 481500000, 1155600000, 'Photon Fry', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Probabilistic Orbit Perch', 232200, 845208, 531000000, 1805400000, 'Neutrino Gnat', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Waveform Vector Trout', 248400, 991116, 580500000, 2554200000, 'Boson Beetle', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Planck Catfish', 264600, 592704, 630000000, 3402000000, 'Spin Larva', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Boson-Flux Eel', 280800, 727272, 679500000, 1970550000, 'Phase Nymph', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Neutrino Interference Manta', 297000, 873180, 729000000, 2843100000, 'Wave Shrimp', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Spin Cascade Mackerel', 313200, 1030428, 778500000, 3814650000, 'Entangle Roe', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Tunneling Collapse Swordfish', 329400, 1199016, 828000000, 1987200000, 'Orbit Grub', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Superposed Tuna', 345600, 1378944, 877500000, 2983500000, 'Planck Fly', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Relativistic Parity Guppy', 361800, 810432, 927000000, 4078800000, 'Flux Worm', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Uncertain Singlet Darter', 378000, 979020, 976500000, 5273100000, 'Parity Midge', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Coherent-Lattice Perch', 394200, 1158948, 1026000000, 2975400000, 'Tunnel Shrimp', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Decoherent Horizon Trout', 410400, 1350216, 1075500000, 4194450000, 'Vector Fry', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Qubit Catfish', 426600, 1552824, 1125000000, 5512500000, 'Muon Midge', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'singularity', 'Phase State Eel', 442800, 1766772, 1174500000, 2818800000, 'Qubit Worm', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Probabilistic Eigen Chub', 468000, 1712880, 1391000000, 4033900000, 'Neutrino Gnat', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Waveform Parity Carp', 503100, 2017431, 1534000000, 5982600000, 'Boson Beetle', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Planck Gar', 538200, 1216332, 1677000000, 8217300000, 'Spin Larva', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Boson-Lattice Grouper', 573300, 1496313, 1820000000, 4368000000, 'Phase Nymph', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Neutrino Horizon Ray', 608400, 1800864, 1963000000, 6674200000, 'Wave Shrimp', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Spin Duality Barracuda', 643500, 2129985, 2106000000, 9266400000, 'Entangle Roe', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Tunneling State Marlin', 678600, 2483676, 2249000000, 12144600000, 'Orbit Grub', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Superposed Coelacanth', 713700, 2861937, 2392000000, 6936800000, 'Planck Fly', 'Can tunnel through thin obstacles.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Relativistic Orbit Minnow', 748800, 1692288, 2535000000, 9886500000, 'Flux Worm', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Uncertain Vector Smelt', 783900, 2045979, 2678000000, 13122200000, 'Parity Midge', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Coherent-Node Chub', 819000, 2424240, 2821000000, 6770400000, 'Tunnel Shrimp', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Decoherent Flux Carp', 854100, 2827071, 2964000000, 10077600000, 'Vector Fry', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Qubit Gar', 889200, 3254472, 3107000000, 13670800000, 'Muon Midge', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Phase Cascade Grouper', 924300, 3706443, 3250000000, 17550000000, 'Qubit Worm', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'paradox', 'Entangled Collapse Ray', 959400, 2168244, 3393000000, 9839700000, 'Photon Fry', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Waveform Orbit Bream', 1008000, 4062240, 3959000000, 13460600000, 'Boson Beetle', 'Emits faint blue Cherenkov streaks.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Planck Pike', 1083600, 2470608, 4366000000, 19210400000, 'Spin Larva', 'Bites spike during decoherence surges.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Boson-Node Snapper', 1159200, 3048696, 4773000000, 25774200000, 'Phase Nymph', 'Can swap position with nearby schoolmates.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Neutrino Flux Sturgeon', 1234800, 3679704, 5180000000, 15022000000, 'Wave Shrimp', 'Fades at the edge of observation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Spin Interference Arowana', 1310400, 4363632, 5587000000, 21789300000, 'Entangle Roe', 'Tailbeats generate interference ripples.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Tunneling Cascade Salmon', 1386000, 5100480, 5994000000, 29370600000, 'Orbit Grub', 'Most stable under constant reel cadence.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Superposed Shark', 1461600, 5890248, 6401000000, 15362400000, 'Planck Fly', 'Hook timing affects final mass outcome.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Relativistic Eigen Leviathan', 1537200, 3504816, 6808000000, 23147200000, 'Flux Worm', 'Schools in synchronized phase shifts.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Uncertain Parity Loach', 1612800, 4241664, 7215000000, 31746000000, 'Parity Midge', 'Momentarily splits into mirrored silhouettes.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Coherent-Singlet Shiner', 1688400, 5031432, 7622000000, 41158800000, 'Tunnel Shrimp', 'Tracks lures by spin orientation.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Decoherent Lattice Bream', 1764000, 5874120, 8029000000, 23284100000, 'Vector Fry', 'Responds strongly to oscillating line tension.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Qubit Pike', 1839600, 6769728, 8436000000, 32900400000, 'Muon Midge', 'Prefers low-noise probabilistic currents.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Phase Duality Snapper', 1915200, 7718256, 8843000000, 43330700000, 'Qubit Worm', 'May reclassify rarity on rare events.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Entangled State Sturgeon', 1990800, 4539024, 9250000000, 22200000000, 'Photon Fry', 'Appears in two lanes before collapse.'),
  ('quantum_superposition_sea', 'Quantum Superposition Sea', 'null', 'Probabilistic Wave Arowana', 2066400, 5434632, 9657000000, 32833800000, 'Neutrino Gnat', 'Can tunnel through thin obstacles.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Matcha Minnow', 0.18, 0.32, 7.38, 16.24, 'Tea Midge', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Jasmine Kettle Loach', 0.2, 0.41, 8.32, 25.97, 'Roast Worm', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Oolong Infusion Darter', 0.21, 0.51, 9.27, 37.45, 'Herbal Nymph', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Roasted Leafdrift Chub', 0.23, 0.63, 10.22, 50.67, 'Bean Grub', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Clover Brewcurrent Bream', 0.24, 0.75, 11.16, 24.55, 'Cinnamon Fly', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Sencha Aroma Trout', 0.26, 0.88, 12.11, 37.77, 'Foam Shrimp', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Amberleaf Gar', 0.27, 1.03, 13.05, 52.72, 'Steam Beetle', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Mocha Teacrest Snapper', 0.29, 0.5, 14, 69.42, 'Spice Roe', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Darjeeling-Dripline Eel', 0.3, 0.63, 14.94, 32.87, 'Leaf Larva', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Hearth Herbal Ray', 0.32, 0.77, 15.89, 49.56, 'Kettle Cricket', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Saffron Warmwater Arowana', 0.33, 0.92, 16.83, 67.99, 'Mint Fry', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Minted Foamline Mackerel', 0.35, 1.08, 17.78, 88.16, 'Clove Worm', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Velvet Marlin', 0.36, 1.25, 18.72, 41.18, 'Syrup Gnat', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Copperkettle Tisane Shark', 0.38, 1.44, 19.67, 61.35, 'Biscuit Crumb', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'common', 'Cinnamon Cafecurrent Tuna', 0.39, 0.69, 20.61, 83.26, 'Mocha Moth', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Jasmine Infusion Smelt', 0.62, 1.31, 21.32, 56.71, 'Roast Worm', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Oolong Leafdrift Shiner', 0.67, 1.65, 24.05, 86.1, 'Herbal Nymph', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Roasted Brewcurrent Perch', 0.73, 2.03, 26.78, 121, 'Bean Grub', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Clover Aroma Carp', 0.78, 2.44, 29.51, 160, 'Cinnamon Fly', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Sencha Emberstream Pike', 0.83, 2.89, 32.24, 85.76, 'Foam Shrimp', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Amberleaf Catfish', 0.88, 3.37, 34.97, 125, 'Steam Beetle', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Mocha Dripline Grouper', 0.94, 1.66, 37.7, 170, 'Spice Roe', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Darjeeling-Herbal Sturgeon', 0.99, 2.09, 40.43, 219, 'Leaf Larva', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Hearth Warmwater Manta', 1.04, 2.56, 43.16, 115, 'Kettle Cricket', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Saffron Foamline Barracuda', 1.09, 3.06, 45.89, 164, 'Mint Fry', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Minted Brisk Salmon', 1.15, 3.6, 48.62, 219, 'Clove Worm', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Velvet Swordfish', 1.2, 4.17, 51.35, 278, 'Syrup Gnat', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Copperkettle Cafecurrent Coelacanth', 1.25, 4.78, 54.08, 144, 'Biscuit Crumb', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Cinnamon Steamfin Leviathan', 1.31, 2.32, 56.81, 203, 'Mocha Moth', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'uncommon', 'Matcha Kettle Guppy', 1.36, 2.87, 59.54, 268, 'Tea Midge', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Oolong Brewcurrent Chub', 1.55, 3.84, 67.24, 210, 'Herbal Nymph', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Roasted Aroma Bream', 1.68, 4.74, 75.85, 306, 'Bean Grub', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Clover Emberstream Trout', 1.81, 5.73, 84.46, 419, 'Cinnamon Fly', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Sencha Teacrest Gar', 1.95, 6.81, 93.07, 205, 'Foam Shrimp', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Amberleaf Snapper', 2.08, 7.98, 102, 317, 'Steam Beetle', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Mocha Herbal Eel', 2.21, 3.98, 110, 446, 'Spice Roe', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Darjeeling-Warmwater Ray', 2.34, 5.01, 119, 590, 'Leaf Larva', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Hearth Foamline Arowana', 2.47, 6.13, 128, 281, 'Kettle Cricket', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Saffron Brisk Mackerel', 2.6, 7.34, 136, 425, 'Mint Fry', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Minted Tisane Marlin', 2.74, 8.64, 145, 585, 'Clove Worm', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Velvet Shark', 2.87, 10.04, 153, 761, 'Syrup Gnat', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Copperkettle Steamfin Tuna', 3, 11.52, 162, 356, 'Biscuit Crumb', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Cinnamon Kettle Minnow', 3.13, 5.64, 171, 532, 'Mocha Moth', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Matcha Infusion Loach', 3.26, 6.98, 179, 724, 'Tea Midge', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'rare', 'Jasmine-Leafdrift Darter', 3.39, 8.42, 188, 931, 'Roast Worm', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Roasted Emberstream Carp', 4.1, 11.66, 205, 734, 'Bean Grub', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Clover Teacrest Pike', 4.45, 14.17, 231, 1041, 'Cinnamon Fly', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Sencha Dripline Catfish', 4.8, 16.91, 258, 1396, 'Foam Shrimp', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Amberleaf Grouper', 5.15, 19.89, 284, 755, 'Steam Beetle', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Mocha Warmwater Sturgeon', 5.49, 10.03, 310, 1110, 'Spice Roe', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Darjeeling-Foamline Manta', 5.84, 12.65, 336, 1513, 'Leaf Larva', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Hearth Brisk Barracuda', 6.19, 15.51, 363, 1965, 'Kettle Cricket', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Saffron Tisane Salmon', 6.54, 18.6, 389, 1034, 'Mint Fry', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Minted Cafecurrent Swordfish', 6.89, 21.94, 415, 1486, 'Clove Worm', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Velvet Coelacanth', 7.24, 25.51, 441, 1986, 'Syrup Gnat', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Copperkettle Kettle Leviathan', 7.59, 29.32, 468, 2534, 'Biscuit Crumb', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Cinnamon Infusion Guppy', 7.93, 14.48, 494, 1313, 'Mocha Moth', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Matcha Leafdrift Smelt', 8.28, 17.93, 520, 1862, 'Tea Midge', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Jasmine-Brewcurrent Shiner', 8.63, 21.62, 546, 2458, 'Roast Worm', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'epic', 'Oolong Aroma Perch', 8.98, 25.55, 573, 3103, 'Herbal Nymph', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Clover Dripline Gar', 10.8, 34.67, 607, 2451, 'Cinnamon Fly', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Sencha Herbal Snapper', 11.72, 41.6, 685, 3395, 'Foam Shrimp', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Amberleaf Eel', 12.64, 49.15, 762, 1677, 'Steam Beetle', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Mocha Foamline Ray', 13.55, 25.07, 840, 2620, 'Spice Roe', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Darjeeling-Brisk Arowana', 14.47, 31.69, 918, 3707, 'Leaf Larva', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Hearth Tisane Mackerel', 15.39, 38.94, 995, 4937, 'Kettle Cricket', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Saffron Cafecurrent Marlin', 16.31, 46.8, 1073, 2361, 'Mint Fry', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Minted Steamfin Shark', 17.23, 55.3, 1151, 3590, 'Clove Worm', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Velvet Tuna', 18.14, 64.41, 1228, 4963, 'Syrup Gnat', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Copperkettle Infusion Minnow', 19.06, 74.15, 1306, 6478, 'Biscuit Crumb', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Cinnamon Leafdrift Loach', 19.98, 36.96, 1384, 3044, 'Mocha Moth', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Matcha Brewcurrent Darter', 20.9, 45.77, 1462, 4560, 'Tea Midge', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Jasmine-Aroma Chub', 21.82, 55.19, 1539, 6218, 'Roast Worm', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Oolong Emberstream Bream', 22.73, 65.25, 1617, 8020, 'Herbal Nymph', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'legendary', 'Roasted Trout', 23.65, 75.92, 1695, 3728, 'Bean Grub', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Sencha Warmwater Grouper', 24, 85.8, 1722, 7749, 'Foam Shrimp', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Amberleaf Sturgeon', 26.04, 102, 1942, 10528, 'Steam Beetle', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Mocha Brisk Manta', 28.08, 52.65, 2163, 5754, 'Spice Roe', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Darjeeling-Tisane Barracuda', 30.12, 66.72, 2384, 8533, 'Leaf Larva', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Hearth Cafecurrent Salmon', 32.16, 82.17, 2604, 11718, 'Kettle Cricket', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Saffron Steamfin Swordfish', 34.2, 99.01, 2825, 15309, 'Mint Fry', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Minted Kettle Coelacanth', 36.24, 117, 3045, 8100, 'Clove Worm', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Velvet Leviathan', 38.28, 137, 3266, 11690, 'Syrup Gnat', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Copperkettle Leafdrift Guppy', 40.32, 158, 3486, 15687, 'Biscuit Crumb', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Cinnamon Brewcurrent Smelt', 42.36, 79.43, 3707, 20089, 'Mocha Moth', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Matcha Aroma Shiner', 44.4, 98.35, 3927, 10446, 'Tea Midge', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Jasmine-Emberstream Perch', 46.44, 119, 4148, 14848, 'Roast Worm', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Oolong Teacrest Carp', 48.48, 140, 4368, 19656, 'Herbal Nymph', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Roasted Pike', 50.52, 163, 4589, 24870, 'Bean Grub', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'liminal', 'Clover Herbal Catfish', 52.56, 188, 4809, 12792, 'Cinnamon Fly', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Amberleaf Ray', 52, 205, 4838, 23996, 'Steam Beetle', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Mocha Tisane Arowana', 56.42, 107, 5458, 12007, 'Spice Roe', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Darjeeling-Cafecurrent Mackerel', 60.84, 136, 6077, 18960, 'Leaf Larva', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Hearth Steamfin Marlin', 65.26, 168, 6697, 27054, 'Kettle Cricket', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Saffron Kettle Shark', 69.68, 203, 7316, 36287, 'Mint Fry', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Minted Infusion Tuna', 74.1, 242, 7936, 17458, 'Clove Worm', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Velvet Minnow', 78.52, 283, 8555, 26692, 'Syrup Gnat', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Copperkettle Brewcurrent Loach', 82.94, 327, 9175, 37065, 'Biscuit Crumb', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Cinnamon Aroma Darter', 87.36, 166, 9794, 48578, 'Mocha Moth', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Matcha Emberstream Chub', 91.78, 206, 10414, 22910, 'Tea Midge', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Jasmine-Teacrest Bream', 96.2, 248, 11033, 34423, 'Roast Worm', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Oolong Dripline Trout', 101, 294, 11653, 47076, 'Herbal Nymph', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Roasted Gar', 105, 342, 12272, 60869, 'Bean Grub', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Clover Warmwater Snapper', 109, 394, 12892, 28361, 'Cinnamon Fly', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'mythic', 'Sencha Foamline Eel', 114, 449, 13511, 42154, 'Foam Shrimp', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Mocha Cafecurrent Barracuda', 112, 216, 13776, 74666, 'Spice Roe', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Darjeeling-Steamfin Salmon', 122, 275, 15540, 41336, 'Leaf Larva', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Hearth Kettle Swordfish', 131, 341, 17304, 61948, 'Kettle Cricket', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Saffron Infusion Coelacanth', 141, 414, 19068, 85806, 'Mint Fry', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Minted Leafdrift Leviathan', 150, 493, 20832, 112909, 'Clove Worm', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Velvet Guppy', 160, 579, 22596, 60105, 'Syrup Gnat', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Copperkettle Aroma Smelt', 169, 671, 24360, 87209, 'Biscuit Crumb', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Cinnamon Emberstream Shiner', 179, 344, 26124, 117558, 'Mocha Moth', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Matcha Teacrest Perch', 188, 426, 27888, 151153, 'Tea Midge', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Jasmine-Dripline Carp', 198, 515, 29652, 78874, 'Roast Worm', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Oolong Herbal Pike', 207, 610, 31416, 112469, 'Herbal Nymph', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Roasted Catfish', 217, 712, 33180, 149310, 'Bean Grub', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Clover Foamline Grouper', 226, 820, 34944, 189396, 'Cinnamon Fly', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Sencha Brisk Sturgeon', 236, 935, 36708, 97643, 'Foam Shrimp', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'ascendant', 'Amberleaf Tisane Manta', 245, 472, 38472, 137730, 'Steam Beetle', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Darjeeling-Kettle Marlin', 235, 538, 38540, 84788, 'Leaf Larva', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Hearth Infusion Shark', 255, 671, 43475, 135642, 'Kettle Cricket', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Saffron Leafdrift Tuna', 275, 817, 48410, 195576, 'Mint Fry', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Minted Brewcurrent Minnow', 295, 976, 53345, 264591, 'Clove Worm', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Velvet Loach', 315, 1149, 58280, 128216, 'Syrup Gnat', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Copperkettle Emberstream Darter', 335, 1336, 63215, 197231, 'Biscuit Crumb', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Cinnamon Teacrest Chub', 355, 692, 68150, 275326, 'Mocha Moth', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Matcha Dripline Bream', 375, 858, 73085, 362502, 'Tea Midge', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Jasmine-Herbal Trout', 395, 1038, 78020, 171644, 'Roast Worm', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Oolong Warmwater Gar', 415, 1232, 82955, 258820, 'Herbal Nymph', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Roasted Snapper', 435, 1439, 87890, 355076, 'Bean Grub', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Clover Brisk Eel', 455, 1660, 92825, 460412, 'Cinnamon Fly', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Sencha Tisane Ray', 475, 1894, 97760, 215072, 'Foam Shrimp', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Amberleaf Cafecurrent Arowana', 495, 965, 102695, 320408, 'Steam Beetle', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'celestial', 'Mocha Steamfin Mackerel', 515, 1179, 107630, 434825, 'Spice Roe', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Hearth Leafdrift Coelacanth', 495, 1314, 108240, 287918, 'Kettle Cricket', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Saffron Brewcurrent Leviathan', 537, 1609, 122100, 437118, 'Mint Fry', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Minted Aroma Guppy', 579, 1931, 135960, 611820, 'Clove Worm', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Velvet Smelt', 621, 2283, 149820, 812024, 'Syrup Gnat', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Copperkettle Teacrest Shiner', 663, 2663, 163680, 435389, 'Biscuit Crumb', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Cinnamon Dripline Perch', 705, 1393, 177540, 635593, 'Mocha Moth', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Matcha Herbal Carp', 747, 1730, 191400, 861300, 'Tea Midge', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Jasmine-Warmwater Pike', 790, 2096, 205260, 1112509, 'Roast Worm', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Oolong Foamline Catfish', 832, 2491, 219120, 582859, 'Herbal Nymph', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Roasted Grouper', 874, 2914, 232980, 834068, 'Bean Grub', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Clover Tisane Sturgeon', 916, 3365, 246840, 1110780, 'Cinnamon Fly', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Sencha Cafecurrent Manta', 958, 3846, 260700, 1412994, 'Foam Shrimp', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Amberleaf Steamfin Barracuda', 1000, 1975, 274560, 730330, 'Steam Beetle', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Mocha Kettle Salmon', 1042, 2412, 288420, 1032544, 'Spice Roe', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'eldritch', 'Darjeeling Infusion Swordfish', 1084, 2878, 302280, 1360260, 'Leaf Larva', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Saffron Aroma Minnow', 1050, 3171, 303400, 946608, 'Mint Fry', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Minted Emberstream Loach', 1139, 3828, 342250, 1382690, 'Clove Worm', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Velvet Darter', 1229, 4545, 381100, 1890256, 'Syrup Gnat', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Copperkettle Dripline Chub', 1318, 5324, 419950, 923890, 'Biscuit Crumb', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Cinnamon Herbal Bream', 1407, 2814, 458800, 1431456, 'Mocha Moth', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Matcha Warmwater Trout', 1496, 3501, 497650, 2010506, 'Tea Midge', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Jasmine-Foamline Gar', 1586, 4249, 536500, 2661040, 'Roast Worm', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Oolong Brisk Snapper', 1675, 5058, 575350, 1265770, 'Herbal Nymph', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Roasted Eel', 1764, 5927, 614200, 1916304, 'Bean Grub', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Clover Cafecurrent Ray', 1853, 6857, 653050, 2638322, 'Cinnamon Fly', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Sencha Steamfin Arowana', 1943, 7848, 691900, 3431824, 'Foam Shrimp', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Amberleaf Kettle Mackerel', 2032, 4064, 730750, 1607650, 'Steam Beetle', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Mocha Infusion Marlin', 2121, 4963, 769600, 2401152, 'Spice Roe', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Darjeeling Leafdrift Shark', 2210, 5923, 808450, 3266138, 'Leaf Larva', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'eternal', 'Hearth Tuna', 2300, 6944, 847300, 4202608, 'Kettle Cricket', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Minted Teacrest Smelt', 2240, 7582, 852800, 3053024, 'Clove Worm', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Velvet Shiner', 2430, 9053, 962000, 4329000, 'Syrup Gnat', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Copperkettle Herbal Perch', 2621, 10654, 1071200, 5805904, 'Biscuit Crumb', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Cinnamon Warmwater Carp', 2811, 5693, 1180400, 3139864, 'Mocha Moth', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Matcha Foamline Pike', 3002, 7099, 1289600, 4616768, 'Tea Midge', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Jasmine-Brisk Catfish', 3192, 8634, 1398800, 6294600, 'Roast Worm', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Oolong Tisane Grouper', 3382, 10299, 1508000, 8173360, 'Herbal Nymph', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Roasted Sturgeon', 3573, 12094, 1617200, 4301752, 'Bean Grub', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Clover Steamfin Manta', 3763, 14018, 1726400, 6180512, 'Cinnamon Fly', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Sencha Kettle Barracuda', 3954, 16071, 1835600, 8260200, 'Foam Shrimp', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Amberleaf Infusion Salmon', 4144, 8392, 1944800, 10540816, 'Steam Beetle', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Mocha Leafdrift Swordfish', 4334, 10251, 2054000, 5463640, 'Spice Roe', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Darjeeling Brewcurrent Coelacanth', 4525, 12240, 2163200, 7744256, 'Leaf Larva', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Hearth Leviathan', 4715, 14358, 2272400, 10225800, 'Kettle Cricket', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'divine', 'Saffron Emberstream Guppy', 4906, 16605, 2381600, 12908272, 'Mint Fry', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Velvet Chub', 4800, 18000, 2394400, 9673376, 'Syrup Gnat', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Copperkettle Warmwater Bream', 5208, 21301, 2701000, 13396960, 'Biscuit Crumb', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Cinnamon Foamline Trout', 5616, 11513, 3007600, 6616720, 'Mocha Moth', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Matcha Brisk Gar', 6024, 14397, 3314200, 10340304, 'Tea Midge', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Jasmine-Tisane Snapper', 6432, 17559, 3620800, 14628032, 'Roast Worm', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Oolong Cafecurrent Eel', 6840, 20999, 3927400, 19479904, 'Herbal Nymph', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Roasted Ray', 7248, 24716, 4234000, 9314800, 'Bean Grub', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Clover Kettle Arowana', 7656, 28710, 4540600, 14166672, 'Cinnamon Fly', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Sencha Infusion Mackerel', 8064, 32982, 4847200, 19582688, 'Foam Shrimp', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Amberleaf Leafdrift Marlin', 8472, 17368, 5153800, 25562848, 'Steam Beetle', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Mocha Brewcurrent Shark', 8880, 21223, 5460400, 12012880, 'Spice Roe', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Darjeeling Aroma Tuna', 9288, 25356, 5767000, 17993040, 'Leaf Larva', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Hearth Minnow', 9696, 29767, 6073600, 24537344, 'Kettle Cricket', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Saffron Teacrest Loach', 10104, 34455, 6380200, 31645792, 'Mint Fry', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'cosmic', 'Minted Dripline Darter', 10512, 39420, 6686800, 14710960, 'Clove Worm', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Copperkettle Foamline Carp', 10200, 41973, 6740400, 30331800, 'Biscuit Crumb', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Cinnamon Brisk Pike', 11067, 22964, 7603500, 41210970, 'Mocha Moth', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Matcha Tisane Catfish', 11934, 28821, 8466600, 22521156, 'Tea Midge', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Jasmine-Cafecurrent Grouper', 12801, 35267, 9329700, 33400326, 'Roast Worm', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Oolong Steamfin Sturgeon', 13668, 42302, 10192800, 45867600, 'Herbal Nymph', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Roasted Manta', 14535, 49928, 11055900, 59922978, 'Bean Grub', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Clover Infusion Barracuda', 15402, 58143, 11919000, 31704540, 'Cinnamon Fly', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Sencha Leafdrift Salmon', 16269, 66947, 12782100, 45759918, 'Foam Shrimp', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Amberleaf Brewcurrent Swordfish', 17136, 35557, 13645200, 61403400, 'Steam Beetle', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Mocha Aroma Coelacanth', 18003, 43477, 14508300, 78634986, 'Spice Roe', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Darjeeling Emberstream Leviathan', 18870, 51987, 15371400, 40887924, 'Leaf Larva', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Hearth Guppy', 19737, 61086, 16234500, 58119510, 'Kettle Cricket', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Saffron Dripline Smelt', 20604, 70775, 17097600, 76939200, 'Mint Fry', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Minted Herbal Shiner', 21471, 81053, 17960700, 97346994, 'Clove Worm', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'primordial', 'Velvet Warmwater Perch', 22338, 91921, 18823800, 50071308, 'Syrup Gnat', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Cinnamon Tisane Gar', 22000, 46200, 18942000, 93952320, 'Mocha Moth', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Matcha Cafecurrent Snapper', 23870, 58243, 21367500, 47008500, 'Tea Midge', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Jasmine-Steamfin Eel', 25740, 71557, 23793000, 74234160, 'Roast Worm', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Oolong Kettle Ray', 27610, 86143, 26218500, 105922740, 'Herbal Nymph', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Roasted Arowana', 29480, 102001, 28644000, 142074240, 'Bean Grub', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Clover Leafdrift Mackerel', 31350, 119130, 31069500, 68352900, 'Cinnamon Fly', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Sencha Brewcurrent Marlin', 33220, 137531, 33495000, 104504400, 'Foam Shrimp', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Amberleaf Aroma Shark', 35090, 73689, 35920500, 145118820, 'Steam Beetle', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Mocha Emberstream Tuna', 36960, 90182, 38346000, 190196160, 'Spice Roe', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Darjeeling Teacrest Minnow', 38830, 107947, 40771500, 89697300, 'Leaf Larva', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Hearth Loach', 40700, 126984, 43197000, 134774640, 'Kettle Cricket', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Saffron Herbal Darter', 42570, 147292, 45622500, 184314900, 'Mint Fry', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Minted Warmwater Chub', 44440, 168872, 48048000, 238318080, 'Clove Worm', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Velvet Foamline Bream', 46310, 191723, 50473500, 111041700, 'Syrup Gnat', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'transcendent', 'Copperkettle Brisk Trout', 48180, 101178, 52899000, 165044880, 'Biscuit Crumb', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Matcha Steamfin Grouper', 47000, 115855, 53136000, 287997120, 'Tea Midge', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Jasmine-Kettle Sturgeon', 50995, 143041, 59940000, 159440400, 'Roast Worm', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Oolong Infusion Manta', 54990, 172944, 66744000, 238943520, 'Herbal Nymph', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Roasted Barracuda', 58985, 205563, 73548000, 330966000, 'Bean Grub', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Clover Brewcurrent Salmon', 62980, 240899, 80352000, 435507840, 'Cinnamon Fly', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Sencha Aroma Swordfish', 66975, 278951, 87156000, 231834960, 'Foam Shrimp', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Amberleaf Emberstream Coelacanth', 70970, 150811, 93960000, 336376800, 'Steam Beetle', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Mocha Teacrest Leviathan', 74965, 184789, 100764000, 453438000, 'Spice Roe', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Darjeeling Dripline Guppy', 78960, 221483, 107568000, 583018560, 'Leaf Larva', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Hearth Smelt', 82955, 260893, 114372000, 304229520, 'Kettle Cricket', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Saffron Warmwater Shiner', 86950, 303021, 121176000, 433810080, 'Mint Fry', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Minted Foamline Perch', 90945, 347865, 127980000, 575910000, 'Clove Worm', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Velvet Brisk Carp', 94940, 395425, 134784000, 730529280, 'Syrup Gnat', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Copperkettle Tisane Pike', 98935, 210237, 141588000, 376624080, 'Biscuit Crumb', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'apotheosis', 'Cinnamon Cafecurrent Catfish', 102930, 253722, 148392000, 531243360, 'Mocha Moth', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Jasmine-Infusion Ray', 101000, 285830, 149240000, 328328000, 'Roast Worm', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Oolong Leafdrift Arowana', 109585, 347384, 168350000, 525252000, 'Herbal Nymph', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Roasted Mackerel', 118170, 414777, 187460000, 757338400, 'Bean Grub', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Clover Aroma Marlin', 126755, 488007, 206570000, 1024587200, 'Cinnamon Fly', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Sencha Emberstream Shark', 135340, 567075, 225680000, 496496000, 'Foam Shrimp', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Amberleaf Teacrest Tuna', 143925, 309439, 244790000, 763744800, 'Steam Beetle', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Mocha Dripline Minnow', 152510, 379750, 263900000, 1066156000, 'Spice Roe', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Darjeeling Herbal Loach', 161095, 455899, 283010000, 1403729600, 'Leaf Larva', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Hearth Darter', 169680, 537886, 302120000, 664664000, 'Kettle Cricket', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Saffron Foamline Chub', 178265, 625710, 321230000, 1002237600, 'Mint Fry', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Minted Brisk Bream', 186850, 719373, 340340000, 1374973600, 'Clove Worm', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Velvet Tisane Trout', 195435, 818873, 359450000, 1782872000, 'Syrup Gnat', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Copperkettle Cafecurrent Gar', 204020, 438643, 378560000, 832832000, 'Biscuit Crumb', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Cinnamon Steamfin Snapper', 212605, 529386, 397670000, 1240730400, 'Mocha Moth', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'absolute', 'Matcha Eel', 221190, 625968, 416780000, 1683791200, 'Tea Midge', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Oolong Brewcurrent Barracuda', 216000, 690120, 419840000, 1116774400, 'Herbal Nymph', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Roasted Salmon', 234360, 828463, 473600000, 1695488000, 'Bean Grub', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Clover Emberstream Swordfish', 252720, 979290, 527360000, 2373120000, 'Cinnamon Fly', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Sencha Teacrest Coelacanth', 271080, 1142602, 581120000, 3149670400, 'Foam Shrimp', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Amberleaf Dripline Leviathan', 289440, 629532, 634880000, 1688780800, 'Steam Beetle', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Mocha Herbal Guppy', 307800, 774117, 688640000, 2465331200, 'Spice Roe', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Darjeeling Warmwater Smelt', 326160, 931187, 742400000, 3340800000, 'Leaf Larva', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Hearth Shiner', 344520, 1100741, 796160000, 4315187200, 'Kettle Cricket', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Saffron Brisk Perch', 362880, 1282781, 849920000, 2260787200, 'Mint Fry', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Minted Tisane Carp', 381240, 1477305, 903680000, 3235174400, 'Clove Worm', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Velvet Cafecurrent Pike', 399600, 1684314, 957440000, 4308480000, 'Syrup Gnat', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Copperkettle Steamfin Catfish', 417960, 909063, 1011200000, 5480704000, 'Biscuit Crumb', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Cinnamon Kettle Grouper', 436320, 1097345, 1064960000, 2832793600, 'Mocha Moth', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Matcha Sturgeon', 454680, 1298111, 1118720000, 4005017600, 'Tea Midge', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'singularity', 'Jasmine Leafdrift Manta', 473040, 1511363, 1172480000, 5276160000, 'Roast Worm', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Roasted Marlin', 463000, 1648280, 1180800000, 3684096000, 'Bean Grub', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Clover Teacrest Shark', 502355, 1959185, 1332000000, 5381280000, 'Cinnamon Fly', 'Tailbeat leaves brief steam rings.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Sencha Dripline Tuna', 541710, 2296850, 1483200000, 7356672000, 'Foam Shrimp', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Amberleaf Herbal Minnow', 581065, 1278343, 1634400000, 3595680000, 'Steam Beetle', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Mocha Warmwater Loach', 620420, 1575867, 1785600000, 5571072000, 'Spice Roe', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Darjeeling Foamline Darter', 659775, 1900152, 1936800000, 7824672000, 'Leaf Larva', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Hearth Chub', 699130, 2251199, 2088000000, 10356480000, 'Kettle Cricket', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Saffron Tisane Bream', 738485, 2629007, 2239200000, 4926240000, 'Mint Fry', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Minted Cafecurrent Trout', 777840, 3033576, 2390400000, 7458048000, 'Clove Worm', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Velvet Steamfin Gar', 817195, 3464907, 2541600000, 10268064000, 'Syrup Gnat', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Copperkettle Kettle Snapper', 856550, 1884410, 2692800000, 13356288000, 'Biscuit Crumb', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Cinnamon Infusion Eel', 895905, 2275599, 2844000000, 6256800000, 'Mocha Moth', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Matcha Ray', 935260, 2693549, 2995200000, 9345024000, 'Tea Midge', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Jasmine Brewcurrent Arowana', 974615, 3138260, 3146400000, 12711456000, 'Roast Worm', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'paradox', 'Oolong-Aroma Mackerel', 1013970, 3609733, 3297600000, 16356096000, 'Herbal Nymph', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Clover Dripline Coelacanth', 992000, 3893600, 3329200000, 11918536000, 'Cinnamon Fly', 'Most active after rain-cooled evenings.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Sencha Herbal Leviathan', 1076320, 4590505, 3755500000, 16899750000, 'Foam Shrimp', 'Shifts color between tea and bronze tones.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Amberleaf Warmwater Guppy', 1160640, 2582424, 4181800000, 22665356000, 'Steam Beetle', 'Responds quickly to aromatic baits.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Mocha Foamline Smelt', 1244960, 3193322, 4608100000, 12257546000, 'Spice Roe', 'Holds depth well in rolling currents.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Darjeeling Brisk Shiner', 1329280, 3861558, 5034400000, 18023152000, 'Leaf Larva', 'Often rises during fragrant bloom hours.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Hearth Perch', 1413600, 4587132, 5460700000, 24573150000, 'Kettle Cricket', 'Can sprint in short hyperactive bursts.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Saffron Cafecurrent Carp', 1497920, 5370043, 5887000000, 31907540000, 'Mint Fry', 'Settles near mossy spring outflows.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Minted Steamfin Pike', 1582240, 6210292, 6313300000, 16793378000, 'Clove Worm', 'Tracks warm eddies near bubbling vents.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Velvet Kettle Catfish', 1666560, 7107878, 6739600000, 24127768000, 'Syrup Gnat', 'Bites hardest during sunrise steam.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Copperkettle Infusion Grouper', 1750880, 3895708, 7165900000, 32246550000, 'Biscuit Crumb', 'Carries a faint roasted aroma.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Cinnamon Leafdrift Sturgeon', 1835200, 4707288, 7592200000, 41149724000, 'Mocha Moth', 'Prefers mineral-rich herbal pools.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Matcha Manta', 1919520, 5576206, 8018500000, 21329210000, 'Tea Midge', 'Schools around kettle-stone shelves.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Jasmine Aroma Barracuda', 2003840, 6502461, 8444800000, 30232384000, 'Roast Worm', 'Can tolerate sudden heat spikes.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Oolong-Emberstream Salmon', 2088160, 7486054, 8871100000, 39919950000, 'Herbal Nymph', 'Feeds on caffeine-dense plankton.'),
  ('steeped_springs', 'Steeped Springs', 'null', 'Roasted Teacrest Swordfish', 2172480, 8526984, 9297400000, 50391908000, 'Bean Grub', 'Tailbeat leaves brief steam rings.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Porcelain Minnow', 0.19, 0.4, 8.04, 21.4, 'Clay Worm', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Ivory Ceramic Loach', 0.21, 0.5, 9.07, 32.49, 'Pearl Midge', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Celadon Goldseam Darter', 0.22, 0.62, 10.1, 45.47, 'Goldleaf Fry', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Kintsugi Kilnwater Chub', 0.24, 0.74, 11.13, 60.35, 'Glaze Grub', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Glazed Glazetail Bream', 0.26, 0.88, 12.16, 32.36, 'Kiln Beetle', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Whiteclay Crackline Trout', 0.27, 1.03, 13.19, 47.24, 'Slip Nymph', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Azureline Gar', 0.29, 0.5, 14.22, 64.01, 'Ceramic Shrimp', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Moonceramic Brushline Snapper', 0.3, 0.64, 15.25, 82.68, 'Rice Bran Fly', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Fineware-Siltshell Eel', 0.32, 0.78, 16.28, 43.32, 'Tea Dust Roe', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Lacquered Lustre Ray', 0.34, 0.93, 17.31, 61.99, 'Silica Larva', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Palegilt Teacup Arowana', 0.35, 1.1, 18.34, 82.55, 'Whitefly', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Stoneware Anvilclay Mackerel', 0.37, 1.27, 19.37, 105, 'Lacquer Cricket', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Kilnfire Marlin', 0.39, 1.46, 20.4, 54.28, 'Gilt Moth', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Silkglaze Slipstream Shark', 0.4, 0.7, 21.43, 76.74, 'Porcelain Pellet', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'common', 'Delft Mosaic Tuna', 0.42, 0.87, 22.46, 101, 'Varnish Gnat', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Ivory Goldseam Smelt', 0.66, 1.61, 23.24, 72.51, 'Pearl Midge', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Celadon Kilnwater Shiner', 0.71, 1.99, 26.21, 106, 'Goldleaf Fry', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Kintsugi Glazetail Perch', 0.77, 2.41, 29.19, 145, 'Glaze Grub', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Glazed Crackline Carp', 0.82, 2.87, 32.17, 70.76, 'Kiln Beetle', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Whiteclay Vasecrest Pike', 0.88, 3.36, 35.14, 110, 'Slip Nymph', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Azureline Catfish', 0.94, 1.66, 38.12, 154, 'Ceramic Shrimp', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Moonceramic Siltshell Grouper', 0.99, 2.1, 41.09, 204, 'Rice Bran Fly', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Fineware-Lustre Sturgeon', 1.05, 2.57, 44.07, 96.95, 'Tea Dust Roe', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Lacquered Teacup Manta', 1.1, 3.09, 47.04, 147, 'Silica Larva', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Palegilt Anvilclay Barracuda', 1.16, 3.64, 50.02, 202, 'Whitefly', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Stoneware Gildline Salmon', 1.22, 4.22, 53, 263, 'Lacquer Cricket', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Kilnfire Swordfish', 1.27, 4.85, 55.97, 123, 'Gilt Moth', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Silkglaze Mosaic Coelacanth', 1.33, 2.36, 58.95, 184, 'Porcelain Pellet', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Delft Shardfin Leviathan', 1.38, 2.93, 61.92, 250, 'Varnish Gnat', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'uncommon', 'Porcelain Ceramic Guppy', 1.44, 3.53, 64.9, 322, 'Clay Worm', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Celadon Glazetail Chub', 1.64, 4.63, 73.29, 262, 'Goldleaf Fry', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Kintsugi Crackline Bream', 1.78, 5.63, 82.68, 372, 'Glaze Grub', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Glazed Vasecrest Trout', 1.92, 6.73, 92.06, 499, 'Kiln Beetle', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Whiteclay Brushline Gar', 2.06, 7.92, 101, 270, 'Slip Nymph', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Azureline Snapper', 2.2, 3.96, 111, 397, 'Ceramic Shrimp', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Moonceramic Lustre Eel', 2.34, 5.01, 120, 541, 'Rice Bran Fly', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Fineware-Teacup Ray', 2.48, 6.15, 130, 702, 'Tea Dust Roe', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Lacquered Anvilclay Arowana', 2.62, 7.39, 139, 370, 'Silica Larva', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Palegilt Gildline Mackerel', 2.76, 8.72, 148, 531, 'Whitefly', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Stoneware Slipstream Marlin', 2.9, 10.15, 158, 710, 'Lacquer Cricket', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Kilnfire Shark', 3.04, 11.67, 167, 906, 'Gilt Moth', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Silkglaze Shardfin Tuna', 3.18, 5.72, 177, 470, 'Porcelain Pellet', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Delft Ceramic Minnow', 3.32, 7.1, 186, 666, 'Varnish Gnat', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Porcelain Goldseam Loach', 3.46, 8.58, 195, 879, 'Clay Worm', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'rare', 'Ivory-Kilnwater Darter', 3.6, 10.15, 205, 1109, 'Pearl Midge', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Kintsugi Vasecrest Carp', 4.35, 13.84, 223, 903, 'Glaze Grub', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Glazed Brushline Pike', 4.72, 16.62, 252, 1250, 'Kiln Beetle', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Whiteclay Siltshell Catfish', 5.08, 19.65, 281, 617, 'Slip Nymph', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Azureline Grouper', 5.45, 9.95, 309, 965, 'Ceramic Shrimp', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Moonceramic Teacup Sturgeon', 5.82, 12.61, 338, 1365, 'Rice Bran Fly', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Fineware-Anvilclay Manta', 6.19, 15.51, 367, 1818, 'Tea Dust Roe', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Lacquered Gildline Barracuda', 6.56, 18.67, 395, 869, 'Silica Larva', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Palegilt Slipstream Salmon', 6.93, 22.08, 424, 1322, 'Whitefly', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Stoneware Mosaic Swordfish', 7.3, 25.74, 452, 1827, 'Lacquer Cricket', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Kilnfire Coelacanth', 7.67, 29.65, 481, 2386, 'Gilt Moth', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Silkglaze Ceramic Leviathan', 8.04, 14.67, 510, 1121, 'Porcelain Pellet', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Delft Goldseam Guppy', 8.41, 18.21, 538, 1679, 'Varnish Gnat', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Porcelain Kilnwater Smelt', 8.78, 21.99, 567, 2290, 'Clay Worm', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Ivory-Glazetail Shiner', 9.15, 26.03, 595, 2953, 'Pearl Midge', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'epic', 'Celadon Crackline Perch', 9.52, 30.31, 624, 1373, 'Goldleaf Fry', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Glazed Siltshell Gar', 11.45, 40.64, 661, 2976, 'Kiln Beetle', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Whiteclay Lustre Snapper', 12.42, 48.32, 746, 4044, 'Slip Nymph', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Azureline Eel', 13.39, 24.78, 831, 2210, 'Ceramic Shrimp', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Moonceramic Anvilclay Ray', 14.37, 31.46, 915, 3277, 'Rice Bran Fly', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Fineware-Gildline Arowana', 15.34, 38.81, 1000, 4501, 'Tea Dust Roe', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Lacquered Slipstream Mackerel', 16.31, 46.82, 1085, 5880, 'Silica Larva', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Palegilt Mosaic Marlin', 17.29, 55.49, 1170, 3111, 'Whitefly', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Stoneware Shardfin Shark', 18.26, 64.82, 1254, 4490, 'Lacquer Cricket', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Kilnfire Tuna', 19.23, 74.81, 1339, 6025, 'Gilt Moth', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Silkglaze Goldseam Minnow', 20.21, 37.38, 1424, 7716, 'Porcelain Pellet', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Delft Kilnwater Loach', 21.18, 46.38, 1508, 4012, 'Varnish Gnat', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Porcelain Glazetail Darter', 22.15, 56.04, 1593, 5703, 'Clay Worm', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Ivory-Crackline Chub', 23.12, 66.37, 1678, 7550, 'Pearl Midge', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Celadon Vasecrest Bream', 24.1, 77.35, 1762, 9552, 'Goldleaf Fry', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'legendary', 'Kintsugi Trout', 25.07, 89, 1847, 4913, 'Glaze Grub', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Whiteclay Teacup Grouper', 25.44, 99.6, 1877, 9310, 'Slip Nymph', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Azureline Sturgeon', 27.6, 51.75, 2117, 4658, 'Ceramic Shrimp', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Moonceramic Gildline Manta', 29.76, 65.93, 2358, 7356, 'Rice Bran Fly', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Fineware-Slipstream Barracuda', 31.93, 81.57, 2598, 10496, 'Tea Dust Roe', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Lacquered Mosaic Salmon', 34.09, 98.69, 2838, 14078, 'Silica Larva', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Palegilt Shardfin Swordfish', 36.25, 117, 3079, 6773, 'Whitefly', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Stoneware Ceramic Coelacanth', 38.41, 137, 3319, 10355, 'Lacquer Cricket', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Kilnfire Leviathan', 40.58, 159, 3559, 14380, 'Gilt Moth', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Silkglaze Kilnwater Guppy', 42.74, 80.14, 3800, 18847, 'Porcelain Pellet', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Delft Glazetail Smelt', 44.9, 99.46, 4040, 8888, 'Varnish Gnat', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Porcelain Crackline Shiner', 47.06, 120, 4280, 13355, 'Clay Worm', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Ivory-Vasecrest Perch', 49.23, 143, 4521, 18264, 'Pearl Midge', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Celadon Brushline Carp', 51.39, 166, 4761, 23615, 'Goldleaf Fry', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Kintsugi Pike', 53.55, 191, 5001, 11003, 'Glaze Grub', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'liminal', 'Glazed Lustre Catfish', 55.71, 218, 5242, 16354, 'Kiln Beetle', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Azureline Ray', 55.12, 105, 5273, 28582, 'Ceramic Shrimp', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Moonceramic Slipstream Arowana', 59.81, 134, 5949, 15823, 'Rice Bran Fly', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Fineware-Mosaic Mackerel', 64.49, 166, 6624, 23714, 'Tea Dust Roe', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Lacquered Shardfin Marlin', 69.18, 202, 7299, 32846, 'Silica Larva', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Palegilt Ceramic Shark', 73.86, 241, 7974, 43221, 'Whitefly', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Stoneware Goldseam Tuna', 78.55, 283, 8650, 23008, 'Lacquer Cricket', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Kilnfire Minnow', 83.23, 328, 9325, 33383, 'Gilt Moth', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Silkglaze Glazetail Loach', 87.92, 167, 10000, 45001, 'Porcelain Pellet', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Delft Crackline Darter', 92.6, 207, 10675, 57861, 'Varnish Gnat', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Porcelain Vasecrest Chub', 97.29, 251, 11351, 30193, 'Clay Worm', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Ivory-Brushline Bream', 102, 298, 12026, 43053, 'Pearl Midge', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Celadon Siltshell Trout', 107, 348, 12701, 57156, 'Goldleaf Fry', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Kintsugi Gar', 111, 401, 13376, 72501, 'Glaze Grub', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Glazed Teacup Snapper', 116, 457, 14052, 37378, 'Kiln Beetle', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'mythic', 'Whiteclay Anvilclay Eel', 121, 229, 14727, 52723, 'Slip Nymph', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Moonceramic Mosaic Barracuda', 119, 269, 15016, 33035, 'Rice Bran Fly', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Fineware-Shardfin Salmon', 129, 336, 16939, 52848, 'Tea Dust Roe', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Lacquered Ceramic Swordfish', 139, 409, 18861, 76200, 'Silica Larva', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Palegilt Goldseam Coelacanth', 149, 489, 20784, 103089, 'Whitefly', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Stoneware Kilnwater Leviathan', 159, 577, 22707, 49955, 'Lacquer Cricket', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Kilnfire Guppy', 169, 671, 24630, 76844, 'Gilt Moth', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Silkglaze Crackline Smelt', 179, 345, 26552, 107272, 'Porcelain Pellet', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Delft Vasecrest Shiner', 189, 429, 28475, 141237, 'Varnish Gnat', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Porcelain Brushline Perch', 199, 520, 30398, 66875, 'Clay Worm', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Ivory-Siltshell Carp', 210, 617, 32321, 100841, 'Pearl Midge', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Celadon Lustre Pike', 220, 721, 34243, 138343, 'Goldleaf Fry', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Kintsugi Catfish', 230, 833, 36166, 179384, 'Glaze Grub', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Glazed Anvilclay Grouper', 240, 951, 38089, 83796, 'Kiln Beetle', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Whiteclay Gildline Sturgeon', 250, 481, 40012, 124837, 'Slip Nymph', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'ascendant', 'Azureline Slipstream Manta', 260, 589, 41934, 169415, 'Ceramic Shrimp', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Fineware-Ceramic Marlin', 249, 655, 42009, 111743, 'Tea Dust Roe', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Lacquered Goldseam Shark', 270, 803, 47388, 169648, 'Silica Larva', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Palegilt Kilnwater Tuna', 291, 965, 52767, 237451, 'Whitefly', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Stoneware Glazetail Minnow', 313, 1141, 58146, 315152, 'Lacquer Cricket', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Kilnfire Loach', 334, 1332, 63525, 168977, 'Gilt Moth', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Silkglaze Vasecrest Darter', 355, 692, 68904, 246678, 'Porcelain Pellet', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Delft Brushline Chub', 376, 861, 74284, 334276, 'Varnish Gnat', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Porcelain Siltshell Bream', 397, 1045, 79663, 431772, 'Clay Worm', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Ivory-Lustre Trout', 418, 1243, 85042, 226211, 'Pearl Midge', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Celadon Teacup Gar', 440, 1455, 90421, 323707, 'Goldleaf Fry', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Kintsugi Snapper', 461, 1682, 95800, 431100, 'Glaze Grub', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Glazed Gildline Eel', 482, 1923, 101179, 548392, 'Kiln Beetle', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Whiteclay Slipstream Ray', 503, 981, 106558, 283445, 'Slip Nymph', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Azureline Mosaic Arowana', 524, 1201, 111938, 400736, 'Ceramic Shrimp', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'celestial', 'Moonceramic Shardfin Mackerel', 546, 1435, 117317, 527925, 'Rice Bran Fly', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Lacquered Kilnwater Coelacanth', 525, 1571, 117982, 368103, 'Silica Larva', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Palegilt Glazetail Leviathan', 569, 1899, 133089, 537680, 'Whitefly', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Stoneware Crackline Guppy', 614, 2256, 148196, 735054, 'Lacquer Cricket', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Kilnfire Smelt', 658, 2644, 163304, 359268, 'Gilt Moth', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Silkglaze Brushline Shiner', 703, 1389, 178411, 556643, 'Porcelain Pellet', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Delft Siltshell Perch', 748, 1731, 193519, 781815, 'Varnish Gnat', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Porcelain Lustre Carp', 792, 2104, 208626, 1034785, 'Clay Worm', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Ivory-Teacup Pike', 837, 2507, 223733, 492213, 'Pearl Midge', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Celadon Anvilclay Catfish', 881, 2940, 238841, 745183, 'Goldleaf Fry', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Kintsugi Grouper', 926, 3403, 253948, 1025951, 'Glaze Grub', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Glazed Slipstream Sturgeon', 971, 3897, 269056, 1334516, 'Kiln Beetle', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Whiteclay Mosaic Manta', 1015, 2005, 284163, 625159, 'Slip Nymph', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Azureline Shardfin Barracuda', 1060, 2454, 299270, 933724, 'Ceramic Shrimp', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Moonceramic Ceramic Salmon', 1104, 2932, 314378, 1270086, 'Rice Bran Fly', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eldritch', 'Fineware Goldseam Swordfish', 1149, 3442, 329485, 1634247, 'Tea Dust Roe', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Palegilt Crackline Minnow', 1113, 3740, 330706, 1183927, 'Whitefly', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Stoneware Vasecrest Loach', 1208, 4468, 373053, 1678736, 'Lacquer Cricket', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Kilnfire Darter', 1302, 5261, 415399, 2251463, 'Gilt Moth', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Silkglaze Siltshell Chub', 1397, 2794, 457746, 1217603, 'Porcelain Pellet', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Delft Lustre Bream', 1491, 3490, 500092, 1790329, 'Varnish Gnat', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Porcelain Teacup Trout', 1586, 4251, 542439, 2440973, 'Clay Worm', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Ivory-Anvilclay Gar', 1681, 5076, 584785, 3169535, 'Pearl Midge', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Celadon Gildline Snapper', 1775, 5965, 627132, 1668170, 'Goldleaf Fry', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Kintsugi Eel', 1870, 6918, 669478, 2396731, 'Glaze Grub', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Glazed Mosaic Ray', 1964, 7936, 711825, 3203210, 'Kiln Beetle', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Whiteclay Shardfin Arowana', 2059, 4118, 754171, 4087607, 'Slip Nymph', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Azureline Ceramic Mackerel', 2154, 5040, 796518, 2118737, 'Ceramic Shrimp', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Moonceramic Goldseam Marlin', 2248, 6025, 838864, 3003133, 'Rice Bran Fly', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Fineware Kilnwater Shark', 2343, 7075, 881211, 3965447, 'Tea Dust Roe', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'eternal', 'Lacquered Tuna', 2437, 8190, 923557, 5005679, 'Silica Larva', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Stoneware Brushline Smelt', 2374, 8845, 929552, 3755390, 'Lacquer Cricket', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Kilnfire Shiner', 2576, 10472, 1048580, 5200957, 'Gilt Moth', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Silkglaze Lustre Perch', 2778, 5626, 1167608, 2568738, 'Porcelain Pellet', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Delft Teacup Carp', 2980, 7047, 1286636, 4014304, 'Varnish Gnat', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Porcelain Anvilclay Pike', 3182, 8606, 1405664, 5678883, 'Clay Worm', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Ivory-Gildline Catfish', 3384, 10303, 1524692, 7562472, 'Pearl Midge', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Celadon Slipstream Grouper', 3585, 12136, 1643720, 3616184, 'Goldleaf Fry', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Kintsugi Sturgeon', 3787, 14107, 1762748, 5499774, 'Glaze Grub', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Glazed Shardfin Manta', 3989, 16215, 1881776, 7602375, 'Kiln Beetle', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Whiteclay Ceramic Barracuda', 4191, 8486, 2000804, 9923988, 'Slip Nymph', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Azureline Goldseam Salmon', 4393, 10389, 2119832, 4663630, 'Ceramic Shrimp', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Moonceramic Kilnwater Swordfish', 4594, 12428, 2238860, 6985243, 'Rice Bran Fly', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Fineware Glazetail Coelacanth', 4796, 14605, 2357888, 9525868, 'Tea Dust Roe', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Lacquered Leviathan', 4998, 16919, 2476916, 12285503, 'Silica Larva', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'divine', 'Palegilt Vasecrest Guppy', 5200, 19370, 2595944, 5711077, 'Whitefly', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Kilnfire Chub', 5088, 20810, 2609896, 11744532, 'Gilt Moth', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Silkglaze Teacup Bream', 5520, 11317, 2944090, 15956968, 'Porcelain Pellet', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Delft Anvilclay Trout', 5953, 14228, 3278284, 8720235, 'Varnish Gnat', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Porcelain Gildline Gar', 6385, 17432, 3612478, 12932671, 'Clay Worm', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Ivory-Slipstream Snapper', 6818, 20931, 3946672, 17760024, 'Pearl Midge', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Celadon Mosaic Eel', 7250, 24724, 4280866, 23202294, 'Goldleaf Fry', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Kintsugi Ray', 7683, 28811, 4615060, 12276060, 'Glaze Grub', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Glazed Ceramic Arowana', 8115, 33192, 4949254, 17718329, 'Kiln Beetle', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Whiteclay Goldseam Mackerel', 8548, 17523, 5283448, 23775516, 'Slip Nymph', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Azureline Kilnwater Marlin', 8980, 21463, 5617642, 30447620, 'Ceramic Shrimp', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Moonceramic Glazetail Shark', 9413, 25697, 5951836, 15831884, 'Rice Bran Fly', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Fineware Crackline Tuna', 9845, 30225, 6286030, 22503987, 'Tea Dust Roe', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Lacquered Minnow', 10278, 35047, 6620224, 29791008, 'Silica Larva', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Palegilt Brushline Loach', 10710, 40163, 6954418, 37692946, 'Whitefly', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'cosmic', 'Stoneware Siltshell Darter', 11143, 45574, 7288612, 19387708, 'Lacquer Cricket', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Silkglaze Anvilclay Carp', 10812, 22435, 7347036, 36441299, 'Porcelain Pellet', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Delft Gildline Pike', 11731, 28330, 8287815, 18233193, 'Varnish Gnat', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Porcelain Slipstream Catfish', 12650, 34851, 9228594, 28793213, 'Clay Worm', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Ivory-Mosaic Grouper', 13569, 41996, 10169373, 41084267, 'Pearl Midge', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Celadon Shardfin Sturgeon', 14488, 49767, 11110152, 55106354, 'Goldleaf Fry', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Kintsugi Manta', 15407, 58162, 12050931, 26512048, 'Glaze Grub', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Glazed Goldseam Barracuda', 16326, 67182, 12991710, 40534135, 'Kiln Beetle', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Whiteclay Kilnwater Salmon', 17245, 35784, 13932489, 56287256, 'Slip Nymph', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Azureline Glazetail Swordfish', 18164, 43866, 14873268, 73771409, 'Ceramic Shrimp', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Moonceramic Crackline Coelacanth', 19083, 52574, 15814047, 34790903, 'Rice Bran Fly', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Fineware Vasecrest Leviathan', 20002, 61907, 16754826, 52275057, 'Tea Dust Roe', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Lacquered Guppy', 20921, 71864, 17695605, 71490244, 'Silica Larva', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Palegilt Siltshell Smelt', 21840, 82447, 18636384, 92436465, 'Whitefly', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Stoneware Lustre Shiner', 22759, 93654, 19577163, 43069759, 'Lacquer Cricket', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'primordial', 'Kilnfire Teacup Perch', 23678, 49132, 20517942, 64015979, 'Gilt Moth', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Delft Slipstream Gar', 23320, 56901, 20646780, 111905548, 'Varnish Gnat', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Porcelain Mosaic Snapper', 25302, 70340, 23290575, 61952930, 'Clay Worm', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Ivory-Shardfin Eel', 27284, 85127, 25934370, 92845045, 'Pearl Midge', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Celadon Ceramic Ray', 29267, 101262, 28578165, 128601743, 'Goldleaf Fry', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Kintsugi Arowana', 31249, 118745, 31221960, 169223023, 'Glaze Grub', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Glazed Kilnwater Mackerel', 33231, 137576, 33865755, 90082908, 'Kiln Beetle', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Whiteclay Glazetail Marlin', 35213, 73948, 36509550, 130704189, 'Slip Nymph', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Azureline Crackline Shark', 37195, 90757, 39153345, 176190053, 'Ceramic Shrimp', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Moonceramic Vasecrest Tuna', 39178, 108914, 41797140, 226540499, 'Rice Bran Fly', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Fineware Brushline Minnow', 41160, 128419, 44440935, 118212887, 'Tea Dust Roe', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Lacquered Loach', 43142, 149271, 47084730, 168563333, 'Silica Larva', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Palegilt Lustre Darter', 45124, 171472, 49728525, 223778363, 'Whitefly', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Stoneware Teacup Chub', 47106, 195020, 52372320, 283857974, 'Lacquer Cricket', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Kilnfire Anvilclay Bream', 49089, 103086, 55016115, 146342866, 'Gilt Moth', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'transcendent', 'Silkglaze Gildline Trout', 51071, 124613, 57659910, 206422478, 'Porcelain Pellet', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Porcelain Shardfin Grouper', 49820, 139745, 57918240, 127420128, 'Clay Worm', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Ivory-Ceramic Sturgeon', 54055, 170002, 65334600, 203843952, 'Pearl Midge', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Celadon Goldseam Manta', 58289, 203139, 72750960, 293913878, 'Goldleaf Fry', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Kintsugi Barracuda', 62524, 239155, 80167320, 397629907, 'Glaze Grub', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Glazed Glazetail Salmon', 66759, 278050, 87583680, 192684096, 'Kiln Beetle', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Whiteclay Crackline Swordfish', 70994, 150861, 95000040, 296400125, 'Slip Nymph', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Azureline Vasecrest Coelacanth', 75228, 185438, 102416400, 413762256, 'Ceramic Shrimp', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Moonceramic Brushline Leviathan', 79463, 222893, 109832760, 544770490, 'Rice Bran Fly', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Fineware Siltshell Guppy', 83698, 263229, 117249120, 257948064, 'Tea Dust Roe', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Lacquered Smelt', 87932, 306444, 124665480, 388956298, 'Silica Larva', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Palegilt Teacup Shiner', 92167, 352539, 132081840, 533610634, 'Whitefly', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Stoneware Anvilclay Perch', 96402, 401513, 139498200, 691911072, 'Lacquer Cricket', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Kilnfire Gildline Carp', 100636, 213852, 146914560, 323212032, 'Gilt Moth', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Silkglaze Slipstream Pike', 104871, 258507, 154330920, 481512470, 'Porcelain Pellet', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'apotheosis', 'Delft Mosaic Catfish', 109106, 306042, 161747280, 653459011, 'Varnish Gnat', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Ivory-Goldseam Ray', 107060, 339380, 162671600, 432706456, 'Pearl Midge', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Celadon Kilnwater Arowana', 116160, 407722, 183501500, 656935370, 'Goldleaf Fry', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Kintsugi Mackerel', 125260, 482252, 204331400, 919491300, 'Glaze Grub', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Glazed Crackline Marlin', 134360, 562970, 225161300, 1220374246, 'Kiln Beetle', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Whiteclay Vasecrest Shark', 143460, 308440, 245991200, 654336592, 'Slip Nymph', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Azureline Brushline Tuna', 152561, 379876, 266821100, 955219538, 'Ceramic Shrimp', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Moonceramic Siltshell Minnow', 161661, 457499, 287651000, 1294429500, 'Rice Bran Fly', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Fineware Lustre Loach', 170761, 541311, 308480900, 1671966478, 'Tea Dust Roe', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Lacquered Darter', 179861, 631311, 329310800, 875966728, 'Silica Larva', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Palegilt Anvilclay Chub', 188961, 727499, 350140700, 1253503706, 'Whitefly', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Stoneware Gildline Bream', 198061, 829876, 370970600, 1669367700, 'Lacquer Cricket', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Kilnfire Slipstream Trout', 207161, 445396, 391800500, 2123558710, 'Gilt Moth', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Silkglaze Mosaic Gar', 216261, 538490, 412630400, 1097596864, 'Porcelain Pellet', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Delft Shardfin Snapper', 225361, 637772, 433460300, 1551787874, 'Varnish Gnat', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'absolute', 'Porcelain Eel', 234461, 743243, 454290200, 2044305900, 'Clay Worm', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Celadon Glazetail Barracuda', 228960, 809374, 457625600, 1427791872, 'Goldleaf Fry', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Kintsugi Salmon', 248422, 962634, 516224000, 2085544960, 'Glaze Grub', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Glazed Vasecrest Swordfish', 267883, 1129128, 574822400, 2851119104, 'Kiln Beetle', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Whiteclay Brushline Coelacanth', 287345, 624975, 633420800, 1393525760, 'Slip Nymph', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Azureline Siltshell Leviathan', 306806, 771618, 692019200, 2159099904, 'Ceramic Shrimp', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Moonceramic Lustre Guppy', 326268, 931495, 750617600, 3032495104, 'Rice Bran Fly', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Fineware Teacup Smelt', 345730, 1104606, 809216000, 4013711360, 'Tea Dust Roe', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Lacquered Shiner', 365191, 1290951, 867814400, 1909191680, 'Silica Larva', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Palegilt Gildline Perch', 384653, 1490530, 926412800, 2890407936, 'Whitefly', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Stoneware Slipstream Carp', 404114, 1703342, 985011200, 3979445248, 'Lacquer Cricket', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Kilnfire Mosaic Pike', 423576, 921278, 1043609600, 5176303616, 'Gilt Moth', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Silkglaze Shardfin Catfish', 443038, 1114240, 1102208000, 2424857600, 'Porcelain Pellet', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Delft Ceramic Grouper', 462499, 1320435, 1160806400, 3621715968, 'Varnish Gnat', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Porcelain Sturgeon', 481961, 1539865, 1219404800, 4926395392, 'Clay Worm', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'singularity', 'Ivory Kilnwater Manta', 501422, 1772528, 1278003200, 6338895872, 'Pearl Midge', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Kintsugi Marlin', 490780, 1914042, 1287072000, 4607717760, 'Glaze Grub', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Glazed Brushline Shark', 532496, 2257784, 1451880000, 6533460000, 'Kiln Beetle', 'Tracks fine vibration through brittle stone.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Whiteclay Siltshell Tuna', 574213, 1263268, 1616688000, 8762448960, 'Slip Nymph', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Azureline Lustre Minnow', 615929, 1564459, 1781496000, 4738779360, 'Ceramic Shrimp', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Moonceramic Teacup Loach', 657645, 1894018, 1946304000, 6967768320, 'Rice Bran Fly', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Fineware Anvilclay Darter', 699362, 2251944, 2111112000, 9500004000, 'Tea Dust Roe', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Lacquered Chub', 741078, 2638237, 2275920000, 12335486400, 'Silica Larva', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Palegilt Slipstream Bream', 782794, 3052897, 2440728000, 6492336480, 'Whitefly', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Stoneware Mosaic Trout', 824510, 3495924, 2605536000, 9327818880, 'Lacquer Cricket', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Kilnfire Shardfin Gar', 866227, 1905699, 2770344000, 12466548000, 'Gilt Moth', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Silkglaze Ceramic Snapper', 907943, 2306175, 2935152000, 15908523840, 'Porcelain Pellet', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Delft Goldseam Eel', 949659, 2735019, 3099960000, 8245893600, 'Varnish Gnat', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Porcelain Ray', 991376, 3192229, 3264768000, 11687869440, 'Clay Worm', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Ivory Glazetail Arowana', 1033092, 3677807, 3429576000, 15433092000, 'Pearl Midge', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'paradox', 'Celadon-Crackline Mackerel', 1074808, 4191752, 3594384000, 19481561280, 'Goldleaf Fry', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Glazed Siltshell Coelacanth', 1051520, 4484733, 3628828000, 14660465120, 'Kiln Beetle', 'Favours clean water with low sediment.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Whiteclay Lustre Leviathan', 1140899, 2538501, 4093495000, 20303735200, 'Slip Nymph', 'Turns pearly under bright overcast light.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Azureline Teacup Guppy', 1230278, 3155664, 4558162000, 10027956400, 'Ceramic Shrimp', 'Spooks at heavy footsteps on tile.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Moonceramic Anvilclay Smelt', 1319658, 3833605, 5022829000, 15671226480, 'Rice Bran Fly', 'Feeds near warm kiln runoff pockets.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Fineware Gildline Shiner', 1409037, 4572324, 5487496000, 22169483840, 'Tea Dust Roe', 'Holds close to ornate vase caverns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Lacquered Perch', 1498416, 5371821, 5952163000, 29522728480, 'Silica Larva', 'Bites cleanly, then dives deep.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Palegilt Mosaic Carp', 1587795, 6232096, 6416830000, 14117026000, 'Whitefly', 'Shows strongest color at dawn.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Stoneware Shardfin Pike', 1677174, 7153149, 6881497000, 21470270640, 'Lacquer Cricket', 'Hides along hairline gold seams.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Kilnfire Ceramic Catfish', 1766554, 3930582, 7346164000, 29678502560, 'Gilt Moth', 'Scales reflect like polished glaze.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Silkglaze Goldseam Grouper', 1855933, 4760468, 7810831000, 38741721760, 'Porcelain Pellet', 'Prefers still water over noisy flow.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Delft Kilnwater Sturgeon', 1945312, 5651131, 8275498000, 18206095600, 'Varnish Gnat', 'Can chip line guides with sharp turns.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Porcelain Manta', 2034691, 6602573, 8740165000, 27269314800, 'Clay Worm', 'Nests beside cracked ceramic ridges.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Ivory Crackline Barracuda', 2124070, 7614792, 9204832000, 37187521280, 'Pearl Midge', 'Glides quietly over smooth pond beds.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Celadon-Vasecrest Salmon', 2213450, 8687790, 9669499000, 47960715040, 'Goldleaf Fry', 'Most active during cool moonlit hours.'),
  ('porcelain_ponds', 'Porcelain Ponds', 'null', 'Kintsugi Brushline Swordfish', 2302829, 9821565, 10134166000, 22295165200, 'Glaze Grub', 'Tracks fine vibration through brittle stone.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Sepia Minnow', 0.2, 0.49, 8.71, 27.17, 'Lamp Midge', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Silvergrain Frame Loach', 0.22, 0.61, 9.82, 39.69, 'Silver Worm', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Projector Cutline Darter', 0.24, 0.73, 10.94, 54.26, 'Reel Grub', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Velvet Splice Chub', 0.25, 0.87, 12.05, 26.52, 'Dustfly', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Noir Stillwater Bream', 0.27, 1.02, 13.17, 41.09, 'Splice Nymph', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Reelbound Vignette Trout', 0.29, 0.5, 14.28, 57.71, 'Tape Shrimp', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Framewise Gar', 0.3, 0.64, 15.4, 76.38, 'Cue Beetle', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Sundial Backdrop Snapper', 0.32, 0.78, 16.51, 36.33, 'Cinema Roe', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Flicker-Spotlight Eel', 0.34, 0.94, 17.63, 55, 'Carbon Larva', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Monochrome Dissolve Ray', 0.36, 1.11, 18.74, 75.73, 'Stage Cricket', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Lantern Cuecurrent Arowana', 0.37, 1.29, 19.86, 98.5, 'Spotlight Fry', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Oldhouse Storyboard Mackerel', 0.39, 1.48, 20.97, 46.14, 'Shadow Worm', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Cine Marlin', 0.41, 0.71, 22.09, 68.92, 'Celluloid Gnat', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Studio Matte Shark', 0.42, 0.89, 23.2, 93.75, 'Velvet Moth', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'common', 'Archive Exposure Tuna', 0.44, 1.07, 24.32, 121, 'Lensfly', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Silvergrain Cutline Smelt', 0.69, 1.94, 25.16, 90.06, 'Silver Worm', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Projector Splice Shiner', 0.75, 2.36, 28.38, 128, 'Reel Grub', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Velvet Stillwater Perch', 0.81, 2.82, 31.6, 171, 'Dustfly', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Noir Vignette Carp', 0.87, 3.32, 34.82, 92.63, 'Splice Nymph', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Reelbound Filmline Pike', 0.93, 1.65, 38.04, 136, 'Tape Shrimp', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Framewise Catfish', 0.99, 2.09, 41.26, 186, 'Cue Beetle', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Sundial Spotlight Grouper', 1.05, 2.57, 44.49, 241, 'Cinema Roe', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Flicker-Dissolve Sturgeon', 1.11, 3.1, 47.71, 127, 'Carbon Larva', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Monochrome Cuecurrent Manta', 1.17, 3.66, 50.93, 182, 'Stage Cricket', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Lantern Storyboard Barracuda', 1.23, 4.26, 54.15, 244, 'Spotlight Fry', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Oldhouse Roll Salmon', 1.28, 4.9, 57.37, 311, 'Shadow Worm', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Cine Swordfish', 1.34, 2.39, 60.59, 161, 'Celluloid Gnat', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Studio Exposure Coelacanth', 1.4, 2.97, 63.81, 228, 'Velvet Moth', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Archive Reelfin Leviathan', 1.46, 3.59, 67.04, 302, 'Lensfly', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'uncommon', 'Sepia Frame Guppy', 1.52, 4.25, 70.26, 381, 'Lamp Midge', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Projector Stillwater Chub', 1.74, 5.49, 79.34, 321, 'Reel Grub', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Velvet Vignette Bream', 1.88, 6.59, 89.5, 444, 'Dustfly', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Noir Filmline Trout', 2.03, 7.8, 99.66, 219, 'Splice Nymph', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Reelbound Backdrop Gar', 2.18, 3.92, 110, 343, 'Tape Shrimp', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Framewise Snapper', 2.33, 4.98, 120, 485, 'Cue Beetle', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Sundial Dissolve Eel', 2.47, 6.14, 130, 646, 'Cinema Roe', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Flicker-Cuecurrent Ray', 2.62, 7.39, 140, 309, 'Carbon Larva', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Monochrome Storyboard Arowana', 2.77, 8.75, 150, 469, 'Stage Cricket', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Lantern Roll Mackerel', 2.92, 10.21, 161, 649, 'Spotlight Fry', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Oldhouse Matte Marlin', 3.06, 11.77, 171, 847, 'Shadow Worm', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Cine Shark', 3.21, 5.78, 181, 398, 'Celluloid Gnat', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Studio Reelfin Tuna', 3.36, 7.19, 191, 596, 'Velvet Moth', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Archive Frame Minnow', 3.51, 8.7, 201, 813, 'Lensfly', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Sepia Cutline Loach', 3.65, 10.31, 211, 1049, 'Lamp Midge', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'rare', 'Silvergrain-Splice Darter', 3.8, 12.01, 222, 487, 'Silver Worm', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Velvet Filmline Carp', 4.59, 16.19, 242, 1089, 'Dustfly', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Noir Backdrop Pike', 4.98, 19.26, 273, 1479, 'Splice Nymph', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Reelbound Spotlight Catfish', 5.37, 9.81, 304, 808, 'Tape Shrimp', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Framewise Grouper', 5.76, 12.48, 335, 1199, 'Cue Beetle', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Sundial Cuecurrent Sturgeon', 6.15, 15.41, 366, 1646, 'Cinema Roe', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Flicker-Storyboard Manta', 6.54, 18.62, 397, 2151, 'Carbon Larva', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Monochrome Roll Barracuda', 6.93, 22.08, 428, 1138, 'Stage Cricket', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Lantern Matte Salmon', 7.32, 25.82, 459, 1642, 'Spotlight Fry', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Oldhouse Exposure Swordfish', 7.71, 29.82, 490, 2204, 'Shadow Worm', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Cine Coelacanth', 8.1, 14.79, 521, 2822, 'Celluloid Gnat', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Studio Frame Leviathan', 8.5, 18.39, 552, 1467, 'Velvet Moth', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Archive Cutline Guppy', 8.89, 22.26, 583, 2086, 'Lensfly', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Sepia Splice Smelt', 9.28, 26.39, 614, 2761, 'Lamp Midge', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Silvergrain-Stillwater Shiner', 9.67, 30.79, 645, 3494, 'Silver Worm', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'epic', 'Projector Vignette Perch', 10.06, 35.45, 676, 1797, 'Reel Grub', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Noir Spotlight Gar', 12.1, 47.05, 716, 3551, 'Splice Nymph', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Reelbound Dissolve Snapper', 13.12, 24.28, 808, 1777, 'Tape Shrimp', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Framewise Eel', 14.15, 30.99, 899, 2806, 'Cue Beetle', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Sundial Storyboard Ray', 15.18, 38.41, 991, 4004, 'Cinema Roe', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Flicker-Roll Arowana', 16.21, 46.52, 1083, 5371, 'Carbon Larva', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Monochrome Matte Mackerel', 17.24, 55.33, 1174, 2584, 'Stage Cricket', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Lantern Exposure Marlin', 18.26, 64.84, 1266, 3950, 'Spotlight Fry', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Oldhouse Reelfin Shark', 19.29, 75.05, 1358, 5486, 'Shadow Worm', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Cine Tuna', 20.32, 37.59, 1450, 7190, 'Celluloid Gnat', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Studio Cutline Minnow', 21.35, 46.76, 1541, 3391, 'Velvet Moth', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Archive Splice Loach', 22.38, 56.62, 1633, 5095, 'Lensfly', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Sepia Stillwater Darter', 23.41, 67.17, 1725, 6967, 'Lamp Midge', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Silvergrain-Vignette Chub', 24.43, 78.43, 1816, 9009, 'Silver Worm', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Projector Filmline Bream', 25.46, 90.39, 1908, 4197, 'Reel Grub', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'legendary', 'Velvet Trout', 26.49, 103, 2000, 6239, 'Dustfly', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Reelbound Cuecurrent Grouper', 26.88, 50.4, 2032, 11013, 'Tape Shrimp', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Framewise Sturgeon', 29.16, 64.6, 2292, 6097, 'Cue Beetle', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Sundial Roll Manta', 31.45, 80.35, 2552, 9137, 'Cinema Roe', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Flicker-Matte Barracuda', 33.73, 97.66, 2813, 12656, 'Carbon Larva', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Monochrome Exposure Salmon', 36.02, 117, 3073, 16654, 'Stage Cricket', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Lantern Reelfin Swordfish', 38.3, 137, 3333, 8866, 'Spotlight Fry', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Oldhouse Frame Coelacanth', 40.59, 159, 3593, 12863, 'Shadow Worm', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Cine Leviathan', 42.87, 80.39, 3853, 17340, 'Celluloid Gnat', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Studio Splice Guppy', 45.16, 100, 4113, 22295, 'Velvet Moth', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Archive Stillwater Smelt', 47.44, 121, 4374, 11634, 'Lensfly', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Sepia Vignette Shiner', 49.73, 144, 4634, 16589, 'Lamp Midge', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Silvergrain-Filmline Perch', 52.01, 168, 4894, 22023, 'Silver Worm', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Projector Backdrop Carp', 54.3, 194, 5154, 27936, 'Reel Grub', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Velvet Pike', 56.58, 222, 5414, 14402, 'Dustfly', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'liminal', 'Noir Dissolve Catfish', 58.87, 110, 5675, 20315, 'Splice Nymph', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Framewise Ray', 58.24, 130, 5709, 12559, 'Cue Beetle', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Sundial Matte Arowana', 63.19, 163, 6440, 20092, 'Cinema Roe', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Flicker-Exposure Mackerel', 68.14, 199, 7171, 28970, 'Carbon Larva', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Monochrome Reelfin Marlin', 73.09, 238, 7902, 39193, 'Stage Cricket', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Lantern Frame Shark', 78.04, 281, 8633, 18992, 'Spotlight Fry', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Oldhouse Cutline Tuna', 82.99, 327, 9364, 29215, 'Shadow Worm', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Cine Minnow', 87.94, 167, 10095, 40783, 'Celluloid Gnat', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Studio Stillwater Loach', 92.89, 208, 10826, 53697, 'Velvet Moth', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Archive Vignette Darter', 97.84, 252, 11557, 25425, 'Lensfly', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Sepia Filmline Chub', 103, 300, 12288, 38338, 'Lamp Midge', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Silvergrain-Backdrop Bream', 108, 351, 13019, 52597, 'Silver Worm', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Projector Spotlight Trout', 113, 406, 13750, 68200, 'Reel Grub', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Velvet Gar', 118, 464, 14481, 31858, 'Dustfly', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Noir Cuecurrent Snapper', 123, 233, 15212, 47461, 'Splice Nymph', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'mythic', 'Reelbound Storyboard Eel', 128, 286, 15943, 64410, 'Tape Shrimp', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Sundial Exposure Barracuda', 125, 327, 16256, 43240, 'Cinema Roe', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Flicker-Reelfin Salmon', 136, 401, 18337, 65647, 'Carbon Larva', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Monochrome Frame Swordfish', 147, 482, 20419, 91884, 'Stage Cricket', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Lantern Cutline Coelacanth', 157, 571, 22500, 121951, 'Spotlight Fry', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Oldhouse Splice Leviathan', 168, 666, 24582, 65387, 'Shadow Worm', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Cine Guppy', 179, 344, 26663, 95455, 'Celluloid Gnat', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Studio Vignette Smelt', 189, 429, 28745, 129352, 'Velvet Moth', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Archive Filmline Shiner', 200, 521, 30826, 167079, 'Lensfly', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Sepia Backdrop Perch', 211, 621, 32908, 87535, 'Lamp Midge', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Silvergrain-Spotlight Carp', 221, 727, 34989, 125262, 'Silver Worm', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Projector Dissolve Pike', 232, 841, 37071, 166819, 'Reel Grub', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Velvet Catfish', 243, 962, 39152, 212206, 'Dustfly', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Noir Storyboard Grouper', 253, 488, 41234, 109682, 'Splice Nymph', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Reelbound Roll Sturgeon', 264, 598, 43315, 155069, 'Tape Shrimp', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'ascendant', 'Framewise Matte Manta', 275, 716, 45397, 204286, 'Cue Beetle', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Flicker-Frame Marlin', 263, 782, 45477, 141889, 'Carbon Larva', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Monochrome Cutline Shark', 286, 945, 51300, 207254, 'Stage Cricket', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Lantern Splice Tuna', 308, 1124, 57124, 283334, 'Spotlight Fry', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Oldhouse Stillwater Minnow', 330, 1318, 62947, 138484, 'Shadow Worm', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Cine Loach', 353, 688, 68770, 214564, 'Celluloid Gnat', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Studio Filmline Darter', 375, 859, 74594, 301359, 'Velvet Moth', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Archive Backdrop Chub', 397, 1045, 80417, 398868, 'Lensfly', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Sepia Spotlight Bream', 420, 1247, 86240, 189729, 'Lamp Midge', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Silvergrain-Dissolve Trout', 442, 1464, 92064, 287238, 'Silver Worm', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Projector Cuecurrent Gar', 465, 1696, 97887, 395463, 'Reel Grub', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Velvet Snapper', 487, 1943, 103710, 514403, 'Dustfly', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Noir Roll Eel', 509, 993, 109534, 240974, 'Splice Nymph', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Reelbound Matte Ray', 532, 1218, 115357, 359913, 'Tape Shrimp', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Framewise Exposure Arowana', 554, 1457, 121180, 489568, 'Cue Beetle', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'celestial', 'Sundial Reelfin Mackerel', 576, 1712, 127003, 629937, 'Cinema Roe', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Monochrome Splice Coelacanth', 554, 1849, 127723, 457249, 'Stage Cricket', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Lantern Stillwater Leviathan', 602, 2211, 144078, 648351, 'Spotlight Fry', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Oldhouse Vignette Guppy', 649, 2604, 160433, 869546, 'Shadow Worm', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Cine Smelt', 696, 1374, 176788, 470255, 'Celluloid Gnat', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Studio Backdrop Shiner', 743, 1720, 193142, 691450, 'Velvet Moth', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Archive Spotlight Perch', 790, 2098, 209497, 942737, 'Lensfly', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Sepia Dissolve Carp', 837, 2507, 225852, 1224118, 'Lamp Midge', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Silvergrain-Cuecurrent Pike', 884, 2949, 242207, 644270, 'Silver Worm', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Projector Storyboard Catfish', 931, 3423, 258562, 925651, 'Reel Grub', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Velvet Grouper', 979, 3929, 274916, 1237124, 'Dustfly', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Noir Matte Sturgeon', 1026, 2026, 291271, 1578690, 'Splice Nymph', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Reelbound Exposure Manta', 1073, 2483, 307626, 818285, 'Tape Shrimp', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Framewise Reelfin Barracuda', 1120, 2973, 323981, 1159851, 'Cue Beetle', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Sundial Frame Salmon', 1167, 3495, 340336, 1531510, 'Cinema Roe', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eldritch', 'Flicker Cutline Swordfish', 1214, 4049, 356690, 1933262, 'Carbon Larva', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Lantern Vignette Minnow', 1176, 4351, 358012, 1446368, 'Spotlight Fry', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Oldhouse Filmline Loach', 1276, 5155, 403855, 2003121, 'Shadow Worm', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Cine Darter', 1376, 2752, 449698, 989336, 'Celluloid Gnat', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Studio Spotlight Chub', 1476, 3454, 495541, 1546088, 'Velvet Moth', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Archive Dissolve Bream', 1576, 4223, 541384, 2187191, 'Lensfly', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Sepia Cuecurrent Trout', 1676, 5061, 587227, 2912646, 'Lamp Midge', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Silvergrain-Storyboard Gar', 1776, 5967, 633070, 1392754, 'Silver Worm', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Projector Roll Snapper', 1876, 6940, 678913, 2118209, 'Reel Grub', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Velvet Eel', 1976, 7982, 724756, 2928014, 'Dustfly', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Noir Exposure Ray', 2076, 4151, 770599, 3822171, 'Splice Nymph', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Reelbound Reelfin Arowana', 2176, 5091, 816442, 1796172, 'Tape Shrimp', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Framewise Frame Mackerel', 2276, 6099, 862285, 2690329, 'Cue Beetle', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Sundial Cutline Marlin', 2376, 7174, 908128, 3668837, 'Cinema Roe', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Flicker Splice Shark', 2475, 8318, 953971, 4731696, 'Carbon Larva', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'eternal', 'Monochrome Tuna', 2575, 9529, 999814, 2199591, 'Stage Cricket', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Oldhouse Backdrop Smelt', 2509, 10198, 1006304, 4528368, 'Shadow Worm', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Cine Shiner', 2722, 5512, 1135160, 6152567, 'Celluloid Gnat', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Studio Dissolve Perch', 2935, 6942, 1264016, 3362283, 'Velvet Moth', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Archive Cuecurrent Carp', 3149, 8517, 1392872, 4986482, 'Lensfly', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Sepia Storyboard Pike', 3362, 10237, 1521728, 6847776, 'Lamp Midge', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Silvergrain-Roll Catfish', 3575, 12102, 1650584, 8946165, 'Silver Worm', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Projector Matte Grouper', 3788, 14111, 1779440, 4733310, 'Reel Grub', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Velvet Sturgeon', 4002, 16266, 1908296, 6831700, 'Dustfly', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Noir Reelfin Manta', 4215, 8535, 2037152, 9167184, 'Splice Nymph', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Reelbound Frame Barracuda', 4428, 10472, 2166008, 11739763, 'Tape Shrimp', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Framewise Cutline Salmon', 4641, 12555, 2294864, 6104338, 'Cue Beetle', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Sundial Splice Swordfish', 4855, 14782, 2423720, 8676918, 'Cinema Roe', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Flicker Stillwater Coelacanth', 5068, 17154, 2552576, 11486592, 'Carbon Larva', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Monochrome Leviathan', 5281, 19672, 2681432, 14533361, 'Stage Cricket', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'divine', 'Lantern Filmline Guppy', 5494, 22334, 2810288, 7475366, 'Spotlight Fry', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Cine Chub', 5376, 11021, 2825392, 14013944, 'Celluloid Gnat', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Studio Cuecurrent Bream', 5833, 13941, 3187180, 7011796, 'Velvet Moth', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Archive Storyboard Trout', 6290, 17171, 3548968, 11072780, 'Lensfly', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Sepia Roll Gar', 6747, 20713, 3910756, 15799454, 'Lamp Midge', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Silvergrain-Matte Snapper', 7204, 24565, 4272544, 21191818, 'Silver Worm', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Projector Exposure Eel', 7661, 28728, 4634332, 10195530, 'Reel Grub', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Velvet Ray', 8118, 33202, 4996120, 15587894, 'Dustfly', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Noir Frame Arowana', 8575, 17578, 5357908, 21645948, 'Splice Nymph', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Reelbound Cutline Mackerel', 9032, 21586, 5719696, 28369692, 'Tape Shrimp', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Framewise Splice Marlin', 9489, 25904, 6081484, 13379265, 'Cue Beetle', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Sundial Stillwater Shark', 9946, 30533, 6443272, 20103009, 'Cinema Roe', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Flicker Vignette Tuna', 10403, 35473, 6805060, 27492442, 'Carbon Larva', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Monochrome Minnow', 10860, 40723, 7166848, 35547566, 'Stage Cricket', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Lantern Backdrop Loach', 11316, 46284, 7528636, 16562999, 'Spotlight Fry', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'cosmic', 'Oldhouse Spotlight Darter', 11773, 24136, 7890424, 24618123, 'Shadow Worm', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Studio Storyboard Carp', 11424, 27589, 7953672, 43108902, 'Velvet Moth', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Archive Roll Pike', 12395, 34148, 8972130, 23865866, 'Lensfly', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Sepia Matte Catfish', 13366, 41368, 9990588, 35766305, 'Lamp Midge', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Silvergrain-Exposure Grouper', 14337, 49248, 11009046, 49540707, 'Silver Worm', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Projector Reelfin Sturgeon', 15308, 57788, 12027504, 65189072, 'Reel Grub', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Velvet Manta', 16279, 66989, 13045962, 34702259, 'Dustfly', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Noir Cutline Barracuda', 17250, 35794, 14064420, 50350624, 'Splice Nymph', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Reelbound Splice Salmon', 18221, 44004, 15082878, 67872951, 'Tape Shrimp', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Framewise Stillwater Swordfish', 19192, 52875, 16101336, 87269241, 'Cue Beetle', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Sundial Vignette Coelacanth', 20163, 62406, 17119794, 45538652, 'Cinema Roe', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Flicker Filmline Leviathan', 21134, 72597, 18138252, 64934942, 'Carbon Larva', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Monochrome Guppy', 22105, 83448, 19156710, 86205195, 'Stage Cricket', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Lantern Spotlight Smelt', 23076, 94960, 20175168, 109349411, 'Spotlight Fry', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Oldhouse Dissolve Shiner', 24048, 49899, 21193626, 56375045, 'Shadow Worm', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'primordial', 'Cine Cuecurrent Perch', 25019, 60420, 22212084, 79519261, 'Celluloid Gnat', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Archive Matte Gar', 24640, 68499, 22351560, 49173432, 'Lensfly', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Sepia Exposure Snapper', 26734, 83411, 25213650, 78666588, 'Lamp Midge', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Silvergrain-Reelfin Eel', 28829, 99748, 28075740, 113425990, 'Silver Worm', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Projector Frame Ray', 30923, 117508, 30937830, 153451637, 'Reel Grub', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Velvet Arowana', 33018, 136693, 33799920, 74359824, 'Dustfly', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Noir Splice Mackerel', 35112, 73735, 36662010, 114385471, 'Splice Nymph', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Reelbound Stillwater Marlin', 37206, 90784, 39524100, 159677364, 'Tape Shrimp', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Framewise Vignette Shark', 39301, 109256, 42386190, 210235502, 'Cue Beetle', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Sundial Filmline Tuna', 41395, 129153, 45248280, 99546216, 'Cinema Roe', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Flicker Backdrop Minnow', 43490, 150474, 48110370, 150104354, 'Carbon Larva', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Monochrome Loach', 45584, 173219, 50972460, 205928738, 'Stage Cricket', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Lantern Dissolve Darter', 47678, 197389, 53834550, 267019368, 'Spotlight Fry', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Oldhouse Cuecurrent Chub', 49773, 104523, 56696640, 124732608, 'Shadow Worm', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Cine Storyboard Bream', 51867, 126556, 59558730, 185823238, 'Celluloid Gnat', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'transcendent', 'Studio Roll Trout', 53962, 150013, 62420820, 252180113, 'Velvet Moth', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Sepia Reelfin Grouper', 52640, 165553, 62700480, 166783277, 'Lamp Midge', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Silvergrain-Frame Sturgeon', 57114, 199044, 70729200, 253210536, 'Silver Worm', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Projector Cutline Manta', 61589, 235577, 78757920, 354410640, 'Reel Grub', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Velvet Barracuda', 66063, 275153, 86786640, 470383589, 'Dustfly', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Noir Stillwater Salmon', 70538, 149892, 94815360, 252208858, 'Splice Nymph', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Reelbound Vignette Swordfish', 75012, 184905, 102844080, 368181806, 'Tape Shrimp', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Framewise Filmline Coelacanth', 79486, 222959, 110872800, 498927600, 'Cue Beetle', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Sundial Backdrop Leviathan', 83961, 264057, 118901520, 644446238, 'Cinema Roe', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Flicker Spotlight Guppy', 88435, 308197, 126930240, 337634438, 'Carbon Larva', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Monochrome Smelt', 92910, 355379, 134958960, 483153077, 'Stage Cricket', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Lantern Cuecurrent Shiner', 97384, 405604, 142987680, 643444560, 'Spotlight Fry', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Oldhouse Storyboard Perch', 101858, 216449, 151016400, 818508888, 'Shadow Worm', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Cine Roll Carp', 106333, 262110, 159045120, 423060019, 'Celluloid Gnat', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Studio Matte Pike', 110807, 310814, 167073840, 598124347, 'Velvet Moth', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'apotheosis', 'Archive Exposure Catfish', 115282, 362561, 175102560, 787961520, 'Lensfly', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Silvergrain-Cutline Ray', 113120, 397051, 176103200, 549441984, 'Silver Worm', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Projector Splice Arowana', 122735, 472531, 198653000, 802558120, 'Reel Grub', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Velvet Mackerel', 132350, 554548, 221202800, 1097165888, 'Dustfly', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Noir Vignette Marlin', 141966, 305226, 243752600, 536255720, 'Splice Nymph', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Reelbound Filmline Shark', 151581, 377436, 266302400, 830863488, 'Tape Shrimp', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Framewise Backdrop Tuna', 161196, 456185, 288852200, 1166962888, 'Cue Beetle', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Sundial Spotlight Minnow', 170811, 541472, 311402000, 1544553920, 'Cinema Roe', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Flicker Dissolve Loach', 180426, 633297, 333951800, 734693960, 'Carbon Larva', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Monochrome Darter', 190042, 731660, 356501600, 1112284992, 'Stage Cricket', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Lantern Storyboard Chub', 199657, 836562, 379051400, 1531367656, 'Spotlight Fry', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Oldhouse Roll Bream', 209272, 449935, 401601200, 1991941952, 'Shadow Worm', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Cine Matte Trout', 218887, 545029, 424151000, 933132200, 'Celluloid Gnat', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Studio Exposure Gar', 228502, 646662, 446700800, 1393706496, 'Velvet Moth', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Archive Reelfin Snapper', 238118, 754833, 469250600, 1895772424, 'Lensfly', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'absolute', 'Sepia Eel', 247733, 869542, 491800400, 2439329984, 'Lamp Midge', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Projector Stillwater Barracuda', 241920, 937440, 495411200, 1773572096, 'Reel Grub', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Velvet Salmon', 262483, 1106367, 558848000, 2514816000, 'Dustfly', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Noir Filmline Swordfish', 283046, 615626, 622284800, 3372783616, 'Splice Nymph', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Reelbound Backdrop Coelacanth', 303610, 763578, 685721600, 1824019456, 'Tape Shrimp', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Framewise Spotlight Leviathan', 324173, 925513, 749158400, 2681987072, 'Cue Beetle', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Sundial Dissolve Guppy', 344736, 1101432, 812595200, 3656678400, 'Cinema Roe', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Flicker Cuecurrent Smelt', 365299, 1291333, 876032000, 4748093440, 'Carbon Larva', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Monochrome Shiner', 385862, 1495217, 939468800, 2498987008, 'Stage Cricket', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Lantern Roll Perch', 406426, 1713084, 1002905600, 3590402048, 'Spotlight Fry', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Oldhouse Matte Carp', 426989, 928701, 1066342400, 4798540800, 'Shadow Worm', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Cine Exposure Pike', 447552, 1125593, 1129779200, 6123403264, 'Celluloid Gnat', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Studio Reelfin Catfish', 468115, 1336469, 1193216000, 3173954560, 'Velvet Moth', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Archive Frame Grouper', 488678, 1561327, 1256652800, 4498817024, 'Lensfly', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Sepia Sturgeon', 509242, 1800169, 1320089600, 5940403200, 'Lamp Midge', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'singularity', 'Silvergrain Splice Manta', 529805, 2052994, 1383526400, 7498713088, 'Silver Worm', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Velvet Marlin', 518560, 2198694, 1393344000, 5629109760, 'Dustfly', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Noir Backdrop Shark', 562638, 1237803, 1571760000, 7795929600, 'Splice Nymph', 'Responds to rhythmic line taps.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Reelbound Spotlight Tuna', 606715, 1541057, 1750176000, 3850387200, 'Tape Shrimp', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Framewise Dissolve Minnow', 650793, 1874283, 1928592000, 6017207040, 'Cue Beetle', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Sundial Cuecurrent Loach', 694870, 2237483, 2107008000, 8512312320, 'Cinema Roe', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Flicker Storyboard Darter', 738948, 2630655, 2285424000, 11335703040, 'Carbon Larva', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Monochrome Chub', 783026, 3053800, 2463840000, 5420448000, 'Stage Cricket', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Lantern Matte Bream', 827103, 3506918, 2642256000, 8243838720, 'Spotlight Fry', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Oldhouse Exposure Trout', 871181, 1916598, 2820672000, 11395514880, 'Shadow Worm', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Cine Reelfin Gar', 915258, 2324756, 2999088000, 14875476480, 'Celluloid Gnat', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Studio Frame Snapper', 959336, 2762888, 3177504000, 6990508800, 'Velvet Moth', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Archive Cutline Eel', 1003414, 3230992, 3355920000, 10470470400, 'Lensfly', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Sepia Ray', 1047491, 3729069, 3534336000, 14278717440, 'Lamp Midge', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Silvergrain Stillwater Arowana', 1091569, 4257118, 3712752000, 18415249920, 'Silver Worm', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'paradox', 'Projector-Vignette Mackerel', 1135646, 4815141, 3891168000, 8560569600, 'Reel Grub', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Noir Spotlight Coelacanth', 1111040, 2472064, 3928456000, 17678052000, 'Splice Nymph', 'Avoids sudden white-light flashes.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Reelbound Dissolve Leviathan', 1205478, 3092052, 4431490000, 24018675800, 'Tape Shrimp', 'Tracks prey by contrast edges.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Framewise Cuecurrent Guppy', 1299917, 3776258, 4934524000, 13125833840, 'Cue Beetle', 'Schools in synchronized frame beats.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Sundial Storyboard Smelt', 1394355, 4524683, 5437558000, 19466457640, 'Cinema Roe', 'Surges during evening hush periods.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Flicker Roll Shiner', 1488794, 5337325, 5940592000, 26732664000, 'Carbon Larva', 'Leaves faint ripple trails like film scratches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Monochrome Perch', 1583232, 6214186, 6443626000, 34924452920, 'Stage Cricket', 'Rests near quiet cavern screens.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Lantern Exposure Carp', 1677670, 7155264, 6946660000, 18478115600, 'Spotlight Fry', 'Turns copper-toned at first light.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Oldhouse Reelfin Pike', 1772109, 3942942, 7449694000, 26669904520, 'Shadow Worm', 'Moves in quick stop-motion bursts.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Cine Frame Catfish', 1866547, 4787694, 7952728000, 35787276000, 'Celluloid Gnat', 'Most active when ambient light is low.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Studio Cutline Grouper', 1960986, 5696663, 8455762000, 45830230040, 'Velvet Moth', 'Scales shimmer like silver film grain.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Archive Splice Sturgeon', 2055424, 6669851, 8958796000, 23830397360, 'Lensfly', 'Often circles old projector vents.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Sepia Manta', 2149862, 7707257, 9461830000, 33873351400, 'Lamp Midge', 'Bites on steady reel cadence.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Silvergrain Vignette Barracuda', 2244301, 8808881, 9964864000, 44841888000, 'Silver Worm', 'Can fade into sepia shadows.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Projector-Filmline Salmon', 2338739, 9974723, 10467898000, 56736007160, 'Reel Grub', 'Prefers deep pools under stone arches.'),
  ('celluloid_cenote', 'Celluloid Cenote', 'null', 'Velvet Backdrop Swordfish', 2433178, 5413820, 10970932000, 29182679120, 'Dustfly', 'Responds to rhythmic line taps.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Atlas Minnow', 0.21, 0.59, 9.37, 33.55, 'Ink Worm', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Meridian Mapfin Loach', 0.23, 0.72, 10.57, 47.58, 'Compass Midge', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Compass Gridline Darter', 0.25, 0.86, 11.77, 63.81, 'Parchment Fry', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Parchment Sounding Chub', 0.27, 1.01, 12.97, 34.51, 'Mapleaf Grub', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Sounding Waypoint Bream', 0.28, 0.5, 14.17, 50.74, 'Harbor Shrimp', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Longitude Currentline Trout', 0.3, 0.63, 15.37, 69.18, 'Reef Beetle', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Latitude Gar', 0.32, 0.78, 16.57, 89.83, 'Chart Nymph', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Wayfinder Northline Snapper', 0.34, 0.94, 17.77, 47.28, 'Waypoint Roe', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Surveyor-Truecourse Eel', 0.36, 1.11, 18.97, 67.93, 'Brassfly', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Draftline Coastline Ray', 0.37, 1.29, 20.17, 90.78, 'Coast Cricket', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Mariner Bearing Arowana', 0.39, 1.49, 21.37, 116, 'Tide Larva', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Charted Meridian Mackerel', 0.41, 0.72, 22.57, 60.05, 'Lineworm', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Harbor Marlin', 0.43, 0.9, 23.77, 85.11, 'Rose Moth', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Inkline Chartwater Shark', 0.45, 1.09, 24.97, 112, 'Anchor Gnat', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'common', 'Rosewind Landfall Tuna', 0.47, 1.29, 26.17, 142, 'Survey Fly', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Meridian Gridline Smelt', 0.73, 2.29, 27.08, 109, 'Compass Midge', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Compass Sounding Shiner', 0.79, 2.76, 30.54, 151, 'Parchment Fry', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Parchment Waypoint Perch', 0.86, 3.27, 34.01, 74.82, 'Mapleaf Grub', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Sounding Currentline Carp', 0.92, 1.63, 37.48, 117, 'Harbor Shrimp', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Longitude Plotter Pike', 0.98, 2.07, 40.94, 165, 'Reef Beetle', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Latitude Catfish', 1.04, 2.56, 44.41, 220, 'Chart Nymph', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Wayfinder Truecourse Grouper', 1.1, 3.09, 47.88, 105, 'Waypoint Roe', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Surveyor-Coastline Sturgeon', 1.17, 3.66, 51.35, 160, 'Brassfly', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Draftline Bearing Manta', 1.23, 4.27, 54.81, 221, 'Coast Cricket', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Mariner Meridian Barracuda', 1.29, 4.93, 58.28, 289, 'Tide Larva', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Charted Contour Salmon', 1.35, 2.4, 61.75, 136, 'Lineworm', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Harbor Swordfish', 1.42, 2.99, 65.21, 203, 'Rose Moth', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Inkline Landfall Coelacanth', 1.48, 3.63, 68.68, 277, 'Anchor Gnat', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Rosewind Seamark Leviathan', 1.54, 4.3, 72.15, 358, 'Survey Fly', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'uncommon', 'Atlas Mapfin Guppy', 1.6, 5.02, 75.62, 166, 'Ink Worm', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Compass Waypoint Chub', 1.83, 6.4, 85.39, 384, 'Parchment Fry', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Parchment Currentline Bream', 1.98, 7.62, 96.33, 522, 'Mapleaf Grub', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Sounding Plotter Trout', 2.14, 3.85, 107, 285, 'Harbor Shrimp', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Longitude Northline Gar', 2.3, 4.91, 118, 423, 'Reef Beetle', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Latitude Snapper', 2.45, 6.08, 129, 581, 'Chart Nymph', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Wayfinder Coastline Eel', 2.61, 7.35, 140, 759, 'Waypoint Roe', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Surveyor-Bearing Ray', 2.76, 8.73, 151, 402, 'Brassfly', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Draftline Meridian Arowana', 2.92, 10.21, 162, 580, 'Coast Cricket', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Mariner Contour Mackerel', 3.07, 11.8, 173, 778, 'Tide Larva', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Charted Chartwater Marlin', 3.23, 5.81, 184, 996, 'Lineworm', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Harbor Shark', 3.38, 7.24, 195, 518, 'Rose Moth', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Inkline Seamark Tuna', 3.54, 8.78, 206, 736, 'Anchor Gnat', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Rosewind Mapfin Minnow', 3.69, 10.42, 217, 975, 'Survey Fly', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Atlas Gridline Loach', 3.85, 12.17, 228, 1233, 'Ink Worm', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'rare', 'Meridian-Sounding Darter', 4.01, 14.02, 238, 634, 'Compass Midge', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Parchment Plotter Carp', 4.84, 18.7, 260, 1291, 'Mapleaf Grub', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Sounding Northline Pike', 5.25, 9.58, 294, 646, 'Harbor Shrimp', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Longitude Truecourse Catfish', 5.66, 12.25, 327, 1020, 'Reef Beetle', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Latitude Grouper', 6.07, 15.21, 360, 1456, 'Chart Nymph', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Wayfinder Bearing Sturgeon', 6.48, 18.44, 394, 1953, 'Waypoint Roe', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Surveyor-Meridian Manta', 6.89, 21.96, 427, 939, 'Brassfly', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Draftline Contour Barracuda', 7.31, 25.75, 460, 1436, 'Coast Cricket', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Mariner Chartwater Salmon', 7.72, 29.82, 494, 1995, 'Tide Larva', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Charted Landfall Swordfish', 8.13, 14.83, 527, 2614, 'Lineworm', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Harbor Coelacanth', 8.54, 18.49, 560, 1233, 'Rose Moth', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Inkline Mapfin Leviathan', 8.95, 22.42, 594, 1852, 'Anchor Gnat', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Rosewind Gridline Guppy', 9.36, 26.63, 627, 2533, 'Survey Fly', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Atlas Sounding Smelt', 9.77, 31.13, 660, 3276, 'Ink Worm', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Meridian-Waypoint Shiner', 10.18, 35.9, 694, 1526, 'Compass Midge', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'epic', 'Compass Currentline Perch', 10.6, 40.95, 727, 2268, 'Parchment Fry', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Sounding Truecourse Gar', 12.74, 23.58, 771, 4177, 'Harbor Shrimp', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Longitude Coastline Snapper', 13.83, 30.28, 869, 2312, 'Reef Beetle', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Latitude Eel', 14.91, 37.72, 968, 3465, 'Chart Nymph', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Wayfinder Meridian Ray', 15.99, 45.9, 1067, 4800, 'Waypoint Roe', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Surveyor-Contour Arowana', 17.08, 54.82, 1165, 6316, 'Brassfly', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Draftline Chartwater Mackerel', 18.16, 64.47, 1264, 3362, 'Coast Cricket', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Mariner Landfall Marlin', 19.24, 74.86, 1363, 4879, 'Tide Larva', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Charted Seamark Shark', 20.33, 37.6, 1461, 6576, 'Lineworm', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Harbor Tuna', 21.41, 46.89, 1560, 8456, 'Rose Moth', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Inkline Gridline Minnow', 22.49, 56.91, 1659, 4412, 'Anchor Gnat', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Rosewind Sounding Loach', 23.58, 67.66, 1757, 6292, 'Survey Fly', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Atlas Waypoint Darter', 24.66, 79.16, 1856, 8352, 'Ink Worm', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Meridian-Currentline Chub', 25.74, 91.39, 1955, 10595, 'Compass Midge', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Compass Plotter Bream', 26.83, 104, 2053, 5462, 'Parchment Fry', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'legendary', 'Parchment Trout', 27.91, 51.63, 2152, 7705, 'Mapleaf Grub', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Longitude Bearing Grouper', 28.32, 62.73, 2187, 4811, 'Reef Beetle', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Latitude Sturgeon', 30.73, 78.51, 2467, 7697, 'Chart Nymph', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Wayfinder Contour Manta', 33.13, 95.92, 2747, 11098, 'Waypoint Roe', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Surveyor-Chartwater Barracuda', 35.54, 115, 3027, 15014, 'Brassfly', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Draftline Landfall Salmon', 37.95, 136, 3307, 7276, 'Coast Cricket', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Mariner Seamark Swordfish', 40.36, 158, 3587, 11192, 'Tide Larva', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Charted Mapfin Coelacanth', 42.76, 80.18, 3867, 15623, 'Lineworm', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Harbor Leviathan', 45.17, 100, 4147, 20570, 'Rose Moth', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Inkline Sounding Guppy', 47.58, 122, 4427, 9740, 'Anchor Gnat', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Rosewind Waypoint Smelt', 49.98, 145, 4707, 14687, 'Survey Fly', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Atlas Currentline Shiner', 52.39, 169, 4987, 20149, 'Ink Worm', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Meridian-Plotter Perch', 54.8, 196, 5267, 26126, 'Compass Midge', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Compass Northline Carp', 57.21, 224, 5547, 12204, 'Parchment Fry', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Parchment Pike', 59.61, 112, 5827, 18181, 'Mapleaf Grub', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'liminal', 'Sounding Coastline Catfish', 62.02, 137, 6107, 24674, 'Harbor Shrimp', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Latitude Ray', 61.36, 158, 6144, 16344, 'Chart Nymph', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Wayfinder Chartwater Arowana', 66.58, 194, 6931, 24813, 'Waypoint Roe', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Surveyor-Landfall Mackerel', 71.79, 234, 7718, 34730, 'Brassfly', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Draftline Seamark Marlin', 77.01, 277, 8505, 46095, 'Coast Cricket', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Mariner Mapfin Shark', 82.22, 324, 9291, 24715, 'Tide Larva', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Charted Gridline Tuna', 87.44, 166, 10078, 36080, 'Lineworm', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Harbor Minnow', 92.65, 208, 10865, 48892, 'Rose Moth', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Inkline Waypoint Loach', 97.87, 253, 11652, 63152, 'Anchor Gnat', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Rosewind Currentline Darter', 103, 301, 12438, 33086, 'Survey Fly', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Atlas Plotter Chub', 108, 353, 13225, 47346, 'Ink Worm', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Meridian-Northline Bream', 114, 409, 14012, 63054, 'Compass Midge', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Compass Truecourse Trout', 119, 468, 14799, 80209, 'Parchment Fry', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Parchment Gar', 124, 235, 15585, 41457, 'Mapleaf Grub', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Sounding Bearing Snapper', 129, 289, 16372, 58612, 'Harbor Shrimp', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'mythic', 'Longitude Meridian Eel', 134, 347, 17159, 77215, 'Reef Beetle', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Wayfinder Landfall Barracuda', 132, 389, 17496, 54586, 'Waypoint Roe', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Surveyor-Seamark Salmon', 143, 471, 19736, 79733, 'Brassfly', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Draftline Mapfin Swordfish', 155, 561, 21976, 109001, 'Coast Cricket', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Mariner Gridline Coelacanth', 166, 658, 24216, 53276, 'Tide Larva', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Charted Sounding Leviathan', 177, 341, 26457, 82545, 'Lineworm', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Harbor Guppy', 188, 427, 28697, 115936, 'Rose Moth', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Inkline Currentline Smelt', 200, 520, 30937, 153449, 'Anchor Gnat', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Rosewind Plotter Shiner', 211, 621, 33177, 72990, 'Survey Fly', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Atlas Northline Perch', 222, 729, 35418, 110503, 'Ink Worm', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Meridian-Truecourse Carp', 233, 846, 37658, 152138, 'Compass Midge', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Compass Coastline Pike', 244, 969, 39898, 197896, 'Parchment Fry', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Parchment Catfish', 256, 492, 42139, 92705, 'Mapleaf Grub', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Sounding Meridian Grouper', 267, 605, 44379, 138462, 'Harbor Shrimp', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Longitude Contour Sturgeon', 278, 725, 46619, 188341, 'Reef Beetle', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'ascendant', 'Latitude Chartwater Manta', 289, 852, 48859, 242343, 'Chart Nymph', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Surveyor-Mapfin Marlin', 277, 918, 48946, 175226, 'Brassfly', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Draftline Gridline Shark', 301, 1098, 55213, 248460, 'Coast Cricket', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Mariner Sounding Tuna', 324, 1295, 61481, 333225, 'Tide Larva', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Charted Waypoint Minnow', 348, 679, 67748, 180210, 'Lineworm', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Harbor Loach', 372, 851, 74016, 264976, 'Rose Moth', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Inkline Plotter Darter', 395, 1039, 80283, 361274, 'Anchor Gnat', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Rosewind Northline Chub', 419, 1244, 86551, 469104, 'Survey Fly', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Atlas Truecourse Bream', 442, 1464, 92818, 246896, 'Ink Worm', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Meridian-Coastline Trout', 466, 1700, 99085, 354726, 'Compass Midge', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Compass Bearing Gar', 489, 1953, 105353, 474088, 'Parchment Fry', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Parchment Snapper', 513, 1000, 111620, 604982, 'Mapleaf Grub', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Sounding Contour Eel', 537, 1229, 117888, 313581, 'Harbor Shrimp', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Longitude Chartwater Ray', 560, 1473, 124155, 444476, 'Reef Beetle', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Latitude Landfall Arowana', 584, 1734, 130423, 586902, 'Chart Nymph', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'celestial', 'Wayfinder Seamark Mackerel', 607, 2010, 136690, 740860, 'Waypoint Roe', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Draftline Sounding Coelacanth', 584, 2147, 137465, 555358, 'Coast Cricket', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Mariner Waypoint Leviathan', 634, 2545, 155067, 769132, 'Tide Larva', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Charted Currentline Guppy', 683, 1350, 172669, 379872, 'Lineworm', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Harbor Smelt', 733, 1697, 190271, 593647, 'Rose Moth', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Inkline Northline Shiner', 783, 2078, 207874, 839809, 'Anchor Gnat', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Rosewind Truecourse Perch', 832, 2493, 225476, 1118360, 'Survey Fly', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Atlas Coastline Carp', 882, 2941, 243078, 534772, 'Ink Worm', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Meridian-Bearing Pike', 932, 3424, 260680, 813322, 'Compass Midge', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Compass Meridian Catfish', 981, 3940, 278282, 1124261, 'Parchment Fry', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Parchment Grouper', 1031, 2036, 295885, 1467588, 'Mapleaf Grub', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Sounding Chartwater Sturgeon', 1081, 2502, 313487, 689671, 'Harbor Shrimp', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Longitude Landfall Manta', 1130, 3001, 331089, 1032998, 'Reef Beetle', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Latitude Seamark Barracuda', 1180, 3534, 348691, 1408712, 'Chart Nymph', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Wayfinder Mapfin Salmon', 1230, 4100, 366293, 1816815, 'Waypoint Roe', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eldritch', 'Surveyor Gridline Swordfish', 1279, 4701, 383896, 844570, 'Brassfly', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Mariner Currentline Minnow', 1239, 5006, 385318, 1733931, 'Tide Larva', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Charted Plotter Loach', 1344, 2689, 434657, 2355844, 'Lineworm', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Harbor Darter', 1450, 3392, 483997, 1287432, 'Rose Moth', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Inkline Truecourse Chub', 1555, 4167, 533337, 1909345, 'Anchor Gnat', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Rosewind Coastline Bream', 1660, 5014, 582676, 2622042, 'Survey Fly', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Atlas Bearing Trout', 1766, 5932, 632016, 3425524, 'Ink Worm', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Meridian-Meridian Gar', 1871, 6922, 681355, 1812404, 'Compass Midge', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Compass Contour Snapper', 1976, 7984, 730695, 2615886, 'Parchment Fry', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Parchment Eel', 2082, 4163, 780034, 3510153, 'Mapleaf Grub', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Sounding Landfall Ray', 2187, 5117, 829374, 4495204, 'Harbor Shrimp', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Longitude Seamark Arowana', 2292, 6143, 878713, 2337377, 'Reef Beetle', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Latitude Mapfin Mackerel', 2397, 7240, 928053, 3322428, 'Chart Nymph', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Wayfinder Gridline Marlin', 2503, 8409, 977392, 4398264, 'Waypoint Roe', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Surveyor Sounding Shark', 2608, 9650, 1026732, 5564885, 'Brassfly', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'eternal', 'Draftline Tuna', 2713, 10962, 1076071, 2862349, 'Coast Cricket', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Charted Northline Smelt', 2643, 5352, 1083056, 5371958, 'Lineworm', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Harbor Shiner', 2868, 6783, 1221740, 2687828, 'Rose Moth', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Inkline Coastline Perch', 3093, 8365, 1360424, 4244523, 'Anchor Gnat', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Rosewind Bearing Carp', 3317, 10101, 1499108, 6056396, 'Survey Fly', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Atlas Meridian Pike', 3542, 11989, 1637792, 8123448, 'Ink Worm', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Meridian-Contour Catfish', 3767, 14030, 1776476, 3908247, 'Compass Midge', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Compass Chartwater Grouper', 3991, 16224, 1915160, 5975299, 'Parchment Fry', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Parchment Sturgeon', 4216, 8537, 2053844, 8297530, 'Mapleaf Grub', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Sounding Seamark Manta', 4441, 10502, 2192528, 10874939, 'Harbor Shrimp', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Longitude Mapfin Barracuda', 4665, 12619, 2331212, 5128666, 'Reef Beetle', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Latitude Gridline Salmon', 4890, 14890, 2469896, 7706076, 'Chart Nymph', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Wayfinder Sounding Swordfish', 5115, 17313, 2608580, 10538663, 'Waypoint Roe', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Surveyor Waypoint Coelacanth', 5339, 19889, 2747264, 13626429, 'Brassfly', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Draftline Leviathan', 5564, 22617, 2885948, 6349086, 'Coast Cricket', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'divine', 'Mariner Plotter Guppy', 5789, 11722, 3024632, 9436852, 'Tide Larva', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Harbor Chub', 5664, 13537, 3040888, 16481613, 'Rose Moth', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Inkline Bearing Bream', 6145, 16777, 3430270, 9124518, 'Anchor Gnat', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Rosewind Meridian Trout', 6627, 20345, 3819652, 13674354, 'Survey Fly', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Atlas Contour Gar', 7108, 24239, 4209034, 18940653, 'Ink Worm', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Meridian-Chartwater Snapper', 7590, 28462, 4598416, 24923415, 'Compass Midge', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Compass Landfall Eel', 8071, 33011, 4987798, 13267543, 'Parchment Fry', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Parchment Ray', 8553, 17533, 5377180, 19250304, 'Mapleaf Grub', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Sounding Mapfin Arowana', 9034, 21591, 5766562, 25949529, 'Harbor Shrimp', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Longitude Gridline Mackerel', 9516, 25977, 6155944, 33365216, 'Reef Beetle', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Latitude Sounding Marlin', 9997, 30691, 6545326, 17410567, 'Chart Nymph', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Wayfinder Waypoint Shark', 10478, 35731, 6934708, 24826255, 'Waypoint Roe', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Surveyor Currentline Tuna', 10960, 41099, 7324090, 32958405, 'Brassfly', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Draftline Minnow', 11441, 46795, 7713472, 41807018, 'Coast Cricket', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Mariner Northline Loach', 11923, 24442, 8102854, 21553592, 'Tide Larva', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'cosmic', 'Charted Truecourse Darter', 12404, 29646, 8492236, 30402205, 'Lineworm', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Inkline Meridian Carp', 12036, 33159, 8560308, 18832678, 'Anchor Gnat', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Rosewind Contour Pike', 13059, 40418, 9656445, 30128108, 'Survey Fly', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Atlas Chartwater Catfish', 14082, 48372, 10752582, 43440431, 'Ink Worm', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Meridian-Landfall Grouper', 15105, 57022, 11848719, 58769646, 'Compass Midge', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Compass Seamark Sturgeon', 16128, 66368, 12944856, 28478683, 'Parchment Fry', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Parchment Manta', 17151, 35589, 14040993, 43807898, 'Mapleaf Grub', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Sounding Gridline Barracuda', 18174, 43891, 15137130, 61154005, 'Harbor Shrimp', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Longitude Sounding Salmon', 19197, 52889, 16233267, 80517004, 'Reef Beetle', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Latitude Waypoint Swordfish', 20220, 62582, 17329404, 38124689, 'Chart Nymph', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Wayfinder Currentline Coelacanth', 21244, 72972, 18425541, 57487688, 'Waypoint Roe', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Surveyor Plotter Leviathan', 22267, 84056, 19521678, 78867579, 'Brassfly', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Draftline Guppy', 23290, 95837, 20617815, 102264362, 'Coast Cricket', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Mariner Truecourse Smelt', 24313, 50449, 21713952, 47770694, 'Tide Larva', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Charted Coastline Shiner', 25336, 61186, 22810089, 71167478, 'Lineworm', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'primordial', 'Harbor Bearing Perch', 26359, 72619, 23906226, 96581153, 'Rose Moth', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Rosewind Chartwater Gar', 25960, 80995, 24056340, 63989864, 'Survey Fly', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Atlas Landfall Snapper', 28167, 97456, 27136725, 97149475, 'Ink Worm', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Meridian-Seamark Eel', 30373, 115418, 30217110, 135976995, 'Compass Midge', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Compass Mapfin Ray', 32580, 134880, 33297495, 180472423, 'Parchment Fry', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Parchment Arowana', 34786, 73051, 36377880, 96765161, 'Mapleaf Grub', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Sounding Sounding Mackerel', 36993, 90263, 39458265, 141260589, 'Harbor Shrimp', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Longitude Waypoint Marlin', 39200, 108975, 42538650, 191423925, 'Reef Beetle', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Latitude Currentline Shark', 41406, 129187, 45619035, 247255170, 'Chart Nymph', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Wayfinder Plotter Tuna', 43613, 150900, 48699420, 129540457, 'Waypoint Roe', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Surveyor Northline Minnow', 45819, 174114, 51779805, 185371702, 'Brassfly', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Draftline Loach', 48026, 198828, 54860190, 246870855, 'Coast Cricket', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Mariner Coastline Darter', 50233, 105488, 57940575, 314037917, 'Tide Larva', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Charted Bearing Chub', 52439, 127952, 61020960, 162315754, 'Lineworm', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Harbor Meridian Bream', 54646, 151915, 64101345, 229482815, 'Rose Moth', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'transcendent', 'Inkline Contour Trout', 56852, 177379, 67181730, 302317785, 'Anchor Gnat', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Atlas Seamark Grouper', 55460, 193278, 67482720, 210546086, 'Ink Worm', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Meridian-Mapfin Sturgeon', 60174, 230166, 76123800, 307540152, 'Compass Midge', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Compass Gridline Manta', 64888, 270259, 84764880, 420433805, 'Parchment Fry', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Parchment Barracuda', 69602, 147905, 93405960, 205493112, 'Mapleaf Grub', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Sounding Waypoint Salmon', 74316, 183190, 102047040, 318386765, 'Harbor Shrimp', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Longitude Currentline Swordfish', 79031, 221681, 110688120, 447180005, 'Reef Beetle', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Latitude Plotter Coelacanth', 83745, 263377, 119329200, 591872832, 'Chart Nymph', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Wayfinder Northline Leviathan', 88459, 308279, 127970280, 281534616, 'Waypoint Roe', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Surveyor Truecourse Guppy', 93173, 356386, 136611360, 426227443, 'Brassfly', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Draftline Smelt', 97887, 407699, 145252440, 586819858, 'Coast Cricket', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Mariner Bearing Shiner', 102601, 218027, 153893520, 763311859, 'Tide Larva', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Charted Meridian Perch', 107315, 264532, 162534600, 357576120, 'Lineworm', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Harbor Contour Carp', 112029, 314242, 171175680, 534068122, 'Rose Moth', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Inkline Chartwater Pike', 116743, 367158, 179816760, 726459710, 'Anchor Gnat', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'apotheosis', 'Rosewind Landfall Catfish', 121457, 423279, 188457840, 934750886, 'Survey Fly', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Meridian-Gridline Ray', 119180, 458843, 189534800, 678534584, 'Compass Midge', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Compass Sounding Arowana', 129310, 541810, 213804500, 962120250, 'Parchment Fry', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Parchment Mackerel', 139441, 299797, 238074200, 1290362164, 'Mapleaf Grub', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Sounding Currentline Marlin', 149571, 372432, 262343900, 697834774, 'Harbor Shrimp', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Longitude Plotter Shark', 159701, 451954, 286613600, 1026076688, 'Reef Beetle', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Latitude Northline Tuna', 169832, 538366, 310883300, 1398974850, 'Chart Nymph', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Wayfinder Truecourse Minnow', 179962, 631666, 335153000, 1816529260, 'Waypoint Roe', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Surveyor Coastline Loach', 190092, 731855, 359422700, 956064382, 'Brassfly', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Draftline Darter', 200222, 838932, 383692400, 1373618792, 'Coast Cricket', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Mariner Meridian Chub', 210353, 452258, 407962100, 1835829450, 'Tide Larva', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Charted Contour Bream', 220483, 549003, 432231800, 2342696356, 'Lineworm', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Harbor Chartwater Trout', 230613, 652636, 456501500, 1214293990, 'Rose Moth', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Inkline Landfall Gar', 240744, 763157, 480771200, 1721160896, 'Anchor Gnat', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Rosewind Seamark Snapper', 250874, 880567, 505040900, 2272684050, 'Survey Fly', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'absolute', 'Atlas Eel', 261004, 1004866, 529310600, 2868863452, 'Ink Worm', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Compass Waypoint Barracuda', 254880, 1074319, 533196800, 2154115072, 'Parchment Fry', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Parchment Salmon', 276545, 601485, 601472000, 2983301120, 'Mapleaf Grub', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Sounding Plotter Swordfish', 298210, 749997, 669747200, 1473443840, 'Harbor Shrimp', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Longitude Northline Coelacanth', 319874, 913241, 738022400, 2302629888, 'Reef Beetle', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Latitude Truecourse Leviathan', 341539, 1091218, 806297600, 3257442304, 'Chart Nymph', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Wayfinder Coastline Guppy', 363204, 1283926, 874572800, 4337881088, 'Waypoint Roe', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Surveyor Bearing Smelt', 384869, 1491367, 942848000, 2074265600, 'Brassfly', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Draftline Shiner', 406534, 1713539, 1011123200, 3154704384, 'Coast Cricket', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Mariner Contour Perch', 428198, 931332, 1079398400, 4360769536, 'Tide Larva', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Charted Chartwater Carp', 449863, 1131406, 1147673600, 5692461056, 'Lineworm', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Harbor Landfall Pike', 471528, 1346212, 1215948800, 2675087360, 'Rose Moth', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Inkline Seamark Catfish', 493193, 1575751, 1284224000, 4006778880, 'Anchor Gnat', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Rosewind Mapfin Grouper', 514858, 1820022, 1352499200, 5464096768, 'Survey Fly', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Atlas Sturgeon', 536522, 2079024, 1420774400, 7047041024, 'Ink Worm', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'singularity', 'Meridian Sounding Manta', 558187, 2352759, 1489049600, 3275909120, 'Compass Midge', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Parchment Marlin', 546340, 1201948, 1499616000, 6748272000, 'Mapleaf Grub', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Sounding Northline Shark', 592779, 1505658, 1691640000, 9168688800, 'Harbor Shrimp', 'Most active during calm tide windows.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Longitude Truecourse Tuna', 639218, 1840947, 1883664000, 5010546240, 'Reef Beetle', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Latitude Coastline Minnow', 685657, 2207815, 2075688000, 7430963040, 'Chart Nymph', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Wayfinder Bearing Loach', 732096, 2606260, 2267712000, 10204704000, 'Waypoint Roe', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Surveyor Meridian Darter', 778535, 3036285, 2459736000, 13331769120, 'Brassfly', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Draftline Chub', 824973, 3497887, 2651760000, 7053681600, 'Coast Cricket', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Mariner Chartwater Bream', 871412, 1917107, 2843784000, 10180746720, 'Tide Larva', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Charted Landfall Trout', 917851, 2331342, 3035808000, 13661136000, 'Lineworm', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Harbor Seamark Gar', 964290, 2777155, 3227832000, 17494849440, 'Rose Moth', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Inkline Mapfin Snapper', 1010729, 3254547, 3419856000, 9096816960, 'Anchor Gnat', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Rosewind Gridline Eel', 1057168, 3763518, 3611880000, 12930530400, 'Survey Fly', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Atlas Ray', 1103607, 4304067, 3803904000, 17117568000, 'Ink Worm', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Meridian Waypoint Arowana', 1150046, 4876194, 3995928000, 21657929760, 'Compass Midge', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'paradox', 'Compass-Currentline Mackerel', 1196485, 2632266, 4187952000, 11139952320, 'Parchment Fry', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Sounding Truecourse Coelacanth', 1170560, 3002486, 4228084000, 20971296640, 'Harbor Shrimp', 'Responds to steady compass reel rhythm.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Longitude Coastline Leviathan', 1270058, 3689517, 4769485000, 10492867000, 'Reef Beetle', 'Often found near ink-dark channels.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Latitude Bearing Guppy', 1369555, 4444207, 5310886000, 16569964320, 'Chart Nymph', 'Uses reef ridges like coastlines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Wayfinder Meridian Smelt', 1469053, 5266554, 5852287000, 23643239480, 'Waypoint Roe', 'Runs long before turning broadside.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Surveyor Contour Shiner', 1568550, 6156560, 6393688000, 31712692480, 'Brassfly', 'Spawns near sheltered harbor inlets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Draftline Perch', 1668048, 7114225, 6935089000, 15257195800, 'Coast Cricket', 'Favors clean lines over turbulent water.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Mariner Landfall Carp', 1767546, 3932789, 7476490000, 23326648800, 'Tide Larva', 'Leaves wake patterns like chart marks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Charted Seamark Pike', 1867043, 4788966, 8017891000, 32392279640, 'Lineworm', 'Prefers currents that follow contour lines.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Harbor Mapfin Catfish', 1966541, 5712801, 8559292000, 42454088320, 'Rose Moth', 'Schools along invisible meridian bands.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Inkline Gridline Grouper', 2066038, 6704295, 9100693000, 20021524600, 'Anchor Gnat', 'Bites hardest near shifting map edges.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Rosewind Sounding Sturgeon', 2165536, 7763447, 9642094000, 30083333280, 'Survey Fly', 'Tracks magnetic drift with precision.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Atlas Manta', 2265034, 8890257, 10183495000, 41141319800, 'Ink Worm', 'Holds near deep sounding pockets.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Meridian Currentline Barracuda', 2364531, 10084726, 10724896000, 53195484160, 'Compass Midge', 'Turns parchment-gold in sunset light.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Compass-Plotter Salmon', 2464029, 5482464, 11266297000, 24785853400, 'Parchment Fry', 'Can reroute suddenly at waypoint breaks.'),
  ('cartographers_cove', 'Cartographer''s Cove', 'null', 'Parchment Northline Swordfish', 2563526, 6575445, 11807698000, 36840017760, 'Mapleaf Grub', 'Most active during calm tide windows.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Lavender Minnow', 0.22, 0.69, 10.04, 40.55, 'Petal Worm', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Rosewater Perfume Loach', 0.24, 0.84, 11.32, 56.16, 'Rose Midge', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Bergamot Aromawave Darter', 0.26, 0.99, 12.61, 27.74, 'Nectar Fry', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Jasmine Mistline Chub', 0.28, 0.49, 13.89, 43.34, 'Pollen Grub', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Citrus Bouquet Bream', 0.3, 0.63, 15.18, 61.32, 'Perfume Shrimp', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Violet Fragrance Trout', 0.32, 0.77, 16.46, 81.66, 'Floral Beetle', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Sandal Gar', 0.34, 0.93, 17.75, 39.05, 'Scent Nymph', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Peony Bloomcrest Snapper', 0.36, 1.11, 19.03, 59.38, 'Dew Roe', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Iris-Scentdrift Eel', 0.37, 1.29, 20.32, 82.09, 'Violet Larva', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Amberbloom Essence Ray', 0.39, 1.49, 21.6, 107, 'Balm Cricket', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Neroli Dewline Arowana', 0.41, 0.72, 22.89, 50.36, 'Citrus Fly', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Vetiver Floral Mackerel', 0.43, 0.9, 24.17, 75.42, 'Oil Gnat', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Magnolia Marlin', 0.45, 1.1, 25.46, 103, 'Bergamot Moth', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Linden Infusion Shark', 0.47, 1.3, 26.74, 133, 'Bloom Pellet', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'common', 'Myrrh Silkspray Tuna', 0.49, 1.52, 28.03, 61.67, 'Amber Worm', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Rosewater Aromawave Smelt', 0.77, 2.67, 29, 130, 'Rose Midge', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Bergamot Mistline Shiner', 0.83, 3.18, 32.71, 177, 'Nectar Fry', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Jasmine Bouquet Perch', 0.9, 1.6, 36.42, 96.88, 'Pollen Grub', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Citrus Fragrance Carp', 0.96, 2.04, 40.13, 144, 'Perfume Shrimp', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Violet Oilcurrent Pike', 1.03, 2.53, 43.85, 197, 'Floral Beetle', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Sandal Catfish', 1.1, 3.06, 47.56, 258, 'Scent Nymph', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Peony Scentdrift Grouper', 1.16, 3.64, 51.27, 136, 'Dew Roe', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Iris-Essence Sturgeon', 1.23, 4.26, 54.98, 197, 'Violet Larva', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Amberbloom Dewline Manta', 1.29, 4.93, 58.7, 264, 'Balm Cricket', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Neroli Floral Barracuda', 1.36, 2.41, 62.41, 338, 'Citrus Fly', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Vetiver Glassbottle Salmon', 1.42, 3.01, 66.12, 176, 'Oil Gnat', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Magnolia Swordfish', 1.49, 3.65, 69.84, 250, 'Bergamot Moth', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Linden Silkspray Coelacanth', 1.55, 4.34, 73.55, 331, 'Bloom Pellet', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Myrrh Petalfin Leviathan', 1.62, 5.07, 77.26, 419, 'Amber Worm', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'uncommon', 'Lavender Perfume Guppy', 1.68, 5.85, 80.97, 215, 'Petal Worm', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Bergamot Bouquet Chub', 1.92, 7.38, 91.45, 454, 'Nectar Fry', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Jasmine Fragrance Bream', 2.09, 3.75, 103, 227, 'Pollen Grub', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Citrus Oilcurrent Trout', 2.25, 4.81, 115, 358, 'Perfume Shrimp', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Violet Bloomcrest Gar', 2.41, 5.98, 127, 511, 'Floral Beetle', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Sandal Snapper', 2.58, 7.26, 138, 686, 'Scent Nymph', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Peony Essence Eel', 2.74, 8.65, 150, 330, 'Dew Roe', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Iris-Dewline Ray', 2.9, 10.16, 162, 505, 'Violet Larva', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Amberbloom Floral Arowana', 3.07, 11.77, 173, 701, 'Balm Cricket', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Neroli Glassbottle Mackerel', 3.23, 5.81, 185, 918, 'Citrus Fly', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Vetiver Infusion Marlin', 3.39, 7.26, 197, 433, 'Oil Gnat', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Magnolia Shark', 3.56, 8.82, 209, 651, 'Bergamot Moth', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Linden Petalfin Tuna', 3.72, 10.49, 220, 890, 'Bloom Pellet', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Myrrh Perfume Minnow', 3.88, 12.27, 232, 1151, 'Amber Worm', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Lavender Aromawave Loach', 4.05, 14.16, 244, 536, 'Petal Worm', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'rare', 'Rosewater-Mistline Darter', 4.21, 16.16, 255, 797, 'Rose Midge', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Jasmine Oilcurrent Carp', 5.08, 9.28, 279, 1511, 'Pollen Grub', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Citrus Bloomcrest Pike', 5.52, 11.94, 314, 837, 'Perfume Shrimp', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Violet Scentdrift Catfish', 5.95, 14.9, 350, 1254, 'Floral Beetle', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Sandal Grouper', 6.38, 18.15, 386, 1737, 'Scent Nymph', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Peony Dewline Sturgeon', 6.81, 21.7, 422, 2285, 'Dew Roe', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Iris-Floral Manta', 7.24, 25.54, 457, 1216, 'Violet Larva', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Amberbloom Glassbottle Barracuda', 7.68, 29.67, 493, 1765, 'Balm Cricket', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Neroli Infusion Salmon', 8.11, 14.8, 529, 2379, 'Citrus Fly', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Vetiver Silkspray Swordfish', 8.54, 18.49, 564, 3059, 'Oil Gnat', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Magnolia Coelacanth', 8.97, 22.48, 600, 1596, 'Bergamot Moth', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Linden Perfume Leviathan', 9.41, 26.76, 636, 2276, 'Bloom Pellet', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Myrrh Aromawave Guppy', 9.84, 31.33, 671, 3022, 'Amber Worm', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Lavender Mistline Smelt', 10.27, 36.2, 707, 3833, 'Petal Worm', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Rosewater-Bouquet Shiner', 10.7, 41.36, 743, 1976, 'Rose Midge', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'epic', 'Bergamot Fragrance Perch', 11.13, 20.32, 779, 2787, 'Nectar Fry', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Citrus Scentdrift Gar', 13.39, 29.33, 825, 1816, 'Perfume Shrimp', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Violet Essence Snapper', 14.53, 36.76, 931, 2904, 'Floral Beetle', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Sandal Eel', 15.67, 44.97, 1037, 4188, 'Scent Nymph', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Peony Floral Ray', 16.81, 53.95, 1142, 5666, 'Dew Roe', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Iris-Glassbottle Arowana', 17.95, 63.71, 1248, 2745, 'Violet Larva', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Amberbloom Infusion Mackerel', 19.08, 74.24, 1354, 4223, 'Balm Cricket', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Neroli Silkspray Marlin', 20.22, 37.41, 1459, 5895, 'Citrus Fly', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Vetiver Petalfin Shark', 21.36, 46.78, 1565, 7762, 'Oil Gnat', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Magnolia Tuna', 22.5, 56.92, 1671, 3675, 'Bergamot Moth', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Linden Aromawave Minnow', 23.64, 67.84, 1776, 5542, 'Bloom Pellet', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Myrrh Mistline Loach', 24.78, 79.53, 1882, 7603, 'Amber Worm', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Lavender Bouquet Darter', 25.91, 91.99, 1988, 9859, 'Petal Worm', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Rosewater-Fragrance Chub', 27.05, 105, 2093, 4605, 'Rose Midge', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Bergamot Oilcurrent Bream', 28.19, 52.15, 2199, 6861, 'Nectar Fry', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'legendary', 'Jasmine Trout', 29.33, 64.23, 2305, 9311, 'Pollen Grub', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Violet Dewline Grouper', 29.76, 76.04, 2342, 6230, 'Floral Beetle', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Sandal Sturgeon', 32.29, 93.48, 2642, 9458, 'Scent Nymph', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Peony Glassbottle Manta', 34.82, 113, 2942, 13238, 'Dew Roe', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Iris-Infusion Barracuda', 37.35, 134, 3242, 17569, 'Violet Larva', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Amberbloom Silkspray Salmon', 39.88, 156, 3541, 9420, 'Balm Cricket', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Neroli Petalfin Swordfish', 42.41, 79.52, 3841, 13752, 'Citrus Fly', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Vetiver Perfume Coelacanth', 44.94, 99.54, 4141, 18635, 'Oil Gnat', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Magnolia Leviathan', 47.47, 121, 4441, 24071, 'Bergamot Moth', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Linden Mistline Guppy', 50, 145, 4741, 12611, 'Bloom Pellet', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Myrrh Bouquet Smelt', 52.53, 170, 5041, 18046, 'Amber Worm', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Lavender Fragrance Shiner', 55.06, 197, 5341, 24033, 'Petal Worm', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Rosewater-Oilcurrent Perch', 57.59, 225, 5641, 30572, 'Rose Midge', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Bergamot Bloomcrest Carp', 60.12, 113, 5940, 15802, 'Nectar Fry', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Jasmine Pike', 62.64, 139, 6240, 22340, 'Pollen Grub', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'liminal', 'Citrus Essence Catfish', 65.17, 167, 6540, 29431, 'Perfume Shrimp', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Sandal Ray', 64.48, 188, 6580, 20529, 'Scent Nymph', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Peony Infusion Arowana', 69.96, 228, 7422, 29986, 'Dew Roe', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Iris-Silkspray Mackerel', 75.44, 272, 8265, 40993, 'Violet Larva', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Amberbloom Petalfin Marlin', 80.92, 319, 9107, 20036, 'Balm Cricket', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Neroli Perfume Shark', 86.4, 164, 9950, 31043, 'Citrus Fly', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Vetiver Aromawave Tuna', 91.88, 206, 10792, 43601, 'Oil Gnat', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Magnolia Minnow', 97.36, 251, 11635, 57709, 'Bergamot Moth', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Linden Bouquet Loach', 103, 300, 12477, 27450, 'Bloom Pellet', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Myrrh Fragrance Darter', 108, 353, 13320, 41558, 'Amber Worm', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Lavender Oilcurrent Chub', 114, 410, 14162, 57216, 'Petal Worm', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Rosewater-Bloomcrest Bream', 119, 470, 15005, 74424, 'Rose Midge', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Bergamot Scentdrift Trout', 125, 237, 15847, 34864, 'Nectar Fry', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Jasmine Gar', 130, 292, 16690, 52073, 'Pollen Grub', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Citrus Dewline Snapper', 136, 350, 17532, 70831, 'Perfume Shrimp', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'mythic', 'Violet Floral Eel', 141, 412, 18375, 91140, 'Floral Beetle', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Peony Silkspray Barracuda', 139, 456, 18735, 67073, 'Dew Roe', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Iris-Petalfin Salmon', 151, 546, 21134, 95105, 'Violet Larva', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Amberbloom Perfume Swordfish', 162, 644, 23533, 127551, 'Balm Cricket', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Neroli Aromawave Coelacanth', 174, 336, 25932, 68980, 'Citrus Fly', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Vetiver Mistline Leviathan', 186, 422, 28332, 101427, 'Oil Gnat', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Magnolia Guppy', 198, 516, 30731, 138288, 'Bergamot Moth', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Linden Fragrance Smelt', 210, 618, 33130, 179562, 'Bloom Pellet', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Myrrh Oilcurrent Shiner', 222, 728, 35529, 94506, 'Amber Worm', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Lavender Bloomcrest Perch', 233, 846, 37928, 135781, 'Petal Worm', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Rosewater-Scentdrift Carp', 245, 972, 40327, 181470, 'Rose Midge', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Bergamot Essence Pike', 257, 495, 42726, 231574, 'Nectar Fry', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Jasmine Catfish', 269, 609, 45125, 120032, 'Pollen Grub', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Citrus Floral Grouper', 281, 731, 47524, 170135, 'Perfume Shrimp', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Violet Glassbottle Sturgeon', 292, 861, 49923, 224653, 'Floral Beetle', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'ascendant', 'Sandal Infusion Manta', 304, 999, 52322, 283585, 'Scent Nymph', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Iris-Perfume Marlin', 291, 1064, 52414, 211754, 'Violet Larva', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Amberbloom Aromawave Shark', 316, 1262, 59126, 293265, 'Balm Cricket', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Neroli Mistline Tuna', 341, 665, 65838, 144843, 'Citrus Fly', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Vetiver Bouquet Minnow', 366, 837, 72549, 226354, 'Oil Gnat', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Magnolia Loach', 390, 1027, 79261, 320214, 'Bergamot Moth', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Linden Oilcurrent Darter', 415, 1233, 85972, 426423, 'Bloom Pellet', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Myrrh Bloomcrest Chub', 440, 1456, 92684, 203905, 'Amber Worm', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Lavender Scentdrift Bream', 465, 1696, 99396, 310114, 'Petal Worm', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Rosewater-Essence Trout', 490, 1953, 106107, 428673, 'Rose Midge', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Bergamot Dewline Gar', 514, 1003, 112819, 559581, 'Nectar Fry', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Jasmine Snapper', 539, 1235, 119530, 262967, 'Pollen Grub', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Citrus Glassbottle Eel', 564, 1483, 126242, 393875, 'Perfume Shrimp', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Violet Infusion Ray', 589, 1748, 132954, 537133, 'Floral Beetle', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Sandal Silkspray Arowana', 613, 2030, 139665, 692739, 'Scent Nymph', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'celestial', 'Peony Petalfin Mackerel', 638, 2329, 146377, 322029, 'Dew Roe', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Amberbloom Mistline Coelacanth', 614, 2464, 147206, 662429, 'Balm Cricket', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Neroli Bouquet Leviathan', 666, 1315, 166056, 900024, 'Citrus Fly', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Vetiver Fragrance Guppy', 718, 1663, 184906, 491849, 'Oil Gnat', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Magnolia Smelt', 770, 2045, 203755, 729444, 'Bergamot Moth', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Linden Bloomcrest Shiner', 822, 2463, 222605, 1001722, 'Bloom Pellet', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Myrrh Scentdrift Perch', 875, 2917, 241454, 1308683, 'Amber Worm', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Lavender Essence Carp', 927, 3406, 260304, 692409, 'Petal Worm', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Rosewater-Dewline Pike', 979, 3931, 279154, 999370, 'Rose Midge', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Bergamot Floral Catfish', 1031, 2037, 298003, 1341014, 'Nectar Fry', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Jasmine Grouper', 1083, 2508, 316853, 1717342, 'Pollen Grub', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Citrus Infusion Sturgeon', 1136, 3015, 335702, 892968, 'Perfume Shrimp', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Violet Silkspray Manta', 1188, 3557, 354552, 1269296, 'Floral Beetle', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Sandal Petalfin Barracuda', 1240, 4135, 373402, 1680307, 'Scent Nymph', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Peony Perfume Salmon', 1292, 4748, 392251, 2126002, 'Dew Roe', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eldritch', 'Iris Aromawave Swordfish', 1344, 5397, 411101, 1093528, 'Violet Larva', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Neroli Fragrance Minnow', 1302, 2604, 412624, 2046615, 'Citrus Fly', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Vetiver Oilcurrent Loach', 1413, 3306, 465460, 1024012, 'Oil Gnat', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Magnolia Darter', 1523, 4083, 518296, 1617084, 'Bergamot Moth', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Linden Scentdrift Chub', 1634, 4935, 571132, 2307373, 'Bloom Pellet', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Myrrh Essence Bream', 1745, 5862, 623968, 3094881, 'Amber Worm', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Lavender Dewline Trout', 1855, 6865, 676804, 1488969, 'Petal Worm', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Rosewater-Floral Gar', 1966, 7943, 729640, 2276477, 'Rose Midge', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Bergamot Glassbottle Snapper', 2077, 4153, 782476, 3161203, 'Nectar Fry', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Jasmine Eel', 2187, 5118, 835312, 4143148, 'Pollen Grub', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Citrus Silkspray Ray', 2298, 6159, 888148, 1953926, 'Perfume Shrimp', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Violet Petalfin Arowana', 2409, 7274, 940984, 2935870, 'Floral Beetle', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Sandal Perfume Mackerel', 2519, 8465, 993820, 4015033, 'Scent Nymph', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Peony Aromawave Marlin', 2630, 9731, 1046656, 5191414, 'Dew Roe', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Iris Mistline Shark', 2741, 11072, 1099492, 2418882, 'Violet Larva', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'eternal', 'Amberbloom Tuna', 2851, 5703, 1152328, 3595263, 'Balm Cricket', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Vetiver Bloomcrest Smelt', 2778, 6569, 1159808, 6286159, 'Oil Gnat', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Magnolia Shiner', 3014, 8152, 1308320, 3480131, 'Bergamot Moth', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Linden Essence Perch', 3250, 9896, 1456832, 5215459, 'Bloom Pellet', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Myrrh Dewline Carp', 3486, 11800, 1605344, 7224048, 'Amber Worm', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Lavender Floral Pike', 3722, 13864, 1753856, 9505900, 'Petal Worm', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Rosewater-Glassbottle Catfish', 3958, 16090, 1902368, 5060299, 'Rose Midge', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Bergamot Infusion Grouper', 4194, 8493, 2050880, 7342150, 'Nectar Fry', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Jasmine Sturgeon', 4430, 10478, 2199392, 9897264, 'Pollen Grub', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Citrus Petalfin Manta', 4666, 12623, 2347904, 12725640, 'Perfume Shrimp', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Violet Perfume Barracuda', 4902, 14928, 2496416, 6640467, 'Floral Beetle', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Sandal Aromawave Salmon', 5139, 17394, 2644928, 9468842, 'Scent Nymph', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Peony Mistline Swordfish', 5375, 20021, 2793440, 12570480, 'Dew Roe', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Iris Bouquet Coelacanth', 5611, 22808, 2941952, 15945380, 'Violet Larva', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Amberbloom Leviathan', 5847, 11840, 3090464, 8220634, 'Balm Cricket', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'divine', 'Neroli Oilcurrent Guppy', 6083, 14386, 3238976, 11595534, 'Citrus Fly', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Magnolia Chub', 5952, 16249, 3256384, 7164045, 'Bergamot Moth', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Linden Dewline Bream', 6458, 19826, 3673360, 11460883, 'Bloom Pellet', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Myrrh Floral Trout', 6964, 23747, 4090336, 16524957, 'Amber Worm', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Lavender Glassbottle Gar', 7470, 28012, 4507312, 22356268, 'Petal Worm', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Rosewater-Infusion Snapper', 7976, 32621, 4924288, 10833434, 'Rose Midge', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Bergamot Silkspray Eel', 8482, 17387, 5341264, 16664744, 'Nectar Fry', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Jasmine Ray', 8988, 21480, 5758240, 23263290, 'Pollen Grub', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Citrus Perfume Arowana', 9493, 25917, 6175216, 30629071, 'Perfume Shrimp', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Violet Aromawave Mackerel', 9999, 30698, 6592192, 14502822, 'Floral Beetle', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Sandal Mistline Marlin', 10505, 35823, 7009168, 21868604, 'Scent Nymph', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Peony Bouquet Shark', 11011, 41292, 7426144, 30001622, 'Dew Roe', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Iris Fragrance Tuna', 11517, 47105, 7843120, 38901875, 'Violet Larva', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Amberbloom Minnow', 12023, 24647, 8260096, 18172211, 'Balm Cricket', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Neroli Bloomcrest Loach', 12529, 29944, 8677072, 27072465, 'Citrus Fly', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'cosmic', 'Vetiver Scentdrift Darter', 13035, 35585, 9094048, 36739954, 'Oil Gnat', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Linden Floral Carp', 12648, 39146, 9166944, 24384071, 'Bloom Pellet', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Myrrh Glassbottle Pike', 13723, 47139, 10340760, 37019921, 'Amber Worm', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Lavender Infusion Catfish', 14798, 55863, 11514576, 51815592, 'Petal Worm', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Rosewater-Silkspray Grouper', 15873, 65318, 12688392, 68771085, 'Rose Midge', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Bergamot Petalfin Sturgeon', 16948, 35168, 13862208, 36873473, 'Nectar Fry', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Jasmine Manta', 18023, 43527, 15036024, 53828966, 'Pollen Grub', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Citrus Aromawave Barracuda', 19098, 52616, 16209840, 72944280, 'Perfume Shrimp', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Violet Mistline Salmon', 20174, 62437, 17383656, 94219416, 'Floral Beetle', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Sandal Bouquet Swordfish', 21249, 72989, 18557472, 49362876, 'Scent Nymph', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Peony Fragrance Coelacanth', 22324, 84272, 19731288, 70638011, 'Dew Roe', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Iris Oilcurrent Leviathan', 23399, 96286, 20905104, 94072968, 'Violet Larva', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Amberbloom Guppy', 24474, 50783, 22078920, 119667746, 'Balm Cricket', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Neroli Scentdrift Smelt', 25549, 61701, 23252736, 61852278, 'Citrus Fly', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Vetiver Essence Shiner', 26624, 73349, 24426552, 87447056, 'Oil Gnat', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'primordial', 'Magnolia Dewline Perch', 27699, 85729, 25600368, 115201656, 'Bergamot Moth', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Myrrh Infusion Gar', 27280, 94389, 25761120, 80374694, 'Amber Worm', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Lavender Silkspray Snapper', 29599, 112475, 29059800, 117401592, 'Petal Worm', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Rosewater-Petalfin Eel', 31918, 132139, 32358480, 160498061, 'Rose Midge', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Bergamot Perfume Ray', 34236, 71896, 35657160, 78445752, 'Nectar Fry', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Jasmine Arowana', 36555, 89195, 38955840, 121542221, 'Pollen Grub', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Citrus Mistline Mackerel', 38874, 108070, 42254520, 170708261, 'Perfume Shrimp', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Violet Bouquet Marlin', 41193, 128522, 45553200, 225943872, 'Floral Beetle', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Sandal Fragrance Shark', 43512, 150550, 48851880, 107474136, 'Scent Nymph', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Peony Oilcurrent Tuna', 45830, 174156, 52150560, 162709747, 'Dew Roe', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Iris Bloomcrest Minnow', 48149, 199338, 55449240, 224014930, 'Violet Larva', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Amberbloom Loach', 50468, 105983, 58747920, 291389683, 'Balm Cricket', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Neroli Essence Darter', 52787, 128800, 62046600, 136502520, 'Citrus Fly', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Vetiver Dewline Chub', 55106, 153194, 65345280, 203877274, 'Oil Gnat', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Magnolia Floral Bream', 57424, 179164, 68643960, 277321598, 'Bergamot Moth', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'transcendent', 'Linden Glassbottle Trout', 59743, 206711, 71942640, 356835494, 'Bloom Pellet', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Lavender Petalfin Grouper', 58280, 222921, 72264960, 258708557, 'Petal Worm', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Rosewater-Perfume Sturgeon', 63234, 263369, 81518400, 366832800, 'Rose Midge', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Bergamot Aromawave Manta', 68188, 144899, 90771840, 491983373, 'Nectar Fry', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Jasmine Barracuda', 73141, 180294, 100025280, 266067245, 'Pollen Grub', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Citrus Bouquet Salmon', 78095, 219057, 109278720, 391217818, 'Perfume Shrimp', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Violet Fragrance Swordfish', 83049, 261189, 118532160, 533394720, 'Floral Beetle', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Sandal Oilcurrent Coelacanth', 88003, 306690, 127785600, 692597952, 'Scent Nymph', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Peony Bloomcrest Leviathan', 92957, 355559, 137039040, 364523846, 'Dew Roe', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Iris Scentdrift Guppy', 97910, 407797, 146292480, 523727078, 'Violet Larva', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Amberbloom Smelt', 102864, 218586, 155545920, 699956640, 'Balm Cricket', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Neroli Dewline Shiner', 107818, 265771, 164799360, 893212531, 'Citrus Fly', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Vetiver Floral Perch', 112772, 316325, 174052800, 462980448, 'Oil Gnat', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Magnolia Glassbottle Carp', 117726, 370247, 183306240, 656236339, 'Bergamot Moth', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Linden Infusion Pike', 122679, 427538, 192559680, 866518560, 'Bloom Pellet', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'apotheosis', 'Myrrh Silkspray Catfish', 127633, 488197, 201813120, 1093827110, 'Amber Worm', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Rosewater-Aromawave Ray', 125240, 524756, 202966400, 819984256, 'Rose Midge', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Bergamot Mistline Arowana', 135885, 292154, 228956000, 1135621760, 'Nectar Fry', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Jasmine Mackerel', 146531, 364862, 254945600, 560880320, 'Pollen Grub', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Citrus Fragrance Marlin', 157176, 444809, 280935200, 876517824, 'Perfume Shrimp', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Violet Oilcurrent Shark', 167822, 531994, 306924800, 1239976192, 'Floral Beetle', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Sandal Bloomcrest Tuna', 178467, 626419, 332914400, 1651255424, 'Scent Nymph', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Peony Scentdrift Minnow', 189112, 728083, 358904000, 789588800, 'Dew Roe', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Iris Essence Loach', 199758, 836985, 384893600, 1200868032, 'Violet Larva', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Amberbloom Darter', 210403, 452367, 410883200, 1659968128, 'Balm Cricket', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Neroli Floral Chub', 221049, 550411, 436872800, 2166889088, 'Citrus Fly', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Vetiver Glassbottle Bream', 231694, 655694, 462862400, 1018297280, 'Oil Gnat', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Magnolia Infusion Trout', 242339, 768216, 488852000, 1525218240, 'Bergamot Moth', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Linden Silkspray Gar', 252985, 887977, 514841600, 2079960064, 'Bloom Pellet', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Myrrh Petalfin Snapper', 263630, 1014976, 540831200, 2682522752, 'Amber Worm', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'absolute', 'Lavender Eel', 274276, 1149215, 566820800, 1247005760, 'Petal Worm', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Bergamot Bouquet Barracuda', 267840, 582552, 570982400, 2569420800, 'Nectar Fry', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Jasmine Salmon', 290606, 730875, 644096000, 3491000320, 'Pollen Grub', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Citrus Oilcurrent Swordfish', 313373, 894679, 717209600, 1907777536, 'Perfume Shrimp', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Violet Bloomcrest Coelacanth', 336139, 1073965, 790323200, 2829357056, 'Floral Beetle', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Sandal Scentdrift Leviathan', 358906, 1268731, 863436800, 3885465600, 'Scent Nymph', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Peony Essence Guppy', 381672, 1478979, 936550400, 5076103168, 'Dew Roe', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Iris Dewline Smelt', 404438, 1704708, 1009664000, 2685706240, 'Violet Larva', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Amberbloom Shiner', 427205, 929170, 1082777600, 3876343808, 'Balm Cricket', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Neroli Glassbottle Perch', 449971, 1131678, 1155891200, 5201510400, 'Citrus Fly', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Vetiver Infusion Carp', 472738, 1349666, 1229004800, 6661206016, 'Oil Gnat', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Magnolia Silkspray Pike', 495504, 1583135, 1302118400, 3463634944, 'Bergamot Moth', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Linden Petalfin Catfish', 518270, 1832086, 1375232000, 4923330560, 'Bloom Pellet', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Myrrh Perfume Grouper', 541037, 2096518, 1448345600, 6517555200, 'Amber Worm', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Lavender Sturgeon', 563803, 2376430, 1521459200, 8246308864, 'Petal Worm', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'singularity', 'Rosewater Mistline Manta', 586570, 1275789, 1594572800, 4241563648, 'Rose Midge', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Jasmine Marlin', 574120, 1458265, 1605888000, 7965204480, 'Pollen Grub', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Citrus Bloomcrest Shark', 622920, 1794010, 1811520000, 3985344000, 'Perfume Shrimp', 'Avoids sharp chemical odors completely.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Violet Scentdrift Tuna', 671720, 2162940, 2017152000, 6293514240, 'Floral Beetle', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Sandal Essence Minnow', 720521, 2565053, 2222784000, 8980047360, 'Scent Nymph', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Peony Dewline Loach', 769321, 3000351, 2428416000, 12044943360, 'Dew Roe', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Iris Floral Darter', 818121, 3468833, 2634048000, 5794905600, 'Violet Larva', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Amberbloom Chub', 866921, 1907227, 2839680000, 8859801600, 'Balm Cricket', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Neroli Infusion Bream', 915721, 2325932, 3045312000, 12303060480, 'Citrus Fly', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Vetiver Silkspray Trout', 964522, 2777822, 3250944000, 16124682240, 'Oil Gnat', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Magnolia Petalfin Gar', 1013322, 3262896, 3456576000, 7604467200, 'Bergamot Moth', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Linden Perfume Snapper', 1062122, 3781154, 3662208000, 11426088960, 'Bloom Pellet', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Myrrh Aromawave Eel', 1110922, 4332597, 3867840000, 15626073600, 'Amber Worm', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Lavender Ray', 1159722, 4917223, 4073472000, 20204421120, 'Petal Worm', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Rosewater Bouquet Arowana', 1208523, 2658750, 4279104000, 9414028800, 'Rose Midge', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'paradox', 'Bergamot-Fragrance Mackerel', 1257323, 3193600, 4484736000, 13992376320, 'Nectar Fry', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Citrus Scentdrift Coelacanth', 1230080, 3573382, 4527712000, 24540199040, 'Perfume Shrimp', 'Tail flicks release brief aroma plumes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Violet Essence Leviathan', 1334637, 4330896, 5107480000, 13585896800, 'Floral Beetle', 'Feeds near pollen-thick bloom belts.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Sandal Dewline Guppy', 1439194, 5159509, 5687248000, 20360347840, 'Scent Nymph', 'Most active after gentle evening rain.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Peony Floral Smelt', 1543750, 6059220, 6267016000, 28201572000, 'Dew Roe', 'Holds steady in silky currents.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Iris Glassbottle Shiner', 1648307, 7030030, 6846784000, 37109569280, 'Violet Larva', 'Can sprint when spooked by harsh light.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Amberbloom Perch', 1752864, 3900122, 7426552000, 19754628320, 'Balm Cricket', 'Nests in sheltered petal coves.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Neroli Silkspray Carp', 1857421, 4764284, 8006320000, 28662625600, 'Citrus Fly', 'Responds well to subtle lure movement.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Vetiver Petalfin Pike', 1961978, 5699545, 8586088000, 38637396000, 'Oil Gnat', 'Emits a soft floral wake while swimming.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Magnolia Perfume Catfish', 2066534, 6705904, 9165856000, 49678939520, 'Bergamot Moth', 'Bites peak during dawn fragrance drift.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Linden Aromawave Grouper', 2171091, 7783362, 9745624000, 25923359840, 'Bloom Pellet', 'Prefers warm oil-rich surface lanes.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Myrrh Mistline Sturgeon', 2275648, 8931918, 10325392000, 36964903360, 'Amber Worm', 'Can vanish into scented mist pockets.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Lavender Manta', 2380205, 10151573, 10905160000, 49073220000, 'Petal Worm', 'Schools around floating glass bottles.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Rosewater Fragrance Barracuda', 2484762, 5528595, 11484928000, 62248309760, 'Rose Midge', 'Tracks sweet baits over long distances.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Bergamot-Oilcurrent Salmon', 2589318, 6641602, 12064696000, 32092091360, 'Nectar Fry', 'Turns iridescent under moonlit haze.'),
  ('aromatic_archipelago', 'Aromatic Archipelago', 'null', 'Jasmine Bloomcrest Swordfish', 2693875, 7825707, 12644464000, 45267181120, 'Pollen Grub', 'Avoids sharp chemical odors completely.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Golden Minnow', 0.2, 0.36, 8, 18.4, 'Pollen Worm', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Meadow Dustline Loach', 0.22, 0.46, 9.1, 28.76, 'Golden Midge', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Saffron Sporecrest Darter', 0.23, 0.56, 10.2, 41, 'Petal Grub', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Sunpetal Meadowrun Chub', 0.25, 0.68, 11.3, 55.14, 'Dustfly', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Honeydust Bloomwake Bream', 0.27, 0.81, 12.4, 71.18, 'Breeze Shrimp', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Willow Drifttail Trout', 0.28, 0.94, 13.5, 36.85, 'Sunseed Nymph', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Amber Gar', 0.3, 1.09, 14.6, 52.41, 'Honey Gnat', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Bloom Airstream Snapper', 0.31, 1.25, 15.7, 69.86, 'Meadow Roe', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Drift Powderwake Eel', 0.33, 0.6, 16.8, 89.21, 'Willow Larva', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Canopy Petalshore Ray', 0.35, 0.73, 17.9, 41.17, 'Drift Cricket', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Mellow-Nectarline Arowana', 0.36, 0.88, 19, 60.04, 'Bloom Fry', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Dandelion Breezefin Mackerel', 0.38, 1.04, 20.1, 80.8, 'Clover Beetle', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Dewlit Marlin', 0.4, 1.21, 21.2, 103, 'Dew Moth', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Hazel Softcurrent Shark', 0.41, 1.38, 22.3, 128, 'Amber Fly', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'common', 'Buttercup Flightfin Tuna', 0.43, 1.57, 23.4, 63.88, 'Buttercup Worm', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Meadow Sporecrest Smelt', 0.68, 1.45, 24, 65.52, 'Golden Midge', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Saffron Meadowrun Shiner', 0.74, 1.8, 27.3, 98.01, 'Petal Grub', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Sunpetal Bloomwake Perch', 0.79, 2.18, 30.6, 136, 'Dustfly', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Honeydust Drifttail Carp', 0.85, 2.59, 33.9, 180, 'Breeze Shrimp', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Willow Sunripple Pike', 0.9, 3.05, 37.2, 85.56, 'Sunseed Nymph', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Amber Catfish', 0.96, 3.53, 40.5, 128, 'Honey Gnat', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Bloom Powderwake Grouper', 1.01, 4.05, 43.8, 176, 'Meadow Roe', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Drift Petalshore Sturgeon', 1.07, 1.95, 47.1, 230, 'Willow Larva', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Canopy Nectarline Manta', 1.13, 2.4, 50.4, 289, 'Drift Cricket', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Mellow-Breezefin Barracuda', 1.18, 2.89, 53.7, 147, 'Bloom Fry', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Dandelion Glider Salmon', 1.24, 3.41, 57, 205, 'Clover Beetle', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Dewlit Swordfish', 1.29, 3.96, 60.3, 268, 'Dew Moth', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Hazel Flightfin Coelacanth', 1.35, 4.55, 63.6, 338, 'Amber Fly', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Buttercup Bloomfin Leviathan', 1.4, 5.17, 66.9, 154, 'Buttercup Worm', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'uncommon', 'Golden Dustline Guppy', 1.46, 5.83, 70.2, 222, 'Pollen Worm', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Saffron Bloomwake Chub', 1.7, 4.19, 76, 240, 'Petal Grub', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Sunpetal Drifttail Bream', 1.84, 5.1, 86.45, 348, 'Dustfly', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Honeydust Sunripple Trout', 1.98, 6.1, 96.9, 473, 'Breeze Shrimp', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Willow Airstream Gar', 2.12, 7.19, 107, 616, 'Sunseed Nymph', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Amber Snapper', 2.26, 8.36, 118, 322, 'Honey Gnat', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Bloom Petalshore Eel', 2.4, 9.62, 128, 460, 'Meadow Roe', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Drift Nectarline Ray', 2.54, 4.68, 139, 617, 'Willow Larva', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Canopy Breezefin Arowana', 2.68, 5.76, 149, 792, 'Drift Cricket', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Mellow-Glider Mackerel', 2.82, 6.94, 160, 367, 'Bloom Fry', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Dandelion Softcurrent Marlin', 2.95, 8.2, 170, 537, 'Clover Beetle', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Dewlit Shark', 3.09, 9.54, 181, 726, 'Dew Moth', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Hazel Bloomfin Tuna', 3.23, 10.97, 191, 932, 'Amber Fly', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Buttercup Dustline Minnow', 3.37, 12.49, 201, 1156, 'Buttercup Worm', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Golden Sporecrest Loach', 3.51, 14.1, 212, 578, 'Pollen Worm', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'rare', 'Meadow Meadowrun Darter', 3.65, 6.73, 222, 798, 'Golden Midge', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Sunpetal Sunripple Carp', 4.5, 12.58, 228, 819, 'Dustfly', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Honeydust Airstream Pike', 4.87, 15.12, 259, 1154, 'Breeze Shrimp', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Willow Powderwake Catfish', 5.24, 17.89, 291, 1544, 'Sunseed Nymph', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Amber Grouper', 5.61, 20.89, 322, 741, 'Honey Gnat', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Bloom Nectarline Sturgeon', 5.98, 24.12, 353, 1117, 'Meadow Roe', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Drift Breezefin Manta', 6.35, 11.84, 385, 1547, 'Willow Larva', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Canopy Glider Barracuda', 6.71, 14.61, 416, 2031, 'Drift Cricket', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Mellow-Softcurrent Salmon', 7.08, 17.61, 447, 2568, 'Bloom Fry', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Dandelion Flightfin Swordfish', 7.45, 20.84, 479, 1307, 'Clover Beetle', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Dewlit Coelacanth', 7.82, 24.29, 510, 1831, 'Dew Moth', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Hazel Dustline Leviathan', 8.19, 27.98, 542, 2410, 'Amber Fly', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Buttercup Sporecrest Guppy', 8.56, 31.89, 573, 3042, 'Buttercup Worm', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Golden Meadowrun Smelt', 8.93, 36.03, 604, 1390, 'Pollen Worm', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Meadow Bloomwake Shiner', 9.3, 17.35, 636, 2008, 'Golden Midge', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'epic', 'Saffron Drifttail Perch', 9.67, 21.03, 667, 2681, 'Petal Grub', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Honeydust Powderwake Gar', 11.8, 36.91, 680, 2734, 'Breeze Shrimp', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Willow Petalshore Snapper', 12.77, 43.9, 774, 3775, 'Sunseed Nymph', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Amber Eel', 13.74, 51.48, 867, 4977, 'Honey Gnat', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Bloom Breezefin Ray', 14.7, 59.66, 961, 2622, 'Meadow Roe', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Drift Glider Arowana', 15.67, 29.59, 1054, 3784, 'Willow Larva', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Canopy Softcurrent Mackerel', 16.64, 36.57, 1148, 5106, 'Drift Cricket', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Mellow-Flightfin Marlin', 17.61, 44.15, 1241, 6590, 'Bloom Fry', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Dandelion Bloomfin Shark', 18.57, 52.34, 1335, 3069, 'Clover Beetle', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Dewlit Tuna', 19.54, 61.12, 1428, 4512, 'Dew Moth', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Hazel Sporecrest Minnow', 20.51, 70.51, 1522, 6116, 'Amber Fly', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Buttercup Meadowrun Loach', 21.48, 80.49, 1615, 7881, 'Buttercup Worm', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Golden Bloomwake Darter', 22.44, 91.08, 1708, 9807, 'Pollen Worm', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Meadow Drifttail Chub', 23.41, 44.2, 1802, 4919, 'Golden Midge', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Saffron Sunripple Bream', 24.38, 53.58, 1896, 6805, 'Petal Grub', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'legendary', 'Sunpetal Trout', 25.35, 63.57, 1989, 8851, 'Dustfly', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Willow Nectarline Grouper', 26, 89.96, 1920, 8544, 'Sunseed Nymph', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Amber Sturgeon', 28.13, 106, 2184, 11597, 'Honey Gnat', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Bloom Glider Manta', 30.26, 123, 2448, 5630, 'Meadow Roe', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Drift Softcurrent Barracuda', 32.4, 61.88, 2712, 8570, 'Willow Larva', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Canopy Flightfin Salmon', 34.53, 76.65, 2976, 11964, 'Drift Cricket', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Mellow-Bloomfin Swordfish', 36.66, 92.75, 3240, 15811, 'Bloom Fry', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Dandelion Dustline Coelacanth', 38.79, 110, 3504, 20113, 'Clover Beetle', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Dewlit Leviathan', 40.92, 129, 3768, 10287, 'Dew Moth', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Hazel Meadowrun Guppy', 43.06, 149, 4032, 14475, 'Amber Fly', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Buttercup Bloomwake Smelt', 45.19, 170, 4296, 19117, 'Buttercup Worm', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Golden Drifttail Shiner', 47.32, 193, 4560, 24214, 'Pollen Worm', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Meadow Sunripple Perch', 49.45, 94.45, 4824, 11095, 'Golden Midge', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Saffron Airstream Carp', 51.58, 115, 5088, 16078, 'Petal Grub', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Sunpetal Pike', 53.72, 136, 5352, 21515, 'Dustfly', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'liminal', 'Honeydust Petalshore Catfish', 55.85, 159, 5616, 27406, 'Breeze Shrimp', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Amber Ray', 57, 216, 5440, 26547, 'Honey Gnat', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Bloom Softcurrent Arowana', 61.67, 253, 6188, 35519, 'Meadow Roe', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Drift Flightfin Mackerel', 66.35, 128, 6936, 18935, 'Willow Larva', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Canopy Bloomfin Marlin', 71.02, 159, 7684, 27586, 'Drift Cricket', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Mellow-Dustline Shark', 75.7, 193, 8432, 37522, 'Bloom Fry', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Dandelion Sporecrest Tuna', 80.37, 230, 9180, 48746, 'Clover Beetle', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Dewlit Minnow', 85.04, 270, 9928, 22834, 'Dew Moth', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Hazel Bloomwake Loach', 89.72, 312, 10676, 33736, 'Amber Fly', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Buttercup Drifttail Darter', 94.39, 358, 11424, 45924, 'Buttercup Worm', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Golden Sunripple Chub', 99.07, 406, 12172, 59399, 'Pollen Worm', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Meadow Airstream Bream', 104, 200, 12920, 74161, 'Golden Midge', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Saffron Powderwake Trout', 108, 243, 13668, 37314, 'Petal Grub', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Sunpetal Gar', 113, 289, 14416, 51753, 'Dustfly', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Honeydust Nectarline Snapper', 118, 337, 15164, 67480, 'Breeze Shrimp', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'mythic', 'Willow-Breezefin Eel', 122, 388, 15912, 84493, 'Sunseed Nymph', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Bloom Flightfin Barracuda', 123, 507, 15360, 81562, 'Meadow Roe', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Drift Bloomfin Salmon', 133, 260, 17472, 40186, 'Willow Larva', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Canopy Dustline Swordfish', 143, 324, 19584, 61885, 'Drift Cricket', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Mellow-Sporecrest Coelacanth', 153, 394, 21696, 87218, 'Bloom Fry', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Dandelion Meadowrun Leviathan', 163, 471, 23808, 116183, 'Clover Beetle', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Dewlit Guppy', 173, 554, 25920, 148781, 'Dew Moth', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Hazel Drifttail Smelt', 184, 643, 28032, 76527, 'Amber Fly', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Buttercup Sunripple Shiner', 194, 738, 30144, 108217, 'Buttercup Worm', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Golden Airstream Perch', 204, 840, 32256, 143539, 'Pollen Worm', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Meadow Powderwake Carp', 214, 418, 34368, 182494, 'Golden Midge', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Saffron Petalshore Pike', 224, 507, 36480, 83904, 'Petal Grub', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Sunpetal Catfish', 234, 602, 38592, 121951, 'Dustfly', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Honeydust Breezefin Grouper', 244, 704, 40704, 163630, 'Breeze Shrimp', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Willow-Glider Sturgeon', 254, 812, 42816, 208942, 'Sunseed Nymph', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'ascendant', 'Amber Softcurrent Manta', 264, 926, 44928, 257887, 'Honey Gnat', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Drift Dustline Marlin', 262, 518, 43200, 247968, 'Willow Larva', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Canopy Sporecrest Shark', 283, 648, 49140, 134152, 'Drift Cricket', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Mellow-Meadowrun Tuna', 305, 792, 55080, 197737, 'Bloom Fry', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Dandelion Bloomwake Minnow', 326, 949, 61020, 271539, 'Clover Beetle', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Dewlit Loach', 348, 1119, 66960, 355558, 'Dew Moth', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Hazel Sunripple Darter', 369, 1303, 72900, 167670, 'Amber Fly', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Buttercup Airstream Chub', 391, 1500, 78840, 249134, 'Buttercup Worm', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Golden Powderwake Bream', 412, 1710, 84780, 340816, 'Pollen Worm', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Meadow Petalshore Trout', 434, 857, 90720, 442714, 'Golden Midge', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Saffron Nectarline Gar', 455, 1041, 96660, 554828, 'Petal Grub', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Sunpetal Snapper', 477, 1238, 102600, 280098, 'Dustfly', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Honeydust Glider Eel', 498, 1448, 108540, 389659, 'Breeze Shrimp', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Willow-Softcurrent Ray', 520, 1672, 114480, 509436, 'Sunseed Nymph', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Amber Flightfin Arowana', 541, 1909, 120420, 639430, 'Honey Gnat', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'celestial', 'Bloom Bloomfin Mackerel', 563, 2159, 126360, 290628, 'Meadow Roe', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Canopy Meadowrun Coelacanth', 555, 1281, 122400, 281520, 'Drift Cricket', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Mellow-Bloomwake Leviathan', 601, 1572, 139230, 439967, 'Bloom Fry', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Dandelion Drifttail Guppy', 646, 1892, 156060, 627361, 'Clover Beetle', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Dewlit Smelt', 692, 2239, 172890, 843703, 'Dew Moth', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Hazel Airstream Shiner', 737, 2615, 189720, 1088993, 'Amber Fly', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Buttercup Powderwake Perch', 783, 3019, 206550, 563882, 'Buttercup Worm', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Golden Petalshore Carp', 828, 3451, 223380, 801934, 'Pollen Worm', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Meadow Nectarline Pike', 874, 1745, 240210, 1068934, 'Golden Midge', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Saffron Breezefin Catfish', 919, 2121, 257040, 1364882, 'Petal Grub', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Sunpetal Grouper', 965, 2525, 273870, 629901, 'Dustfly', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Honeydust Softcurrent Sturgeon', 1010, 2958, 290700, 918612, 'Breeze Shrimp', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Willow-Flightfin Manta', 1056, 3418, 307530, 1236271, 'Sunseed Nymph', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Amber Bloomfin Barracuda', 1101, 3907, 324360, 1582877, 'Honey Gnat', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Bloom Dustline Salmon', 1147, 4424, 341190, 1958431, 'Meadow Roe', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'eldritch', 'Drift Sporecrest Swordfish', 1192, 4969, 358020, 977395, 'Willow Larva', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Mellow-Drifttail Minnow', 1180, 3115, 344000, 939120, 'Bloom Fry', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Dandelion Sunripple Loach', 1277, 3766, 391300, 1404767, 'Clover Beetle', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Dewlit Darter', 1374, 4478, 438600, 1951770, 'Dew Moth', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Hazel Powderwake Chub', 1470, 5249, 485900, 2580129, 'Amber Fly', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Buttercup Petalshore Bream', 1567, 6080, 533200, 1226360, 'Buttercup Worm', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Golden Nectarline Trout', 1664, 6971, 580500, 1834380, 'Pollen Worm', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Meadow Breezefin Gar', 1761, 3556, 627800, 2523756, 'Golden Midge', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Saffron Glider Snapper', 1857, 4328, 675100, 3294488, 'Petal Grub', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Sunpetal Eel', 1954, 5159, 722400, 4146576, 'Dustfly', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Honeydust Flightfin Ray', 2051, 6050, 769700, 2101281, 'Breeze Shrimp', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Willow-Bloomfin Arowana', 2148, 7001, 817000, 2933030, 'Sunseed Nymph', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Amber Dustline Mackerel', 2244, 8012, 864300, 3846135, 'Honey Gnat', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Bloom Sporecrest Marlin', 2341, 9084, 911600, 4840596, 'Meadow Roe', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Drift Meadowrun Shark', 2438, 10215, 958900, 2205470, 'Willow Larva', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'eternal', 'Canopy Tuna', 2535, 5120, 1006200, 3179592, 'Drift Cricket', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Dandelion Airstream Smelt', 2510, 7460, 968000, 3058880, 'Clover Beetle', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Dewlit Shiner', 2716, 8913, 1101100, 4426422, 'Dew Moth', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Hazel Petalshore Perch', 2922, 10495, 1234200, 6022896, 'Amber Fly', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Buttercup Nectarline Carp', 3127, 12203, 1367300, 7848302, 'Buttercup Worm', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Golden Breezefin Pike', 3333, 14040, 1500400, 4096092, 'Pollen Worm', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Meadow Glider Catfish', 3539, 7227, 1633500, 5864265, 'Golden Midge', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Saffron Softcurrent Grouper', 3745, 8808, 1766600, 7861370, 'Petal Grub', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Sunpetal Sturgeon', 3951, 10517, 1899700, 10087407, 'Dustfly', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Honeydust Bloomfin Manta', 4157, 12353, 2032800, 4675440, 'Breeze Shrimp', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Willow-Dustline Barracuda', 4362, 14317, 2165900, 6844244, 'Sunseed Nymph', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Amber Sporecrest Salmon', 4568, 16409, 2299000, 9241980, 'Honey Gnat', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Bloom Meadowrun Swordfish', 4774, 18628, 2432100, 11868648, 'Meadow Roe', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Drift Bloomwake Coelacanth', 4980, 20975, 2565200, 14724248, 'Willow Larva', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Canopy Leviathan', 5186, 10589, 2698300, 7366359, 'Drift Cricket', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'divine', 'Mellow Sunripple Guppy', 5391, 12681, 2831400, 10164726, 'Bloom Fry', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Dewlit Chub', 5350, 17676, 2728000, 9793520, 'Dew Moth', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Hazel Nectarline Bream', 5789, 20920, 3103100, 13808795, 'Amber Fly', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Buttercup Breezefin Trout', 6227, 24436, 3478200, 18469242, 'Buttercup Worm', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Golden Glider Gar', 6666, 28224, 3853300, 8862590, 'Pollen Worm', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Meadow Softcurrent Snapper', 7105, 14664, 4228400, 13361744, 'Golden Midge', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Saffron Flightfin Eel', 7544, 17908, 4603500, 18506070, 'Petal Grub', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Sunpetal Ray', 7982, 21424, 4978600, 24295568, 'Dustfly', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Honeydust Dustline Arowana', 8421, 25212, 5353700, 30730238, 'Breeze Shrimp', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Willow-Sporecrest Mackerel', 8860, 29272, 5728800, 15639624, 'Sunseed Nymph', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Amber Meadowrun Marlin', 9298, 33604, 6103900, 21913001, 'Honey Gnat', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Bloom Bloomwake Shark', 9737, 38208, 6479000, 28831550, 'Meadow Roe', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Drift Drifttail Tuna', 10176, 43084, 6854100, 36395271, 'Willow Larva', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Canopy Minnow', 10614, 21908, 7229200, 16627160, 'Drift Cricket', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Mellow Airstream Loach', 11053, 26240, 7604300, 24029588, 'Bloom Fry', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'cosmic', 'Dandelion Powderwake Darter', 11492, 30844, 7979400, 32077188, 'Clover Beetle', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Hazel Breezefin Carp', 11400, 41450, 7688000, 30905760, 'Amber Fly', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Buttercup Glider Pike', 12335, 48673, 8745100, 42676088, 'Buttercup Worm', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Golden Softcurrent Catfish', 13270, 56475, 9802200, 56264628, 'Pollen Worm', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Meadow Flightfin Grouper', 14204, 29630, 10859300, 29645889, 'Golden Midge', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Saffron Bloomfin Sturgeon', 15139, 36274, 11916400, 42779876, 'Petal Grub', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Sunpetal Manta', 16074, 43496, 12973500, 57732075, 'Dustfly', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Honeydust Sporecrest Barracuda', 17009, 51299, 14030600, 74502486, 'Breeze Shrimp', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Willow-Meadowrun Salmon', 17944, 59680, 15087700, 34701710, 'Sunseed Nymph', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Amber Bloomwake Swordfish', 18878, 68642, 16144800, 51017568, 'Honey Gnat', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Bloom Drifttail Coelacanth', 19813, 78183, 17201900, 69151638, 'Meadow Roe', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Drift Sunripple Leviathan', 20748, 88303, 18259000, 89103920, 'Willow Larva', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Canopy Guppy', 21683, 45230, 19316100, 110874414, 'Drift Cricket', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Mellow Powderwake Smelt', 22618, 54192, 20373200, 55618836, 'Bloom Fry', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Dandelion Petalshore Shiner', 23552, 63733, 21430300, 76934777, 'Clover Beetle', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'primordial', 'Dewlit Nectarline Perch', 24487, 73853, 22487400, 100068930, 'Dew Moth', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Buttercup Softcurrent Gar', 24400, 96819, 21600000, 96120000, 'Buttercup Worm', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Golden Flightfin Snapper', 26401, 112943, 24570000, 130466700, 'Pollen Worm', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Meadow Bloomfin Eel', 28402, 59871, 27540000, 63342000, 'Golden Midge', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Saffron Dustline Ray', 30402, 73513, 30510000, 96411600, 'Petal Grub', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Sunpetal Arowana', 32403, 88396, 33480000, 134589600, 'Dustfly', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Honeydust Meadowrun Mackerel', 34404, 104519, 36450000, 177876000, 'Breeze Shrimp', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Willow-Bloomwake Marlin', 36405, 121883, 39420000, 226270800, 'Sunseed Nymph', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Amber Drifttail Shark', 38406, 140488, 42390000, 115724700, 'Honey Gnat', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Bloom Sunripple Tuna', 40406, 160333, 45360000, 162842400, 'Meadow Roe', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Drift Airstream Minnow', 42407, 181418, 48330000, 215068500, 'Willow Larva', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Canopy Loach', 44408, 93612, 51300000, 272403000, 'Drift Cricket', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Mellow Petalshore Darter', 46409, 112216, 54270000, 124821000, 'Bloom Fry', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Dandelion Nectarline Chub', 48410, 132061, 57240000, 180878400, 'Clover Beetle', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Dewlit Breezefin Bream', 50410, 153147, 60210000, 242044200, 'Dew Moth', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'transcendent', 'Hazel Glider Trout', 52411, 175473, 63180000, 308318400, 'Amber Fly', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Golden Bloomfin Grouper', 52200, 224460, 60800000, 296704000, 'Pollen Worm', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Meadow Dustline Sturgeon', 56480, 120303, 69160000, 396978400, 'Golden Midge', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Saffron Sporecrest Manta', 60761, 148256, 77520000, 211629600, 'Petal Grub', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Sunpetal Barracuda', 65041, 178863, 85880000, 308309200, 'Dustfly', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Honeydust Bloomwake Salmon', 69322, 212124, 94240000, 419368000, 'Breeze Shrimp', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Willow-Drifttail Swordfish', 73602, 248039, 102600000, 544806000, 'Sunseed Nymph', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Amber Sunripple Coelacanth', 77882, 286607, 110960000, 255208000, 'Honey Gnat', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Bloom Airstream Leviathan', 82163, 327830, 119320000, 377051200, 'Meadow Roe', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Drift Powderwake Guppy', 86443, 371706, 127680000, 513273600, 'Willow Larva', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Canopy Smelt', 90724, 193241, 136040000, 663875200, 'Drift Cricket', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Mellow Nectarline Shiner', 95004, 231810, 144400000, 828856000, 'Bloom Fry', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Dandelion Breezefin Perch', 99284, 273032, 152760000, 417034800, 'Clover Beetle', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Dewlit Glider Carp', 103565, 316908, 161120000, 578420800, 'Dew Moth', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Hazel Softcurrent Pike', 107845, 363438, 169480000, 754186000, 'Amber Fly', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'apotheosis', 'Buttercup Flightfin Catfish', 112126, 412622, 177840000, 944330400, 'Buttercup Worm', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Meadow Sporecrest Ray', 112000, 241024, 171200000, 909072000, 'Golden Midge', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Saffron Meadowrun Arowana', 121184, 298355, 194740000, 447902000, 'Petal Grub', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Sunpetal Mackerel', 130368, 361380, 218280000, 689764800, 'Dustfly', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Honeydust Drifttail Marlin', 139552, 430099, 241820000, 972116400, 'Breeze Shrimp', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Willow-Sunripple Shark', 148736, 504513, 265360000, 1294956800, 'Sunseed Nymph', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Amber Airstream Tuna', 157920, 584620, 288900000, 1658286000, 'Honey Gnat', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Bloom Powderwake Minnow', 167104, 670421, 312440000, 852961200, 'Meadow Roe', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Drift Petalshore Loach', 176288, 761917, 335980000, 1206168200, 'Willow Larva', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Canopy Darter', 185472, 399136, 359520000, 1599864000, 'Drift Cricket', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Mellow Breezefin Chub', 194656, 479243, 383060000, 2034048600, 'Bloom Fry', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Dandelion Glider Bream', 203840, 565044, 406600000, 935180000, 'Clover Beetle', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Dewlit Softcurrent Trout', 213024, 656540, 430140000, 1359242400, 'Dew Moth', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Hazel Flightfin Gar', 222208, 753730, 453680000, 1823793600, 'Amber Fly', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Buttercup Bloomfin Snapper', 231392, 856613, 477220000, 2328833600, 'Buttercup Worm', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'absolute', 'Golden Eel', 240576, 965191, 500760000, 2874362400, 'Pollen Worm', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Saffron Bloomwake Barracuda', 240000, 596160, 482400000, 2768976000, 'Petal Grub', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Sunpetal Salmon', 259680, 725546, 548730000, 1498032900, 'Dustfly', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Honeydust Sunripple Swordfish', 279360, 867133, 615060000, 2208065400, 'Breeze Shrimp', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Willow-Airstream Coelacanth', 299040, 1020923, 681390000, 3032185500, 'Sunseed Nymph', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Amber Powderwake Leviathan', 318720, 1186913, 747720000, 3970393200, 'Honey Gnat', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Bloom Petalshore Guppy', 338400, 1365106, 814050000, 1872315000, 'Meadow Roe', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Drift Nectarline Smelt', 358080, 1555500, 880380000, 2782000800, 'Willow Larva', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Canopy Shiner', 377760, 821250, 946710000, 3805774200, 'Drift Cricket', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Mellow Glider Perch', 397440, 987241, 1013040000, 4943635200, 'Bloom Fry', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Dandelion Softcurrent Carp', 417120, 1165433, 1079370000, 6195583800, 'Clover Beetle', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Dewlit Flightfin Pike', 436800, 1355827, 1145700000, 3127761000, 'Dew Moth', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Hazel Bloomfin Catfish', 456480, 1558423, 1212030000, 4351187700, 'Amber Fly', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Buttercup Dustline Grouper', 476160, 1773220, 1278360000, 5688702000, 'Buttercup Worm', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Golden Sturgeon', 495840, 2000219, 1344690000, 7140303900, 'Pollen Worm', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'singularity', 'Meadow Meadowrun Manta', 515520, 2239419, 1411020000, 3245346000, 'Golden Midge', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Sunpetal Marlin', 515000, 1450240, 1360000000, 3128000000, 'Dustfly', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Honeydust Airstream Shark', 557230, 1741901, 1547000000, 4888520000, 'Breeze Shrimp', 'Handles low-visibility powder water well.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Willow-Powderwake Tuna', 599460, 2059745, 1734000000, 6970680000, 'Sunseed Nymph', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Amber Petalshore Minnow', 641690, 2403771, 1921000000, 9374480000, 'Honey Gnat', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Bloom Nectarline Loach', 683920, 2773980, 2108000000, 12099920000, 'Meadow Roe', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Drift Breezefin Darter', 726150, 3170371, 2295000000, 6265350000, 'Willow Larva', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Canopy Chub', 768380, 1687362, 2482000000, 8910380000, 'Drift Cricket', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Mellow Softcurrent Bream', 810610, 2031389, 2669000000, 11877050000, 'Bloom Fry', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Dandelion Flightfin Trout', 852840, 2401597, 2856000000, 15165360000, 'Clover Beetle', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Dewlit Bloomfin Gar', 895070, 2797989, 3043000000, 6998900000, 'Dew Moth', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Hazel Dustline Snapper', 937300, 3220563, 3230000000, 10206800000, 'Amber Fly', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Buttercup Sporecrest Eel', 979530, 3669319, 3417000000, 13736340000, 'Buttercup Worm', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Golden Ray', 1021760, 4144259, 3604000000, 17587520000, 'Pollen Worm', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Meadow Bloomwake Arowana', 1063990, 4645380, 3791000000, 21760340000, 'Golden Midge', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'paradox', 'Saffron Drifttail Mackerel', 1106220, 2429259, 3978000000, 10859940000, 'Petal Grub', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Honeydust Powderwake Coelacanth', 1104000, 3475392, 3840000000, 10483200000, 'Breeze Shrimp', 'Feeds heavily at seasonal bloom peaks.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Willow-Petalshore Leviathan', 1194528, 4130678, 4368000000, 15681120000, 'Sunseed Nymph', 'Rises near light wind corridors.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Amber Nectarline Guppy', 1285056, 4842091, 4896000000, 21787200000, 'Honey Gnat', 'Turns calmer after evening humidity.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Bloom Breezefin Smelt', 1375584, 5609632, 5424000000, 28801440000, 'Meadow Roe', 'Responds to gentle, steady retrieves.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Drift Glider Shiner', 1466112, 6433299, 5952000000, 13689600000, 'Willow Larva', 'Holds near sheltered petal coves.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Canopy Perch', 1556640, 3452628, 6480000000, 20476800000, 'Drift Cricket', 'Can leap cleanly over pollen mats.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Mellow Flightfin Carp', 1647168, 4164041, 7008000000, 28172160000, 'Bloom Fry', 'Leaves faint golden swirls while turning.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Dandelion Bloomfin Pike', 1737696, 4931581, 7536000000, 36775680000, 'Clover Beetle', 'Glides through airborne pollen currents.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Dewlit Dustline Catfish', 1828224, 5755249, 8064000000, 46287360000, 'Dew Moth', 'Bites best in late morning warmth.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Hazel Sporecrest Grouper', 1918752, 6635044, 8592000000, 23456160000, 'Amber Fly', 'Favors dense yellow bloom zones.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Buttercup Meadowrun Sturgeon', 2009280, 7570967, 9120000000, 32740800000, 'Buttercup Worm', 'Can sprint between drifting dust plumes.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Golden Manta', 2099808, 8563017, 9648000000, 42933600000, 'Pollen Worm', 'Tracks sweet baits over long lanes.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Meadow Drifttail Barracuda', 2190336, 9611194, 10176000000, 54034560000, 'Golden Midge', 'Scales brighten during sunny weather.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Saffron Sunripple Salmon', 2280864, 5058956, 10704000000, 24619200000, 'Petal Grub', 'Often schools above flower-root shelves.'),
  ('pollen_ponds', 'Pollen Ponds', 'null', 'Sunpetal Airstream Swordfish', 2371392, 5994879, 11232000000, 35493120000, 'Dustfly', 'Handles low-visibility powder water well.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Orchid Minnow', 0.21, 0.45, 8.8, 24.02, 'Nectar Moth', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Nectar Sapstream Loach', 0.23, 0.56, 10.01, 35.94, 'Orchid Worm', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Rose Bloomtail Darter', 0.25, 0.68, 11.22, 49.93, 'Sweet Roe', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Clover Pollencrest Chub', 0.27, 0.81, 12.43, 66, 'Pollen Fly', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Velvet Dewline Bream', 0.28, 0.95, 13.64, 31.37, 'Dew Shrimp', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Honey Petalwave Trout', 0.3, 1.1, 14.85, 46.93, 'Petal Nymph', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Lilac Gar', 0.32, 1.27, 16.06, 64.56, 'Syrup Grub', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Blooming Orchidline Snapper', 0.34, 0.61, 17.27, 84.28, 'Honey Midge', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Amber Sugarrun Eel', 0.35, 0.75, 18.48, 106, 'Lilac Larva', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Dewdrop Flowerdrift Ray', 0.37, 0.9, 19.69, 53.75, 'Bloom Cricket', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Meadow-Glazecrest Arowana', 0.39, 1.06, 20.9, 75.03, 'Rose Beetle', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Silkpetal Violettide Mackerel', 0.41, 1.24, 22.11, 98.39, 'Glaze Fry', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Garden Marlin', 0.42, 1.42, 23.32, 124, 'Clover Gnat', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Sweetwater Mistbloom Shark', 0.44, 1.62, 24.53, 56.42, 'Garden Moth', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'common', 'Starlily Fragrantide Tuna', 0.46, 1.82, 25.74, 81.34, 'Amber Worm', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Nectar Bloomtail Smelt', 0.73, 1.78, 26.4, 83.42, 'Orchid Worm', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Rose Pollencrest Shiner', 0.79, 2.17, 30.03, 121, 'Sweet Roe', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Clover Dewline Perch', 0.85, 2.59, 33.66, 164, 'Pollen Fly', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Velvet Petalwave Carp', 0.91, 3.06, 37.29, 214, 'Dew Shrimp', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Honey Honeyflow Pike', 0.97, 3.56, 40.92, 112, 'Petal Nymph', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Lilac Catfish', 1.03, 4.1, 44.55, 160, 'Syrup Grub', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Blooming Sugarrun Grouper', 1.09, 1.98, 48.18, 214, 'Honey Midge', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Amber Flowerdrift Sturgeon', 1.15, 2.44, 51.81, 275, 'Lilac Larva', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Dewdrop Glazecrest Manta', 1.2, 2.94, 55.44, 128, 'Bloom Cricket', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Meadow-Violettide Barracuda', 1.26, 3.48, 59.07, 187, 'Rose Beetle', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Silkpetal Syrupfin Salmon', 1.32, 4.05, 62.7, 252, 'Glaze Fry', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Garden Swordfish', 1.38, 4.67, 66.33, 324, 'Clover Gnat', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Sweetwater Fragrantide Coelacanth', 1.44, 5.32, 69.96, 402, 'Garden Moth', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Starlily Nectarfin Leviathan', 1.5, 6, 73.59, 201, 'Amber Worm', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'uncommon', 'Orchid Sapstream Guppy', 1.56, 2.85, 77.22, 277, 'Nectar Moth', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Rose Dewline Chub', 1.82, 5.05, 83.6, 300, 'Sweet Roe', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Clover Petalwave Bream', 1.97, 6.07, 95.1, 423, 'Pollen Fly', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Velvet Honeyflow Trout', 2.12, 7.19, 107, 566, 'Dew Shrimp', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Honey Orchidline Gar', 2.27, 8.4, 118, 272, 'Petal Nymph', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Lilac Snapper', 2.42, 9.7, 130, 409, 'Syrup Grub', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Blooming Flowerdrift Eel', 2.56, 4.73, 141, 567, 'Honey Midge', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Amber Glazecrest Ray', 2.71, 5.85, 153, 745, 'Lilac Larva', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Dewdrop Violettide Arowana', 2.86, 7.05, 164, 942, 'Bloom Cricket', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Meadow-Syrupfin Mackerel', 3.01, 8.36, 176, 479, 'Rose Beetle', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Silkpetal Mistbloom Marlin', 3.16, 9.75, 187, 672, 'Glaze Fry', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Garden Shark', 3.31, 11.24, 199, 884, 'Clover Gnat', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Sweetwater Nectarfin Tuna', 3.46, 12.81, 210, 1115, 'Garden Moth', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Starlily Sapstream Minnow', 3.61, 14.49, 222, 510, 'Amber Worm', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Orchid Bloomtail Loach', 3.76, 6.93, 233, 736, 'Nectar Moth', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'rare', 'Nectar Pollencrest Darter', 3.91, 8.42, 245, 983, 'Orchid Worm', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Clover Honeyflow Carp', 4.82, 14.96, 251, 1008, 'Pollen Fly', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Velvet Orchidline Pike', 5.21, 17.8, 285, 1392, 'Dew Shrimp', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Honey Sugarrun Catfish', 5.6, 20.88, 320, 1835, 'Petal Nymph', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Lilac Grouper', 6, 24.21, 354, 967, 'Syrup Grub', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Blooming Glazecrest Sturgeon', 6.39, 11.93, 389, 1396, 'Honey Midge', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Amber Violettide Manta', 6.79, 14.77, 423, 1883, 'Lilac Larva', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Dewdrop Syrupfin Barracuda', 7.18, 17.86, 458, 2430, 'Bloom Cricket', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Meadow-Mistbloom Salmon', 7.58, 21.19, 492, 1132, 'Rose Beetle', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Silkpetal Fragrantide Swordfish', 7.97, 24.77, 527, 1664, 'Glaze Fry', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Garden Coelacanth', 8.37, 28.59, 561, 2256, 'Clover Gnat', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Sweetwater Sapstream Leviathan', 8.76, 32.65, 596, 2907, 'Garden Moth', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Starlily Bloomtail Guppy', 9.16, 36.96, 630, 3617, 'Amber Worm', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Orchid Pollencrest Smelt', 9.55, 17.83, 665, 1814, 'Nectar Moth', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Nectar Dewline Shiner', 9.95, 21.65, 699, 2510, 'Orchid Worm', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'epic', 'Rose Petalwave Perch', 10.34, 25.71, 734, 3264, 'Sweet Roe', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Velvet Sugarrun Gar', 12.63, 43.41, 748, 3329, 'Dew Shrimp', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Honey Flowerdrift Snapper', 13.66, 51.2, 851, 4518, 'Petal Nymph', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Lilac Eel', 14.7, 59.64, 954, 2194, 'Syrup Grub', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Blooming Violettide Ray', 15.73, 29.7, 1057, 3339, 'Honey Midge', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Amber Syrupfin Arowana', 16.77, 36.85, 1159, 4661, 'Lilac Larva', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Dewdrop Mistbloom Mackerel', 17.8, 44.65, 1262, 6160, 'Bloom Cricket', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Meadow-Fragrantide Marlin', 18.84, 53.09, 1365, 7836, 'Rose Beetle', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Silkpetal Nectarfin Shark', 19.87, 62.16, 1468, 4008, 'Glaze Fry', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Garden Tuna', 20.91, 71.88, 1571, 5639, 'Clover Gnat', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Sweetwater Bloomtail Minnow', 21.94, 82.25, 1674, 7448, 'Garden Moth', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Starlily Pollencrest Loach', 22.98, 93.25, 1777, 9433, 'Amber Worm', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Orchid Dewline Darter', 24.01, 45.34, 1879, 4323, 'Nectar Moth', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Nectar Petalwave Chub', 25.05, 55.06, 1982, 6264, 'Orchid Worm', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Rose Honeyflow Bream', 26.09, 65.42, 2085, 8382, 'Sweet Roe', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'legendary', 'Clover Trout', 27.12, 76.43, 2188, 10677, 'Pollen Fly', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Honey Glazecrest Grouper', 27.82, 105, 2112, 10307, 'Petal Nymph', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Lilac Sturgeon', 30.1, 123, 2402, 13790, 'Syrup Grub', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Blooming Syrupfin Manta', 32.38, 61.85, 2693, 7351, 'Honey Midge', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Amber Mistbloom Barracuda', 34.66, 76.95, 2983, 10710, 'Lilac Larva', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Dewdrop Fragrantide Salmon', 36.94, 93.47, 3274, 14568, 'Bloom Cricket', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Meadow-Nectarfin Swordfish', 39.23, 111, 3564, 18925, 'Rose Beetle', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Silkpetal Sapstream Coelacanth', 41.51, 131, 3854, 8865, 'Glaze Fry', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Garden Leviathan', 43.79, 152, 4145, 13098, 'Clover Gnat', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Sweetwater Pollencrest Guppy', 46.07, 174, 4435, 17830, 'Garden Moth', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Starlily Dewline Smelt', 48.35, 197, 4726, 23061, 'Amber Worm', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Orchid Petalwave Shiner', 50.63, 96.71, 5016, 28792, 'Nectar Moth', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Nectar Honeyflow Perch', 52.91, 117, 5306, 14486, 'Orchid Worm', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Rose Orchidline Carp', 55.19, 140, 5597, 20093, 'Sweet Roe', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Clover Pike', 57.48, 163, 5887, 26198, 'Pollen Fly', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'liminal', 'Velvet Flowerdrift Catfish', 59.76, 188, 6178, 32803, 'Dew Shrimp', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Lilac Ray', 60.99, 250, 5984, 31775, 'Syrup Grub', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Blooming Mistbloom Arowana', 65.99, 127, 6807, 15656, 'Honey Midge', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Amber Fragrantide Mackerel', 70.99, 159, 7630, 24110, 'Lilac Larva', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Dewdrop Nectarfin Marlin', 75.99, 194, 8452, 33979, 'Bloom Cricket', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Meadow-Sapstream Shark', 80.99, 232, 9275, 45263, 'Rose Beetle', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Silkpetal Bloomtail Tuna', 86, 273, 10098, 57963, 'Glaze Fry', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Garden Minnow', 91, 317, 10921, 29814, 'Clover Gnat', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Sweetwater Dewline Loach', 96, 364, 11744, 42160, 'Garden Moth', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Starlily Petalwave Darter', 101, 414, 12566, 55920, 'Amber Worm', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Orchid Honeyflow Chub', 106, 205, 13389, 71097, 'Nectar Moth', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Nectar Orchidline Bream', 111, 249, 14212, 32688, 'Orchid Worm', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Rose Sugarrun Trout', 116, 296, 15035, 47510, 'Sweet Roe', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Clover Gar', 121, 346, 15858, 63748, 'Pollen Fly', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Velvet Glazecrest Snapper', 126, 400, 16680, 81400, 'Dew Shrimp', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'mythic', 'Honey-Violettide Eel', 131, 456, 17503, 100468, 'Petal Nymph', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Blooming Fragrantide Barracuda', 132, 257, 16896, 96983, 'Honey Midge', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Amber Nectarfin Salmon', 142, 322, 19219, 52468, 'Lilac Larva', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Dewdrop Sapstream Swordfish', 153, 394, 21542, 77337, 'Bloom Cricket', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Meadow-Bloomtail Coelacanth', 164, 473, 23866, 106202, 'Rose Beetle', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Silkpetal Pollencrest Leviathan', 175, 558, 26189, 139063, 'Glaze Fry', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Garden Guppy', 186, 650, 28512, 65578, 'Clover Gnat', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Sweetwater Petalwave Smelt', 196, 749, 30835, 97439, 'Garden Moth', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Starlily Honeyflow Shiner', 207, 854, 33158, 133297, 'Amber Worm', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Orchid Orchidline Perch', 218, 426, 35482, 173150, 'Nectar Moth', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Nectar Sugarrun Carp', 229, 518, 37805, 217000, 'Orchid Worm', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Rose Flowerdrift Pike', 240, 617, 40128, 109549, 'Sweet Roe', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Clover Catfish', 250, 722, 42451, 152400, 'Pollen Fly', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Velvet Violettide Grouper', 261, 834, 44774, 199246, 'Dew Shrimp', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Honey-Syrupfin Sturgeon', 272, 953, 47098, 250088, 'Petal Nymph', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'ascendant', 'Lilac Mistbloom Manta', 283, 1078, 49421, 113668, 'Syrup Grub', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Amber Sapstream Marlin', 280, 641, 47520, 109296, 'Lilac Larva', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Dewdrop Bloomtail Shark', 303, 787, 54054, 170811, 'Bloom Cricket', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Meadow-Pollencrest Tuna', 326, 948, 60588, 243564, 'Rose Beetle', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Silkpetal Dewline Minnow', 349, 1123, 67122, 327555, 'Glaze Fry', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Garden Loach', 372, 1313, 73656, 422785, 'Clover Gnat', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Sweetwater Honeyflow Darter', 395, 1516, 80190, 218919, 'Garden Moth', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Starlily Orchidline Chub', 418, 1734, 86724, 311339, 'Amber Worm', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Orchid Sugarrun Bream', 441, 872, 93258, 414998, 'Nectar Moth', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Nectar Flowerdrift Trout', 464, 1061, 99792, 529896, 'Orchid Worm', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Rose Glazecrest Gar', 487, 1265, 106326, 244550, 'Sweet Roe', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Clover Snapper', 510, 1483, 112860, 356638, 'Pollen Fly', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Velvet Syrupfin Eel', 533, 1715, 119394, 479964, 'Dew Shrimp', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Honey-Mistbloom Ray', 556, 1961, 125928, 614529, 'Petal Nymph', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Lilac Fragrantide Arowana', 579, 2222, 132462, 760332, 'Syrup Grub', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'celestial', 'Blooming Nectarfin Mackerel', 602, 2497, 138996, 379459, 'Honey Midge', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Dewdrop Pollencrest Coelacanth', 594, 1555, 134640, 367567, 'Bloom Cricket', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Meadow-Dewline Leviathan', 643, 1881, 153153, 549819, 'Rose Beetle', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Silkpetal Petalwave Guppy', 691, 2238, 171666, 763914, 'Glaze Fry', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Garden Smelt', 740, 2625, 190179, 1009850, 'Clover Gnat', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Sweetwater Orchidline Shiner', 789, 3043, 208692, 479992, 'Garden Moth', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Starlily Sugarrun Perch', 837, 3490, 227205, 717968, 'Amber Worm', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Orchid Flowerdrift Carp', 886, 1770, 245718, 987786, 'Nectar Moth', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Nectar Glazecrest Pike', 935, 2157, 264231, 1289447, 'Orchid Worm', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Rose Violettide Catfish', 983, 2575, 282744, 1622951, 'Sweet Roe', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Clover Grouper', 1032, 3022, 301257, 822432, 'Pollen Fly', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Velvet Mistbloom Sturgeon', 1081, 3500, 319770, 1147974, 'Dew Shrimp', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Honey-Fragrantide Manta', 1130, 4007, 338283, 1505359, 'Petal Nymph', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Lilac Nectarfin Barracuda', 1178, 4545, 356796, 1894587, 'Syrup Grub', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Blooming Sapstream Salmon', 1227, 5114, 375309, 863211, 'Honey Midge', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'eldritch', 'Amber Bloomtail Swordfish', 1276, 2549, 393822, 1244478, 'Lilac Larva', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Meadow-Petalwave Minnow', 1263, 3725, 378400, 1195744, 'Rose Beetle', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Silkpetal Honeyflow Loach', 1366, 4454, 430430, 1730329, 'Glaze Fry', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Garden Darter', 1470, 5247, 482460, 2354405, 'Clover Gnat', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Sweetwater Sugarrun Chub', 1573, 6104, 534490, 3067973, 'Garden Moth', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Starlily Flowerdrift Bream', 1677, 7026, 586520, 1601200, 'Amber Worm', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Orchid Glazecrest Trout', 1780, 3596, 638550, 2292395, 'Nectar Moth', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Nectar Violettide Gar', 1884, 4389, 690580, 3073081, 'Orchid Worm', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Rose Syrupfin Snapper', 1987, 5247, 742610, 3943259, 'Sweet Roe', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Clover Eel', 2091, 6168, 794640, 1827672, 'Pollen Fly', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Velvet Fragrantide Ray', 2194, 7154, 846670, 2675477, 'Dew Shrimp', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Honey-Nectarfin Arowana', 2298, 8204, 898700, 3612774, 'Petal Nymph', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Lilac Sapstream Mackerel', 2401, 9318, 950730, 4639562, 'Syrup Grub', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Blooming Bloomtail Marlin', 2505, 10496, 1002760, 5755842, 'Honey Midge', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Amber Pollencrest Shark', 2609, 5269, 1054790, 2879577, 'Lilac Larva', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'eternal', 'Dewdrop Tuna', 2712, 6319, 1106820, 3973484, 'Bloom Cricket', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Silkpetal Orchidline Smelt', 2686, 8814, 1064800, 3822632, 'Glaze Fry', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Garden Shiner', 2906, 10438, 1211210, 5389884, 'Clover Gnat', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Sweetwater Flowerdrift Perch', 3126, 12198, 1357620, 7208962, 'Garden Moth', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Starlily Glazecrest Carp', 3346, 14095, 1504030, 3459269, 'Amber Worm', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Orchid Violettide Pike', 3567, 7283, 1650440, 5215390, 'Nectar Moth', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Nectar Syrupfin Catfish', 3787, 8907, 1796850, 7223337, 'Orchid Worm', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Rose Mistbloom Grouper', 4007, 10667, 1943260, 9483109, 'Sweet Roe', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Clover Sturgeon', 4227, 12564, 2089670, 11994706, 'Pollen Fly', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Velvet Nectarfin Manta', 4448, 14597, 2236080, 6104498, 'Dew Shrimp', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Honey-Sapstream Barracuda', 4668, 16767, 2382490, 8553139, 'Petal Nymph', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Lilac Bloomtail Salmon', 4888, 19073, 2528900, 11253605, 'Syrup Grub', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Blooming Pollencrest Swordfish', 5108, 21516, 2675310, 14205896, 'Honey Midge', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Amber Dewline Coelacanth', 5328, 10881, 2821720, 6489956, 'Lilac Larva', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Dewdrop Leviathan', 5549, 13050, 2968130, 9379291, 'Bloom Cricket', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'divine', 'Meadow Honeyflow Guppy', 5769, 15357, 3114540, 12520451, 'Rose Beetle', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Garden Chub', 5725, 20688, 3000800, 12063216, 'Clover Gnat', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Sweetwater Glazecrest Bream', 6194, 24305, 3413410, 16657441, 'Garden Moth', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Starlily Violettide Trout', 6663, 28212, 3826020, 21961355, 'Amber Worm', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Orchid Syrupfin Gar', 7133, 14722, 4238630, 11571460, 'Nectar Moth', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Nectar Mistbloom Snapper', 7602, 18047, 4651240, 16697952, 'Orchid Worm', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Rose Fragrantide Eel', 8072, 21664, 5063850, 22534133, 'Sweet Roe', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Clover Ray', 8541, 25572, 5476460, 29080003, 'Pollen Fly', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Velvet Sapstream Arowana', 9010, 29770, 5889070, 13544861, 'Dew Shrimp', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Honey-Bloomtail Mackerel', 9480, 34260, 6301680, 19913309, 'Petal Nymph', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Lilac Pollencrest Marlin', 9949, 39041, 6714290, 26991446, 'Syrup Grub', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Blooming Dewline Shark', 10419, 44112, 7126900, 34779272, 'Honey Midge', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Amber Petalwave Tuna', 10888, 22473, 7539510, 43276787, 'Lilac Larva', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Dewdrop Minnow', 11357, 26962, 7952120, 21709288, 'Bloom Cricket', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Meadow Orchidline Loach', 11827, 31743, 8364730, 30029381, 'Rose Beetle', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'cosmic', 'Silkpetal Sugarrun Darter', 12296, 36815, 8777340, 39059163, 'Glaze Fry', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Sweetwater Violettide Carp', 12198, 48133, 8456800, 37632760, 'Garden Moth', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Starlily Syrupfin Pike', 13198, 56172, 9619610, 51080129, 'Amber Worm', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Orchid Mistbloom Catfish', 14198, 29618, 10782420, 24799566, 'Nectar Moth', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Nectar Fragrantide Grouper', 15199, 36416, 11945230, 37746927, 'Orchid Worm', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Rose Nectarfin Sturgeon', 16199, 43834, 13108040, 52694321, 'Sweet Roe', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Clover Manta', 17199, 51873, 14270850, 69641748, 'Pollen Fly', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Velvet Bloomtail Barracuda', 18199, 60531, 15433660, 88589208, 'Dew Shrimp', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Honey-Pollencrest Salmon', 19200, 69810, 16596470, 45308363, 'Petal Nymph', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Lilac Dewline Swordfish', 20200, 79709, 17759280, 63755815, 'Syrup Grub', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Blooming Petalwave Coelacanth', 21200, 90228, 18922090, 84203300, 'Honey Midge', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Amber Honeyflow Leviathan', 22200, 46310, 20084900, 106650819, 'Lilac Larva', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Dewdrop Guppy', 23201, 55589, 21247710, 48869733, 'Bloom Cricket', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Meadow Sugarrun Smelt', 24201, 65487, 22410520, 70817243, 'Rose Beetle', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Silkpetal Flowerdrift Shiner', 25201, 76006, 23573330, 94764787, 'Glaze Fry', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'primordial', 'Garden Glazecrest Perch', 26201, 87146, 24736140, 120712363, 'Clover Gnat', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Starlily Mistbloom Gar', 26108, 111690, 23760000, 115948800, 'Amber Worm', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Orchid Fragrantide Snapper', 28249, 59549, 27027000, 155134980, 'Nectar Moth', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Nectar Nectarfin Eel', 30390, 73482, 30294000, 82702620, 'Orchid Worm', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Rose Sapstream Ray', 32531, 88743, 33561000, 120483990, 'Sweet Roe', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Clover Arowana', 34671, 105332, 36828000, 163884600, 'Pollen Fly', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Velvet Pollencrest Mackerel', 36812, 123248, 40095000, 212904450, 'Dew Shrimp', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Honey-Dewline Marlin', 38953, 142491, 43362000, 99732600, 'Petal Nymph', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Lilac Petalwave Shark', 41094, 163061, 46629000, 147347640, 'Syrup Grub', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Blooming Honeyflow Tuna', 43235, 184959, 49896000, 200581920, 'Honey Midge', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Amber Orchidline Minnow', 45376, 95652, 53163000, 259435440, 'Lilac Larva', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Dewdrop Loach', 47517, 114895, 56430000, 323908200, 'Bloom Cricket', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Meadow Flowerdrift Darter', 49657, 135465, 59697000, 162972810, 'Rose Beetle', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Silkpetal Glazecrest Chub', 51798, 157363, 62964000, 226040760, 'Glaze Fry', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Garden Violettide Bream', 53939, 180588, 66231000, 294727950, 'Clover Gnat', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'transcendent', 'Sweetwater Syrupfin Trout', 56080, 205141, 69498000, 369034380, 'Garden Moth', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Orchid Nectarfin Grouper', 55854, 118969, 66880000, 355132800, 'Nectar Moth', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Nectar Sapstream Sturgeon', 60434, 147459, 76076000, 174974800, 'Orchid Worm', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Rose Bloomtail Manta', 65014, 178789, 85272000, 269459520, 'Sweet Roe', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Clover Barracuda', 69594, 212958, 94468000, 379761360, 'Pollen Fly', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Velvet Dewline Salmon', 74174, 249967, 103664000, 505880320, 'Dew Shrimp', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Honey-Petalwave Swordfish', 78754, 289815, 112860000, 647816400, 'Petal Nymph', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Lilac Honeyflow Coelacanth', 83334, 332503, 122056000, 333212880, 'Syrup Grub', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Blooming Orchidline Leviathan', 87914, 378031, 131252000, 471194680, 'Honey Midge', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Amber Sugarrun Guppy', 92494, 197013, 140448000, 624993600, 'Lilac Larva', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Dewdrop Smelt', 97074, 236861, 149644000, 794609640, 'Bloom Cricket', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Meadow Glazecrest Shiner', 101654, 279549, 158840000, 365332000, 'Rose Beetle', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Silkpetal Violettide Perch', 106234, 325077, 168036000, 530993760, 'Glaze Fry', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Garden Syrupfin Carp', 110814, 373444, 177232000, 712472640, 'Clover Gnat', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Sweetwater Mistbloom Pike', 115394, 424651, 186428000, 909768640, 'Garden Moth', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'apotheosis', 'Starlily Fragrantide Catfish', 119974, 478698, 195624000, 1122881760, 'Amber Worm', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Nectar Bloomtail Ray', 119840, 295046, 188320000, 1080956800, 'Orchid Worm', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Rose Pollencrest Arowana', 129667, 359437, 214214000, 584804220, 'Sweet Roe', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Clover Mackerel', 139494, 429920, 240108000, 861987720, 'Pollen Fly', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Velvet Petalwave Marlin', 149321, 506496, 266002000, 1183708900, 'Dew Shrimp', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Honey-Honeyflow Shark', 159148, 589164, 291896000, 1549967760, 'Petal Nymph', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Lilac Orchidline Tuna', 168974, 677925, 317790000, 730917000, 'Syrup Grub', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Blooming Sugarrun Minnow', 178801, 772779, 343684000, 1086041440, 'Honey Midge', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Amber Flowerdrift Loach', 188628, 405928, 369578000, 1485703560, 'Lilac Larva', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Dewdrop Darter', 198455, 488596, 395472000, 1929903360, 'Bloom Cricket', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Meadow Violettide Chub', 208282, 577357, 421366000, 2418640840, 'Rose Beetle', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Silkpetal Syrupfin Bream', 218109, 672211, 447260000, 1221019800, 'Glaze Fry', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Garden Mistbloom Trout', 227936, 773158, 473154000, 1698622860, 'Clover Gnat', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Sweetwater Fragrantide Gar', 237763, 880197, 499048000, 2220763600, 'Garden Moth', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Starlily Nectarfin Snapper', 247589, 993329, 524942000, 2787442020, 'Amber Worm', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'absolute', 'Orchid Eel', 257416, 1112553, 550836000, 1266922800, 'Nectar Moth', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Rose Dewline Barracuda', 256800, 717499, 530640000, 1220472000, 'Sweet Roe', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Clover Salmon', 277858, 862470, 603603000, 1907385480, 'Pollen Fly', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Velvet Honeyflow Swordfish', 298915, 1020496, 676566000, 2719795320, 'Dew Shrimp', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Honey-Orchidline Coelacanth', 319973, 1191579, 749529000, 3657701520, 'Petal Nymph', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Lilac Sugarrun Leviathan', 341030, 1375717, 822492000, 4721104080, 'Syrup Grub', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Blooming Flowerdrift Guppy', 362088, 1572910, 895455000, 2444592150, 'Honey Midge', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Amber Glazecrest Smelt', 383146, 832959, 968418000, 3476620620, 'Lilac Larva', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Dewdrop Shiner', 404203, 1004041, 1041381000, 4634145450, 'Bloom Cricket', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Meadow Syrupfin Perch', 425261, 1188179, 1114344000, 5917166640, 'Rose Beetle', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Silkpetal Mistbloom Carp', 446318, 1385372, 1187307000, 2730806100, 'Glaze Fry', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Garden Fragrantide Pike', 467376, 1595622, 1260270000, 3982453200, 'Clover Gnat', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Sweetwater Nectarfin Catfish', 488434, 1818927, 1333233000, 5359596660, 'Garden Moth', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Starlily Sapstream Grouper', 509491, 2055288, 1406196000, 6862236480, 'Amber Worm', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Orchid Sturgeon', 530549, 2304704, 1479159000, 8490372660, 'Nectar Moth', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'singularity', 'Nectar Pollencrest Manta', 551606, 1199192, 1552122000, 4237293060, 'Orchid Worm', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Clover Marlin', 551050, 1722582, 1496000000, 4084080000, 'Pollen Fly', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Velvet Orchidline Shark', 596236, 2048667, 1701700000, 6109103000, 'Dew Shrimp', 'Prefers calm pools with warm flow.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Honey-Sugarrun Tuna', 641422, 2402768, 1907400000, 8487930000, 'Petal Nymph', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Lilac Flowerdrift Minnow', 686608, 2784883, 2113100000, 11220561000, 'Syrup Grub', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Blooming Glazecrest Loach', 731794, 3195014, 2318800000, 5333240000, 'Honey Midge', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Amber Violettide Darter', 776981, 1706249, 2524500000, 7977420000, 'Lilac Larva', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Dewdrop Chub', 822167, 2060349, 2730200000, 10975404000, 'Bloom Cricket', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Meadow Mistbloom Bream', 867353, 2442465, 2935900000, 14327192000, 'Rose Beetle', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Silkpetal Fragrantide Trout', 912539, 2852596, 3141600000, 18032784000, 'Glaze Fry', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Garden Nectarfin Gar', 957725, 3290743, 3347300000, 9138129000, 'Clover Gnat', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Sweetwater Sapstream Snapper', 1002911, 3756905, 3553000000, 12755270000, 'Garden Moth', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Starlily Bloomtail Eel', 1048097, 4251082, 3758700000, 16726215000, 'Amber Worm', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Orchid Ray', 1093283, 4773274, 3964400000, 21050964000, 'Nectar Moth', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Nectar Dewline Arowana', 1138469, 2500079, 4170100000, 9591230000, 'Orchid Worm', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'paradox', 'Rose Petalwave Mackerel', 1183655, 2966240, 4375800000, 13827528000, 'Sweet Roe', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Velvet Sugarrun Coelacanth', 1181280, 4084866, 4224000000, 13347840000, 'Dew Shrimp', 'Feeds near concentrated sugar seams.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Honey-Flowerdrift Leviathan', 1278145, 4816050, 4804800000, 19315296000, 'Petal Nymph', 'Rises during cool pre-dawn hours.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Lilac Glazecrest Guppy', 1375010, 5607290, 5385600000, 26281728000, 'Syrup Grub', 'Responds to short twitch retrieves.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Blooming Violettide Smelt', 1471875, 6458587, 5966400000, 34247136000, 'Honey Midge', 'Can burrow into soft petal sediment.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Amber Syrupfin Shiner', 1568740, 3479465, 6547200000, 17873856000, 'Lilac Larva', 'Spooks at harsh, sudden light.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Dewdrop Perch', 1665605, 4210649, 7128000000, 25589520000, 'Bloom Cricket', 'Runs long before circling back.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Meadow Fragrantide Carp', 1762470, 5001889, 7708800000, 34304160000, 'Rose Beetle', 'Leaves soft rainbow sheen in wake.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Silkpetal Nectarfin Pike', 1859335, 5853186, 8289600000, 44017776000, 'Glaze Fry', 'Thrives in thick syrup-like channels.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Garden Sapstream Catfish', 1956200, 6764538, 8870400000, 20401920000, 'Clover Gnat', 'Bites sharply after nectar upwells.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Sweetwater Bloomtail Grouper', 2053065, 7735948, 9451200000, 29865792000, 'Garden Moth', 'Favors ultraviolet-lit floral pockets.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Starlily Pollencrest Sturgeon', 2149930, 8767413, 10032000000, 40328640000, 'Amber Worm', 'Can hold line against sticky currents.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Orchid Manta', 2246795, 9858935, 10612800000, 51790464000, 'Nectar Moth', 'Schools around giant orchid roots.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Nectar Petalwave Barracuda', 2343660, 5198237, 11193600000, 64251264000, 'Orchid Worm', 'Tracks fragrant bait with precision.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Rose Honeyflow Salmon', 2440524, 6169646, 11774400000, 32144112000, 'Sweet Roe', 'Turns iridescent in sunset haze.'),
  ('nectar_nexus', 'Nectar Nexus', 'null', 'Clover Orchidline Swordfish', 2537389, 7201111, 12355200000, 44355168000, 'Pollen Fly', 'Prefers calm pools with warm flow.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Bog Minnow', 0.23, 0.55, 9.6, 30.34, 'Mire Worm', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Rooted Bogrun Loach', 0.25, 0.67, 10.92, 43.9, 'Root Grub', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Peat Siltback Darter', 0.27, 0.81, 12.24, 59.73, 'Peat Midge', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Marsh Mossgill Chub', 0.28, 0.95, 13.56, 77.83, 'Marsh Fry', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Alder Fencrest Bream', 0.3, 1.11, 14.88, 40.62, 'Silt Shrimp', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Mossback Miretail Trout', 0.32, 1.28, 16.2, 58.16, 'Reed Nymph', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Driftwood Gar', 0.34, 0.61, 17.52, 77.96, 'Bog Beetle', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Fen Reedfin Snapper', 0.36, 0.76, 18.84, 100, 'Fen Roe', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Ironroot Claycrest Eel', 0.38, 0.91, 20.16, 46.37, 'Clay Larva', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Mire Hollowfin Ray', 0.4, 1.08, 21.48, 67.88, 'Moss Cricket', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Silt-Mudline Arowana', 0.41, 1.26, 22.8, 91.66, 'Umber Fly', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Reed Stonegill Mackerel', 0.43, 1.45, 24.12, 118, 'Drift Gnat', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Bramble Marlin', 0.45, 1.66, 25.44, 146, 'Tangle Moth', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Hollow Marshwake Shark', 0.47, 1.87, 26.76, 73.05, 'Alder Worm', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'common', 'Umber Deepbog Tuna', 0.49, 0.88, 28.08, 101, 'Hollow Grub', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Rooted Siltback Smelt', 0.78, 2.13, 28.8, 103, 'Root Grub', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Peat Mossgill Shiner', 0.84, 2.57, 32.76, 146, 'Peat Midge', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Marsh Fencrest Perch', 0.9, 3.04, 36.72, 195, 'Marsh Fry', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Alder Miretail Carp', 0.97, 3.56, 40.68, 93.56, 'Silt Shrimp', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Mossback Driftline Pike', 1.03, 4.11, 44.64, 141, 'Reed Nymph', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Driftwood Catfish', 1.09, 1.99, 48.6, 195, 'Bog Beetle', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Fen Claycrest Grouper', 1.16, 2.47, 52.56, 256, 'Fen Roe', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Ironroot Hollowfin Sturgeon', 1.22, 2.98, 56.52, 324, 'Clay Larva', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Mire Mudline Manta', 1.28, 3.53, 60.48, 165, 'Moss Cricket', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Silt-Stonegill Barracuda', 1.35, 4.13, 64.44, 231, 'Umber Fly', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Reed Tanglefin Salmon', 1.41, 4.76, 68.4, 304, 'Drift Gnat', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Bramble Swordfish', 1.47, 5.43, 72.36, 384, 'Tangle Moth', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Hollow Deepbog Coelacanth', 1.54, 6.14, 76.32, 176, 'Alder Worm', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Umber Rootfin Leviathan', 1.6, 2.92, 80.28, 254, 'Hollow Grub', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'uncommon', 'Bog Bogrun Guppy', 1.67, 3.55, 84.24, 339, 'Mire Worm', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Peat Fencrest Chub', 1.94, 5.98, 91.2, 367, 'Peat Midge', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Marsh Miretail Bream', 2.1, 7.12, 104, 506, 'Marsh Fry', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Alder Driftline Trout', 2.26, 8.36, 116, 667, 'Silt Shrimp', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Mossback Reedfin Gar', 2.41, 9.69, 129, 352, 'Reed Nymph', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Driftwood Snapper', 2.57, 4.75, 141, 507, 'Bog Beetle', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Fen Hollowfin Eel', 2.73, 5.89, 154, 685, 'Fen Roe', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Ironroot Mudline Ray', 2.89, 7.12, 166, 884, 'Clay Larva', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Mire Stonegill Arowana', 3.05, 8.46, 179, 412, 'Moss Cricket', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Silt-Tanglefin Mackerel', 3.21, 9.9, 192, 605, 'Umber Fly', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Reed Marshwake Marlin', 3.37, 11.43, 204, 820, 'Drift Gnat', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Bramble Shark', 3.53, 13.06, 217, 1057, 'Tangle Moth', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Hollow Rootfin Tuna', 3.69, 14.8, 229, 1315, 'Alder Worm', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Umber Bogrun Minnow', 3.84, 7.09, 242, 660, 'Hollow Grub', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Bog Siltback Loach', 4, 8.62, 254, 913, 'Mire Worm', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'rare', 'Rooted Mossgill Darter', 4.16, 10.26, 267, 1187, 'Root Grub', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Marsh Driftline Carp', 5.13, 17.52, 274, 1218, 'Marsh Fry', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Alder Reedfin Pike', 5.55, 20.68, 311, 1653, 'Silt Shrimp', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Mossback Claycrest Catfish', 5.97, 24.1, 349, 802, 'Reed Nymph', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Driftwood Grouper', 6.39, 11.93, 386, 1221, 'Bog Beetle', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Fen Mudline Sturgeon', 6.81, 14.82, 424, 1705, 'Fen Roe', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Ironroot Stonegill Manta', 7.23, 17.98, 462, 2253, 'Clay Larva', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Mire Tanglefin Barracuda', 7.65, 21.4, 499, 2866, 'Moss Cricket', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Silt-Marshwake Salmon', 8.07, 25.08, 537, 1466, 'Umber Fly', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Reed Deepbog Swordfish', 8.5, 29.02, 575, 2063, 'Drift Gnat', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Bramble Coelacanth', 8.92, 33.22, 612, 2724, 'Tangle Moth', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Hollow Bogrun Leviathan', 9.34, 37.68, 650, 3450, 'Alder Worm', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Umber Siltback Guppy', 9.76, 18.21, 687, 1581, 'Hollow Grub', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Bog Mossgill Smelt', 10.18, 22.15, 725, 2291, 'Mire Worm', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Rooted Fencrest Shiner', 10.6, 26.35, 763, 3066, 'Root Grub', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'epic', 'Peat Miretail Perch', 11.02, 30.81, 800, 3905, 'Peat Midge', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Alder Claycrest Gar', 13.45, 50.42, 816, 3982, 'Silt Shrimp', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Mossback Hollowfin Snapper', 14.56, 59.06, 928, 5328, 'Reed Nymph', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Driftwood Eel', 15.66, 29.56, 1040, 2840, 'Bog Beetle', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Fen Stonegill Ray', 16.76, 36.84, 1153, 4138, 'Fen Roe', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Ironroot Tanglefin Arowana', 17.86, 44.8, 1265, 5628, 'Clay Larva', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Mire Marshwake Mackerel', 18.97, 53.45, 1377, 7312, 'Moss Cricket', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Silt-Deepbog Marlin', 20.07, 62.78, 1489, 3425, 'Umber Fly', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Reed Rootfin Shark', 21.17, 72.79, 1601, 5060, 'Drift Gnat', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Bramble Tuna', 22.28, 83.49, 1714, 6889, 'Tangle Moth', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Hollow Siltback Minnow', 23.38, 94.87, 1826, 8910, 'Alder Worm', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Umber Mossgill Loach', 24.48, 46.22, 1938, 11124, 'Hollow Grub', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Bog Fencrest Darter', 25.59, 56.24, 2050, 5597, 'Mire Worm', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Rooted Miretail Chub', 26.69, 66.94, 2162, 7763, 'Root Grub', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Peat Driftline Bream', 27.79, 78.32, 2275, 10122, 'Peat Midge', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'legendary', 'Marsh Trout', 28.89, 90.38, 2387, 12674, 'Marsh Fry', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Mossback Mudline Grouper', 29.64, 121, 2304, 12234, 'Reed Nymph', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Driftwood Sturgeon', 32.07, 61.25, 2621, 6028, 'Bog Beetle', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Fen Tanglefin Manta', 34.5, 76.59, 2938, 9283, 'Fen Roe', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Ironroot Marshwake Barracuda', 36.93, 93.44, 3254, 13083, 'Clay Larva', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Mire Deepbog Salmon', 39.36, 112, 3571, 17427, 'Moss Cricket', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Silt-Rootfin Swordfish', 41.79, 132, 3888, 22317, 'Umber Fly', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Reed Bogrun Coelacanth', 44.22, 153, 4205, 11479, 'Drift Gnat', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Bramble Leviathan', 46.65, 176, 4522, 16233, 'Tangle Moth', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Hollow Mossgill Guppy', 49.08, 200, 4838, 21531, 'Alder Worm', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Umber Fencrest Smelt', 51.51, 98.39, 5155, 27374, 'Hollow Grub', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Bog Miretail Shiner', 53.94, 120, 5472, 12586, 'Mire Worm', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Rooted Driftline Perch', 56.38, 143, 5789, 18293, 'Root Grub', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Peat Reedfin Carp', 58.81, 167, 6106, 24545, 'Peat Midge', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Marsh Pike', 61.24, 193, 6422, 31341, 'Marsh Fry', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'liminal', 'Alder Hollowfin Catfish', 63.67, 220, 6739, 38683, 'Silt Shrimp', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Driftwood Ray', 64.98, 126, 6528, 37471, 'Bog Beetle', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Fen Marshwake Arowana', 70.31, 158, 7426, 20272, 'Fen Roe', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Ironroot Deepbog Mackerel', 75.64, 193, 8323, 29880, 'Clay Larva', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Mire Rootfin Marlin', 80.97, 232, 9221, 41033, 'Moss Cricket', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Silt-Bogrun Shark', 86.29, 274, 10118, 53729, 'Umber Fly', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Reed Siltback Tuna', 91.62, 319, 11016, 25337, 'Drift Gnat', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Bramble Minnow', 96.95, 368, 11914, 37647, 'Tangle Moth', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Hollow Fencrest Loach', 102, 420, 12811, 51501, 'Alder Worm', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Umber Miretail Darter', 108, 208, 13709, 66899, 'Hollow Grub', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Bog Driftline Chub', 113, 253, 14606, 83841, 'Mire Worm', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Rooted Reedfin Bream', 118, 302, 15504, 42326, 'Root Grub', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Peat Claycrest Trout', 124, 354, 16402, 58882, 'Peat Midge', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Marsh Gar', 129, 409, 17299, 76981, 'Marsh Fry', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Alder Mudline Snapper', 134, 467, 18197, 96625, 'Silt Shrimp', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'mythic', 'Mossback-Stonegill Eel', 140, 529, 19094, 43917, 'Reed Nymph', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Fen Deepbog Barracuda', 140, 317, 18432, 42394, 'Fen Roe', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Ironroot Rootfin Salmon', 152, 391, 20966, 66254, 'Clay Larva', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Mire Bogrun Swordfish', 163, 471, 23501, 94473, 'Moss Cricket', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Silt-Siltback Coelacanth', 175, 558, 26035, 127052, 'Umber Fly', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Reed Mossgill Leviathan', 186, 652, 28570, 163990, 'Drift Gnat', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Bramble Guppy', 198, 754, 31104, 84914, 'Tangle Moth', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Hollow Miretail Smelt', 209, 863, 33638, 120762, 'Alder Worm', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Umber Driftline Shiner', 221, 431, 36173, 160969, 'Hollow Grub', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Bog Reedfin Perch', 232, 526, 38707, 205535, 'Mire Worm', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Rooted Claycrest Carp', 244, 627, 41242, 94856, 'Root Grub', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Peat Hollowfin Pike', 255, 736, 43776, 138332, 'Peat Midge', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Marsh Catfish', 267, 852, 46310, 186168, 'Marsh Fry', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Alder Stonegill Grouper', 278, 975, 48845, 238363, 'Silt Shrimp', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Mossback-Tanglefin Sturgeon', 290, 1105, 51379, 294917, 'Reed Nymph', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'ascendant', 'Driftwood Marshwake Manta', 301, 1242, 53914, 147184, 'Bog Beetle', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Ironroot Bogrun Marlin', 299, 775, 51840, 141523, 'Clay Larva', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Mire Siltback Shark', 323, 939, 58968, 211695, 'Moss Cricket', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Silt-Mossgill Tuna', 348, 1118, 66096, 294127, 'Umber Fly', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Reed Fencrest Minnow', 372, 1312, 73224, 388819, 'Drift Gnat', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Bramble Loach', 397, 1522, 80352, 184810, 'Tangle Moth', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Hollow Driftline Darter', 421, 1746, 87480, 276437, 'Alder Worm', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Umber Reedfin Chub', 446, 881, 94608, 380324, 'Hollow Grub', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Bog Claycrest Bream', 470, 1075, 101736, 496472, 'Mire Worm', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Rooted Hollowfin Trout', 495, 1284, 108864, 624879, 'Root Grub', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Peat Mudline Gar', 519, 1509, 115992, 316658, 'Peat Midge', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Marsh Snapper', 544, 1748, 123120, 442001, 'Marsh Fry', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Alder Tanglefin Eel', 568, 2003, 130248, 579604, 'Silt Shrimp', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Mossback-Marshwake Ray', 593, 2273, 137376, 729467, 'Reed Nymph', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Driftwood Deepbog Arowana', 617, 2558, 144504, 332359, 'Bog Beetle', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'celestial', 'Fen Rootfin Mackerel', 642, 1268, 151632, 479157, 'Fen Roe', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Mire Mossgill Coelacanth', 633, 1853, 146880, 464141, 'Moss Cricket', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Silt-Fencrest Leviathan', 685, 2217, 167076, 671646, 'Umber Fly', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Reed Miretail Guppy', 736, 2613, 187272, 913887, 'Drift Gnat', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Bramble Smelt', 788, 3041, 207468, 1190866, 'Tangle Moth', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Hollow Reedfin Shiner', 840, 3502, 227664, 621523, 'Alder Worm', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Umber Claycrest Perch', 892, 1782, 247860, 889817, 'Hollow Grub', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Bog Hollowfin Carp', 944, 2179, 268056, 1192849, 'Mire Worm', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Rooted Mudline Pike', 996, 2607, 288252, 1530618, 'Root Grub', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Peat Stonegill Catfish', 1048, 3068, 308448, 709430, 'Peat Midge', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Marsh Grouper', 1100, 3561, 328644, 1038515, 'Marsh Fry', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Alder Marshwake Sturgeon', 1152, 4086, 348840, 1402337, 'Silt Shrimp', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Mossback-Deepbog Manta', 1203, 4643, 369036, 1800896, 'Reed Nymph', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Driftwood Rootfin Barracuda', 1255, 5232, 389232, 2234192, 'Bog Beetle', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Fen Bogrun Salmon', 1307, 2612, 409428, 1117738, 'Fen Roe', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eldritch', 'Ironroot Siltback Swordfish', 1359, 3137, 429624, 1542350, 'Clay Larva', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Silt-Miretail Minnow', 1345, 4385, 412800, 1481952, 'Umber Fly', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Reed Driftline Loach', 1456, 5196, 469560, 2089542, 'Drift Gnat', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Bramble Darter', 1566, 6075, 526320, 2794759, 'Tangle Moth', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Hollow Claycrest Chub', 1676, 7023, 583080, 1341084, 'Alder Worm', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Umber Hollowfin Bream', 1786, 3609, 639840, 2021894, 'Hollow Grub', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Bog Mudline Trout', 1897, 4419, 696600, 2800332, 'Mire Worm', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Rooted Stonegill Gar', 2007, 5299, 753360, 3676397, 'Root Grub', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Peat Tanglefin Snapper', 2117, 6246, 810120, 4650089, 'Peat Midge', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Marsh Eel', 2228, 7262, 866880, 2366582, 'Marsh Fry', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Alder Deepbog Ray', 2338, 8347, 923640, 3315868, 'Silt Shrimp', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Mossback-Rootfin Arowana', 2448, 9499, 980400, 4362780, 'Reed Nymph', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Driftwood Bogrun Mackerel', 2559, 10720, 1037160, 5507320, 'Bog Beetle', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Fen Siltback Marlin', 2669, 5391, 1093920, 2516016, 'Fen Roe', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Ironroot Mossgill Shark', 2779, 6475, 1150680, 3636149, 'Clay Larva', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'eternal', 'Mire Tuna', 2889, 7628, 1207440, 4853909, 'Moss Cricket', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Reed Reedfin Smelt', 2861, 10278, 1161600, 4669632, 'Drift Gnat', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Bramble Shiner', 3096, 12081, 1321320, 6448042, 'Tangle Moth', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Hollow Hollowfin Perch', 3331, 14029, 1481040, 8501170, 'Alder Worm', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Umber Mudline Carp', 3565, 7280, 1640760, 4479275, 'Hollow Grub', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Bog Stonegill Pike', 3800, 8937, 1800480, 6463723, 'Mire Worm', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Rooted Tanglefin Catfish', 4035, 10740, 1960200, 8722890, 'Root Grub', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Peat Marshwake Grouper', 4269, 12688, 2119920, 11256775, 'Peat Midge', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Marsh Sturgeon', 4504, 14782, 2279640, 5243172, 'Marsh Fry', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Alder Rootfin Manta', 4738, 17021, 2439360, 7708378, 'Silt Shrimp', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Mossback-Bogrun Barracuda', 4973, 19405, 2599080, 10448302, 'Reed Nymph', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Driftwood Siltback Salmon', 5208, 21935, 2758800, 13462944, 'Bog Beetle', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Fen Mossgill Swordfish', 5442, 11113, 2918520, 16752305, 'Fen Roe', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Ironroot Fencrest Coelacanth', 5677, 13352, 3078240, 8403595, 'Clay Larva', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Mire Leviathan', 5912, 15737, 3237960, 11624276, 'Moss Cricket', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'divine', 'Silt Driftline Guppy', 6146, 18267, 3397680, 15119676, 'Umber Fly', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Bramble Chub', 6099, 23932, 3273600, 14567520, 'Tangle Moth', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Hollow Mudline Bream', 6599, 27941, 3723720, 19772953, 'Alder Worm', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Umber Stonegill Trout', 7099, 14653, 4173840, 9599832, 'Hollow Grub', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Bog Tanglefin Gar', 7599, 18041, 4623960, 14611714, 'Mire Worm', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Rooted Marshwake Snapper', 8099, 21739, 5074080, 20397802, 'Root Grub', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Peat Deepbog Eel', 8600, 25747, 5524200, 26958096, 'Peat Midge', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Marsh Ray', 9100, 30065, 5974320, 34292597, 'Marsh Fry', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Alder Bogrun Arowana', 9600, 34694, 6424440, 17538721, 'Silt Shrimp', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Mossback-Siltback Mackerel', 10100, 39632, 6874560, 24679670, 'Reed Nymph', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Driftwood Mossgill Marlin', 10600, 44881, 7324680, 32594826, 'Bog Beetle', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Fen Fencrest Shark', 11100, 22911, 7774800, 41284188, 'Fen Roe', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Ironroot Miretail Tuna', 11600, 27539, 8224920, 18917316, 'Clay Larva', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Mire Minnow', 12100, 32478, 8675040, 27413126, 'Moss Cricket', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Silt Reedfin Loach', 12601, 37726, 9125160, 36683143, 'Umber Fly', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'cosmic', 'Reed Claycrest Darter', 13101, 43285, 9575280, 46727366, 'Drift Gnat', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Hollow Stonegill Carp', 12996, 55311, 9225600, 45020928, 'Alder Worm', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Umber Tanglefin Pike', 14062, 29333, 10494120, 60236249, 'Hollow Grub', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Bog Marshwake Catfish', 15127, 36245, 11762640, 32112007, 'Mire Worm', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Rooted Deepbog Grouper', 16193, 43818, 13031160, 46781864, 'Root Grub', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Peat Rootfin Sturgeon', 17259, 52052, 14299680, 63633576, 'Peat Midge', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Marsh Manta', 18324, 60947, 15568200, 82667142, 'Marsh Fry', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Alder Siltback Barracuda', 19390, 70502, 16836720, 38724456, 'Silt Shrimp', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Mossback-Mossgill Salmon', 20456, 80718, 18105240, 57212558, 'Reed Nymph', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Driftwood Fencrest Swordfish', 21521, 91595, 19373760, 77882515, 'Bog Beetle', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Fen Miretail Coelacanth', 22587, 47117, 20642280, 100734326, 'Fen Roe', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Ironroot Driftline Leviathan', 23653, 56672, 21910800, 125767992, 'Clay Larva', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Mire Guppy', 24718, 66888, 23179320, 63279544, 'Moss Cricket', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Silt Claycrest Smelt', 25784, 77765, 24447840, 87767746, 'Umber Fly', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Reed Hollowfin Shiner', 26850, 89302, 25716360, 114437802, 'Drift Gnat', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'primordial', 'Bramble Mudline Perch', 27915, 101500, 26984880, 143289713, 'Tangle Moth', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Umber Marshwake Gar', 27816, 58636, 25920000, 137635200, 'Hollow Grub', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Bog Deepbog Snapper', 30097, 72774, 29484000, 67813200, 'Mire Worm', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Rooted Rootfin Eel', 32378, 88327, 33048000, 104431680, 'Root Grub', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Peat Bogrun Ray', 34659, 105293, 36612000, 147180240, 'Peat Midge', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Marsh Arowana', 36940, 123674, 40176000, 196058880, 'Marsh Fry', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Alder Mossgill Mackerel', 39221, 143469, 43740000, 251067600, 'Silt Shrimp', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Mossback-Fencrest Marlin', 41501, 164678, 47304000, 129139920, 'Reed Nymph', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Driftwood Miretail Shark', 43782, 187301, 50868000, 182616120, 'Bog Beetle', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Fen Driftline Tuna', 46063, 97101, 54432000, 242222400, 'Fen Roe', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Ironroot Reedfin Minnow', 48344, 116896, 57996000, 307958760, 'Clay Larva', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Mire Loach', 50625, 138105, 61560000, 141588000, 'Moss Cricket', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Silt Hollowfin Darter', 52906, 160729, 65124000, 205791840, 'Umber Fly', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Reed Mudline Chub', 55187, 184766, 68688000, 276125760, 'Drift Gnat', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Bramble Stonegill Bream', 57468, 210217, 72252000, 352589760, 'Tangle Moth', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'transcendent', 'Hollow Tanglefin Trout', 59749, 237083, 75816000, 435183840, 'Alder Worm', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Bog Rootfin Grouper', 59508, 145200, 72960000, 418790400, 'Mire Worm', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Rooted Bogrun Sturgeon', 64388, 177066, 82992000, 226568160, 'Root Grub', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Peat Siltback Manta', 69267, 211958, 93024000, 333956160, 'Peat Midge', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Marsh Barracuda', 74147, 249875, 103056000, 458599200, 'Marsh Fry', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Alder Fencrest Salmon', 79027, 290818, 113088000, 600497280, 'Silt Shrimp', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Mossback-Miretail Swordfish', 83906, 334786, 123120000, 283176000, 'Reed Nymph', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Driftwood Driftline Coelacanth', 88786, 381780, 133152000, 420760320, 'Bog Beetle', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Fen Reedfin Leviathan', 93666, 199508, 143184000, 575599680, 'Fen Roe', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Ironroot Claycrest Guppy', 98545, 240450, 153216000, 747694080, 'Clay Larva', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Mire Smelt', 103425, 284418, 163248000, 937043520, 'Moss Cricket', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Silt Mudline Shiner', 108305, 331412, 173280000, 473054400, 'Umber Fly', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Reed Stonegill Perch', 113184, 381431, 183312000, 658090080, 'Drift Gnat', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Bramble Tanglefin Carp', 118064, 434475, 193344000, 860380800, 'Tangle Moth', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Hollow Marshwake Pike', 122944, 490545, 203376000, 1079926560, 'Alder Worm', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'apotheosis', 'Umber Deepbog Catfish', 127823, 549640, 213408000, 490838400, 'Hollow Grub', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Rooted Siltback Ray', 127680, 353929, 205440000, 472512000, 'Root Grub', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Peat Mossgill Arowana', 138150, 425778, 233688000, 738454080, 'Peat Midge', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Marsh Mackerel', 148620, 504117, 261936000, 1052982720, 'Marsh Fry', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Alder Miretail Marlin', 159089, 588949, 290184000, 1416097920, 'Silt Shrimp', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Mossback-Driftline Shark', 169559, 680271, 318432000, 1827799680, 'Reed Nymph', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Driftwood Reedfin Tuna', 180029, 778084, 346680000, 946436400, 'Bog Beetle', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Fen Claycrest Minnow', 190499, 409953, 374928000, 1345991520, 'Fen Roe', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Ironroot Hollowfin Loach', 200968, 494784, 403176000, 1794133200, 'Clay Larva', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Mire Darter', 211438, 586106, 431424000, 2290861440, 'Moss Cricket', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Silt Stonegill Chub', 221908, 683920, 459672000, 1057245600, 'Umber Fly', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Reed Tanglefin Bream', 232378, 788225, 487920000, 1541827200, 'Drift Gnat', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Bramble Marshwake Trout', 242847, 899021, 516168000, 2074995360, 'Tangle Moth', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Hollow Deepbog Gar', 253317, 1016308, 544416000, 2656750080, 'Alder Worm', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Umber Rootfin Snapper', 263787, 1140087, 572664000, 3287091360, 'Hollow Grub', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'absolute', 'Bog Eel', 274257, 590200, 600912000, 1640489760, 'Mire Worm', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Peat Fencrest Barracuda', 273600, 849254, 578880000, 1580342400, 'Peat Midge', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Marsh Salmon', 296035, 1010664, 658476000, 2363928840, 'Marsh Fry', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Alder Driftline Swordfish', 318470, 1185984, 738072000, 3284420400, 'Silt Shrimp', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Mossback-Reedfin Coelacanth', 340906, 1375213, 817668000, 4341817080, 'Reed Nymph', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Driftwood Claycrest Leviathan', 363341, 1578352, 897264000, 2063707200, 'Bog Beetle', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Fen Hollowfin Guppy', 385776, 838677, 976860000, 3086877600, 'Fen Roe', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Ironroot Mudline Smelt', 408211, 1013997, 1056456000, 4246953120, 'Clay Larva', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Mire Shiner', 430646, 1203226, 1136052000, 5543933760, 'Moss Cricket', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Silt Tanglefin Perch', 453082, 1406365, 1215648000, 6977819520, 'Umber Fly', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Reed Marshwake Carp', 475517, 1623414, 1295244000, 3536016120, 'Drift Gnat', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Bramble Deepbog Pike', 497952, 1854373, 1374840000, 4935675600, 'Tangle Moth', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Hollow Rootfin Catfish', 520387, 2099242, 1454436000, 6472240200, 'Alder Worm', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Umber Bogrun Grouper', 542822, 2358021, 1534032000, 8145709920, 'Hollow Grub', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Bog Sturgeon', 565258, 1228870, 1613628000, 3711344400, 'Mire Worm', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'singularity', 'Rooted Mossgill Manta', 587693, 1459829, 1693224000, 5350587840, 'Root Grub', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Marsh Marlin', 587100, 2017276, 1632000000, 5157120000, 'Marsh Fry', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Alder Reedfin Shark', 635242, 2379617, 1856400000, 7462728000, 'Silt Shrimp', 'Most active near midnight stillness.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Mossback-Claycrest Tuna', 683384, 2771807, 2080800000, 10154304000, 'Reed Nymph', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Driftwood Hollowfin Minnow', 731527, 3193845, 2305200000, 13231848000, 'Bog Beetle', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Fen Mudline Loach', 779669, 1712153, 2529600000, 6905808000, 'Fen Roe', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Ironroot Stonegill Darter', 827811, 2074494, 2754000000, 9886860000, 'Clay Larva', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Mire Chub', 875953, 2466684, 2978400000, 13253880000, 'Moss Cricket', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Silt Marshwake Bream', 924095, 2888722, 3202800000, 17006868000, 'Umber Fly', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Reed Deepbog Trout', 972238, 3340608, 3427200000, 7882560000, 'Drift Gnat', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Bramble Rootfin Gar', 1020380, 3822343, 3651600000, 11539056000, 'Tangle Moth', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Hollow Bogrun Snapper', 1068522, 4333925, 3876000000, 15581520000, 'Alder Worm', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Umber Siltback Eel', 1116664, 4875356, 4100400000, 20009952000, 'Hollow Grub', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Bog Ray', 1164806, 2557915, 4324800000, 24824352000, 'Mire Worm', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Rooted Fencrest Arowana', 1212949, 3039649, 4549200000, 12419316000, 'Root Grub', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'paradox', 'Peat Miretail Mackerel', 1261091, 3551232, 4773600000, 17137224000, 'Peat Midge', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Alder Claycrest Coelacanth', 1258560, 4742254, 4608000000, 16542720000, 'Silt Shrimp', 'Responds to bottom-drift baits.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Mossback-Hollowfin Leviathan', 1361762, 5553265, 5241600000, 23325120000, 'Reed Nymph', 'Can vanish into root tangles quickly.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Driftwood Mudline Guppy', 1464964, 6428261, 5875200000, 31197312000, 'Bog Beetle', 'Rests in deep, cold sinkholes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Fen Stonegill Smelt', 1568166, 3478192, 6508800000, 14970240000, 'Fen Roe', 'Spawns in sheltered reed hollows.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Ironroot Tanglefin Shiner', 1671368, 4225217, 7142400000, 22569984000, 'Clay Larva', 'Avoids bright open surface lanes.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Mire Perch', 1774570, 5036229, 7776000000, 31259520000, 'Moss Cricket', 'Runs heavy and low when hooked.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Silt Deepbog Carp', 1877772, 5911225, 8409600000, 41038848000, 'Umber Fly', 'Leaves broad rings in still bog water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Reed Rootfin Pike', 1980973, 6850206, 9043200000, 51907968000, 'Drift Gnat', 'Prefers low-light, methane-rich pools.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Bramble Bogrun Catfish', 2084175, 7853173, 9676800000, 26417664000, 'Tangle Moth', 'Bites stronger in pressure drops.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Hollow Siltback Grouper', 2187377, 8920125, 10310400000, 37014336000, 'Alder Worm', 'Holds near old root caverns.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Umber Mossgill Sturgeon', 2290579, 10051062, 10944000000, 48700800000, 'Hollow Grub', 'Can push through dense peat sludge.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Bog Manta', 2393781, 5309407, 11577600000, 61477056000, 'Mire Worm', 'Tracks vibration through muddy water.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Rooted Miretail Barracuda', 2496983, 6312373, 12211200000, 28085760000, 'Root Grub', 'Feeds along slow silt terraces.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Peat Driftline Salmon', 2600185, 7379325, 12844800000, 40589568000, 'Peat Midge', 'Turns darker on overcast days.'),
  ('petrified_peat_bog', 'Petrified Peat-Bog', 'null', 'Marsh Reedfin Swordfish', 2703387, 8510262, 13478400000, 54183168000, 'Marsh Fry', 'Most active near midnight stillness.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Briar Minnow', 0.24, 0.66, 10.4, 37.34, 'Thorn Worm', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Thorned Briarcrest Loach', 0.26, 0.8, 11.83, 52.64, 'Rose Midge', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Rosewood Rosefin Darter', 0.28, 0.94, 13.26, 70.41, 'Briar Grub', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Bramble Brambleback Chub', 0.3, 1.1, 14.69, 33.79, 'Vine Nymph', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Ironbloom Vinegill Bream', 0.32, 1.28, 16.12, 50.94, 'Scarlet Fly', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Hedge Spurtail Trout', 0.34, 0.61, 17.55, 70.55, 'Hedge Shrimp', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Scarlet Gar', 0.36, 0.76, 18.98, 92.62, 'Petal Roe', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Blackthorn Petalguard Snapper', 0.38, 0.92, 20.41, 117, 'Spur Beetle', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Vinebound Crownthorn Eel', 0.4, 1.09, 21.84, 59.62, 'Stem Larva', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Petalguard Razorfin Ray', 0.42, 1.28, 23.27, 83.54, 'Crown Cricket', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Wildrose-Stemline Arowana', 0.44, 1.48, 24.7, 110, 'Night Moth', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Stemwood Bushcrest Mackerel', 0.46, 1.68, 26.13, 139, 'Hawthorn Gnat', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Nightbloom Marlin', 0.48, 1.91, 27.56, 63.39, 'Blackthorn Fry', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Hawthorn Guardfin Shark', 0.5, 0.9, 28.99, 91.61, 'Wildrose Worm', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'common', 'Crimsonleaf Thornwake Tuna', 0.52, 1.1, 30.42, 122, 'Crimson Bait', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Thorned Rosefin Smelt', 0.82, 2.52, 31.2, 125, 'Rose Midge', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Rosewood Brambleback Shiner', 0.89, 3, 35.49, 173, 'Briar Grub', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Bramble Vinegill Perch', 0.96, 3.53, 39.78, 228, 'Vine Nymph', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Ironbloom Spurtail Carp', 1.03, 4.09, 44.07, 120, 'Scarlet Fly', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Hedge Hedgefin Pike', 1.09, 1.99, 48.36, 174, 'Hedge Shrimp', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Scarlet Catfish', 1.16, 2.47, 52.65, 234, 'Petal Roe', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Blackthorn Crownthorn Grouper', 1.23, 3, 56.94, 302, 'Spur Beetle', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Vinebound Razorfin Sturgeon', 1.3, 3.56, 61.23, 141, 'Stem Larva', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Petalguard Stemline Manta', 1.36, 4.17, 65.52, 207, 'Crown Cricket', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Wildrose-Bushcrest Barracuda', 1.43, 4.82, 69.81, 281, 'Night Moth', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Stemwood Spiketail Salmon', 1.5, 5.51, 74.1, 362, 'Hawthorn Gnat', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Nightbloom Swordfish', 1.56, 6.25, 78.39, 450, 'Blackthorn Fry', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Hawthorn Thornwake Coelacanth', 1.63, 2.97, 82.68, 226, 'Wildrose Worm', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Crimsonleaf Thornfin Leviathan', 1.7, 3.62, 86.97, 312, 'Crimson Bait', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'uncommon', 'Briar Briarcrest Guppy', 1.77, 4.32, 91.26, 406, 'Thorn Worm', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Rosewood Vinegill Chub', 2.06, 6.98, 98.8, 440, 'Briar Grub', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Bramble Spurtail Bream', 2.23, 8.24, 112, 597, 'Vine Nymph', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Ironbloom Hedgefin Trout', 2.39, 9.61, 126, 290, 'Scarlet Fly', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Hedge Petalguard Gar', 2.56, 4.73, 140, 441, 'Hedge Shrimp', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Scarlet Snapper', 2.73, 5.88, 153, 616, 'Petal Roe', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Blackthorn Razorfin Eel', 2.9, 7.15, 167, 814, 'Spur Beetle', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Vinebound Stemline Ray', 3.07, 8.51, 180, 1035, 'Stem Larva', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Petalguard Bushcrest Arowana', 3.24, 9.99, 194, 529, 'Crown Cricket', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Wildrose-Spiketail Mackerel', 3.41, 11.56, 207, 745, 'Night Moth', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Stemwood Guardfin Marlin', 3.58, 13.24, 221, 984, 'Hawthorn Gnat', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Nightbloom Shark', 3.74, 15.03, 235, 1246, 'Blackthorn Fry', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Hawthorn Thornfin Tuna', 3.91, 7.21, 248, 571, 'Wildrose Worm', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Crimsonleaf Briarcrest Minnow', 4.08, 8.79, 262, 827, 'Crimson Bait', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Briar Rosefin Loach', 4.25, 10.47, 275, 1107, 'Thorn Worm', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'rare', 'Thorned Brambleback Darter', 4.42, 12.26, 289, 1410, 'Rose Midge', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Bramble Hedgefin Carp', 5.45, 20.29, 296, 1446, 'Vine Nymph', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Ironbloom Petalguard Pike', 5.89, 23.78, 337, 1935, 'Scarlet Fly', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Hedge Crownthorn Catfish', 6.34, 11.83, 378, 1032, 'Hedge Shrimp', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Scarlet Grouper', 6.78, 14.76, 419, 1503, 'Petal Roe', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Blackthorn Stemline Sturgeon', 7.23, 17.98, 459, 2044, 'Spur Beetle', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Vinebound Bushcrest Manta', 7.68, 21.47, 500, 2656, 'Stem Larva', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Petalguard Spiketail Barracuda', 8.12, 25.23, 541, 1244, 'Crown Cricket', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Wildrose-Guardfin Salmon', 8.57, 29.28, 582, 1838, 'Night Moth', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Stemwood Thornwake Swordfish', 9.02, 33.6, 622, 2502, 'Hawthorn Gnat', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Nightbloom Coelacanth', 9.46, 38.19, 663, 3236, 'Blackthorn Fry', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Hawthorn Briarcrest Leviathan', 9.91, 18.49, 704, 4041, 'Wildrose Worm', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Crimsonleaf Rosefin Guppy', 10.36, 22.54, 745, 2033, 'Crimson Bait', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Briar Brambleback Smelt', 10.8, 26.86, 785, 2820, 'Thorn Worm', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Thorned Vinegill Shiner', 11.25, 31.45, 826, 3677, 'Rose Midge', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'epic', 'Rosewood Spurtail Perch', 11.7, 36.33, 867, 4604, 'Briar Grub', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Ironbloom Crownthorn Gar', 14.28, 57.94, 884, 4694, 'Scarlet Fly', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Hedge Razorfin Snapper', 15.45, 29.17, 1006, 2313, 'Hedge Shrimp', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Scarlet Eel', 16.62, 36.53, 1127, 3562, 'Petal Roe', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Blackthorn Bushcrest Ray', 17.79, 44.62, 1249, 5020, 'Spur Beetle', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Vinebound Spiketail Arowana', 18.96, 53.43, 1370, 6687, 'Stem Larva', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Petalguard Guardfin Mackerel', 20.13, 62.97, 1492, 8563, 'Crown Cricket', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Wildrose-Thornwake Marlin', 21.3, 73.24, 1613, 4404, 'Night Moth', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Stemwood Thornfin Shark', 22.47, 84.23, 1735, 6228, 'Hawthorn Gnat', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Nightbloom Tuna', 23.64, 95.95, 1856, 8261, 'Blackthorn Fry', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Hawthorn Rosefin Minnow', 24.82, 46.85, 1978, 10503, 'Wildrose Worm', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Crimsonleaf Brambleback Loach', 25.99, 57.12, 2100, 4829, 'Crimson Bait', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Briar Vinegill Darter', 27.16, 68.11, 2221, 7019, 'Thorn Worm', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Thorned Spurtail Chub', 28.33, 79.83, 2343, 9417, 'Rose Midge', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Rosewood Hedgefin Bream', 29.5, 92.27, 2464, 12025, 'Briar Grub', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'legendary', 'Bramble Trout', 30.67, 105, 2586, 14842, 'Vine Nymph', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Hedge Stemline Grouper', 31.46, 60.09, 2496, 14327, 'Hedge Shrimp', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Scarlet Sturgeon', 34.04, 75.57, 2839, 7751, 'Petal Roe', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Blackthorn Spiketail Manta', 36.62, 92.65, 3182, 11425, 'Spur Beetle', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Vinebound Guardfin Barracuda', 39.2, 111, 3526, 15689, 'Stem Larva', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Petalguard Thornwake Salmon', 41.78, 132, 3869, 20543, 'Crown Cricket', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Wildrose-Thornfin Swordfish', 44.36, 153, 4212, 9688, 'Night Moth', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Stemwood Briarcrest Coelacanth', 46.94, 177, 4555, 14394, 'Hawthorn Gnat', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Nightbloom Leviathan', 49.52, 202, 4898, 19692, 'Blackthorn Fry', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Hawthorn Brambleback Guppy', 52.1, 99.51, 5242, 25579, 'Wildrose Worm', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Crimsonleaf Vinegill Smelt', 54.68, 121, 5585, 32057, 'Crimson Bait', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Briar Spurtail Shiner', 57.26, 145, 5928, 16183, 'Thorn Worm', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Thorned Hedgefin Perch', 59.84, 170, 6271, 22514, 'Rose Midge', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Rosewood Petalguard Carp', 62.42, 197, 6614, 29434, 'Briar Grub', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Bramble Pike', 65, 225, 6958, 36945, 'Vine Nymph', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'liminal', 'Ironbloom Razorfin Catfish', 67.58, 255, 7301, 16792, 'Scarlet Fly', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Scarlet Ray', 68.97, 155, 7072, 16266, 'Petal Roe', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Blackthorn Guardfin Arowana', 74.63, 190, 8044, 25420, 'Spur Beetle', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Vinebound Thornwake Mackerel', 80.28, 230, 9017, 36248, 'Stem Larva', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Petalguard Thornfin Marlin', 85.94, 273, 9989, 48747, 'Crown Cricket', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Wildrose-Briarcrest Shark', 91.59, 319, 10962, 62920, 'Night Moth', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Stemwood Rosefin Tuna', 97.25, 369, 11934, 32580, 'Hawthorn Gnat', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Nightbloom Minnow', 103, 422, 12906, 46334, 'Blackthorn Fry', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Hawthorn Vinegill Loach', 109, 210, 13879, 61761, 'Wildrose Worm', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Crimsonleaf Spurtail Darter', 114, 256, 14851, 78860, 'Crimson Bait', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Briar Hedgefin Chub', 120, 306, 15824, 36394, 'Thorn Worm', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Thorned Petalguard Bream', 126, 359, 16796, 53075, 'Rose Midge', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Rosewood Crownthorn Trout', 131, 416, 17768, 71429, 'Briar Grub', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Bramble Gar', 137, 476, 18741, 91455, 'Vine Nymph', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Ironbloom Stemline Snapper', 142, 540, 19713, 113154, 'Scarlet Fly', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'mythic', 'Hedge-Bushcrest Eel', 148, 608, 20686, 56472, 'Hedge Shrimp', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Blackthorn Thornwake Barracuda', 149, 383, 19968, 54513, 'Spur Beetle', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Vinebound Thornfin Salmon', 161, 464, 22714, 81542, 'Stem Larva', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Petalguard Briarcrest Swordfish', 173, 553, 25459, 113293, 'Crown Cricket', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Wildrose-Rosefin Coelacanth', 185, 650, 28205, 149767, 'Night Moth', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Stemwood Brambleback Leviathan', 198, 754, 30950, 71186, 'Hawthorn Gnat', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Nightbloom Guppy', 210, 865, 33696, 106479, 'Blackthorn Fry', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Hawthorn Spurtail Smelt', 222, 434, 36442, 146495, 'Wildrose Worm', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Crimsonleaf Hedgefin Shiner', 234, 530, 39187, 191234, 'Crimson Bait', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Briar Petalguard Perch', 246, 634, 41933, 240694, 'Thorn Worm', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Thorned Crownthorn Carp', 259, 746, 44678, 121972, 'Rose Midge', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Rosewood Razorfin Pike', 271, 865, 47424, 170252, 'Briar Grub', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Bramble Catfish', 283, 992, 50170, 223255, 'Vine Nymph', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Ironbloom Bushcrest Grouper', 295, 1126, 52915, 280980, 'Scarlet Fly', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Hedge-Spiketail Sturgeon', 307, 1268, 55661, 128020, 'Hedge Shrimp', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'ascendant', 'Scarlet Guardfin Manta', 320, 625, 58406, 184564, 'Petal Roe', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Vinebound Briarcrest Marlin', 317, 921, 56160, 177466, 'Stem Larva', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Petalguard Rosefin Shark', 343, 1103, 63882, 256806, 'Crown Cricket', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Wildrose-Brambleback Tuna', 369, 1301, 71604, 349428, 'Night Moth', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Stemwood Vinegill Minnow', 395, 1515, 79326, 455331, 'Hawthorn Gnat', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Nightbloom Loach', 421, 1745, 87048, 237641, 'Blackthorn Fry', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Hawthorn Hedgefin Darter', 447, 883, 94770, 340224, 'Wildrose Worm', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Crimsonleaf Petalguard Chub', 473, 1081, 102492, 456089, 'Crimson Bait', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Briar Crownthorn Bream', 499, 1295, 110214, 585236, 'Thorn Worm', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Thorned Razorfin Trout', 525, 1526, 117936, 271253, 'Rose Midge', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Rosewood Stemline Gar', 551, 1772, 125658, 397079, 'Briar Grub', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Bramble Snapper', 577, 2034, 133380, 536188, 'Vine Nymph', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Ironbloom Spiketail Eel', 603, 2313, 141102, 688578, 'Scarlet Fly', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Hedge-Guardfin Ray', 629, 2608, 148824, 854250, 'Hedge Shrimp', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Scarlet Thornwake Arowana', 655, 1294, 156546, 427371, 'Petal Roe', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'celestial', 'Blackthorn Thornfin Mackerel', 681, 1557, 164268, 589722, 'Spur Beetle', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Petalguard Brambleback Coelacanth', 672, 2174, 159120, 571241, 'Crown Cricket', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Wildrose-Vinegill Leviathan', 727, 2578, 180999, 805446, 'Night Moth', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Stemwood Spurtail Guppy', 782, 3016, 202878, 1077282, 'Hawthorn Gnat', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Nightbloom Smelt', 837, 3488, 224757, 516941, 'Blackthorn Fry', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Hawthorn Petalguard Shiner', 892, 1782, 246636, 779370, 'Wildrose Worm', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Crimsonleaf Crownthorn Perch', 947, 2185, 268515, 1079430, 'Crimson Bait', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Briar Razorfin Carp', 1002, 2623, 290394, 1417123, 'Thorn Worm', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Thorned Stemline Pike', 1057, 3095, 312273, 1792447, 'Rose Midge', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Rosewood Bushcrest Catfish', 1112, 3601, 334152, 912235, 'Briar Grub', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Bramble Grouper', 1167, 4141, 356031, 1278151, 'Vine Nymph', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Ironbloom Guardfin Sturgeon', 1222, 4715, 377910, 1681699, 'Scarlet Fly', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Hedge-Thornwake Manta', 1277, 5324, 399789, 2122880, 'Hedge Shrimp', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Scarlet Thornfin Barracuda', 1332, 2662, 421668, 969836, 'Petal Roe', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Blackthorn Briarcrest Salmon', 1387, 3202, 443547, 1401609, 'Spur Beetle', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eldritch', 'Vinebound Rosefin Swordfish', 1442, 3776, 465426, 1871013, 'Stem Larva', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Wildrose-Spurtail Minnow', 1428, 5097, 447200, 1797744, 'Night Moth', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Stemwood Hedgefin Loach', 1545, 5994, 508690, 2482407, 'Hawthorn Gnat', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Nightbloom Darter', 1662, 6964, 570180, 3272833, 'Blackthorn Fry', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Hawthorn Crownthorn Chub', 1779, 3594, 631670, 1724459, 'Wildrose Worm', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Crimsonleaf Razorfin Bream', 1896, 4418, 693160, 2488444, 'Crimson Bait', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Briar Stemline Trout', 2013, 5315, 754650, 3358192, 'Thorn Worm', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Thorned Bushcrest Gar', 2130, 6284, 816140, 4333703, 'Rose Midge', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Rosewood Spiketail Snapper', 2247, 7326, 877630, 2018549, 'Briar Grub', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Bramble Eel', 2364, 8441, 939120, 2967619, 'Vine Nymph', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Ironbloom Thornwake Ray', 2482, 9628, 1000610, 4022452, 'Scarlet Fly', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Hedge-Thornfin Arowana', 2599, 10888, 1062100, 5183048, 'Hedge Shrimp', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Scarlet Briarcrest Mackerel', 2716, 5486, 1123590, 6449407, 'Petal Roe', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Blackthorn Rosefin Marlin', 2833, 6600, 1185080, 3235268, 'Spur Beetle', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Vinebound Brambleback Shark', 2950, 7788, 1246570, 4475186, 'Stem Larva', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'eternal', 'Petalguard Tuna', 3067, 9047, 1308060, 5820867, 'Crown Cricket', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Stemwood Petalguard Smelt', 3037, 11851, 1258400, 5599880, 'Hawthorn Gnat', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Nightbloom Shiner', 3286, 13841, 1431430, 7600893, 'Blackthorn Fry', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Hawthorn Razorfin Perch', 3535, 7219, 1604460, 3690258, 'Wildrose Worm', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Crimsonleaf Stemline Carp', 3784, 8901, 1777490, 5616868, 'Crimson Bait', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Briar Bushcrest Pike', 4033, 10737, 1950520, 7841090, 'Thorn Worm', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Thorned Spiketail Catfish', 4282, 12727, 2123550, 10362924, 'Rose Midge', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Rosewood Guardfin Grouper', 4531, 14872, 2296580, 13182369, 'Briar Grub', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Bramble Sturgeon', 4780, 17171, 2469610, 6742035, 'Vine Nymph', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Ironbloom Thornfin Manta', 5029, 19625, 2642640, 9487078, 'Scarlet Fly', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Hedge-Briarcrest Barracuda', 5278, 22233, 2815670, 12529731, 'Hedge Shrimp', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Scarlet Rosefin Salmon', 5528, 11287, 2988700, 15869997, 'Petal Roe', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Blackthorn Brambleback Swordfish', 5777, 13586, 3161730, 7271979, 'Spur Beetle', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Vinebound Vinegill Coelacanth', 6026, 16040, 3334760, 10537842, 'Stem Larva', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Petalguard Leviathan', 6275, 18648, 3507790, 14101316, 'Crown Cricket', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'divine', 'Wildrose Hedgefin Guppy', 6524, 21411, 3680820, 17962402, 'Night Moth', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Nightbloom Chub', 6474, 27409, 3546400, 17306432, 'Blackthorn Fry', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Hawthorn Stemline Bream', 7004, 14457, 4034030, 23155332, 'Wildrose Worm', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Crimsonleaf Bushcrest Trout', 7535, 17888, 4521660, 12344132, 'Crimson Bait', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Briar Spiketail Gar', 8066, 21649, 5009290, 17983351, 'Thorn Worm', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Thorned Guardfin Snapper', 8597, 25739, 5496920, 24461294, 'Rose Midge', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Rosewood Thornwake Eel', 9128, 30158, 5984550, 31777960, 'Briar Grub', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Bramble Ray', 9658, 34906, 6472180, 14886014, 'Vine Nymph', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Ironbloom Briarcrest Arowana', 10189, 39983, 6959810, 21993000, 'Scarlet Fly', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Hedge-Rosefin Mackerel', 10720, 45389, 7447440, 29938709, 'Hedge Shrimp', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Scarlet Brambleback Marlin', 11251, 23222, 7935070, 38723142, 'Petal Roe', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Blackthorn Vinegill Shark', 11782, 27970, 8422700, 48346298, 'Spur Beetle', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Vinebound Spurtail Tuna', 12313, 33047, 8910330, 24325201, 'Stem Larva', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Petalguard Minnow', 12843, 38453, 9397960, 33738676, 'Crown Cricket', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Wildrose Petalguard Loach', 13374, 44189, 9885590, 43990875, 'Night Moth', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'cosmic', 'Stemwood Crownthorn Darter', 13905, 50253, 10373220, 55081798, 'Hawthorn Gnat', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Hawthorn Bushcrest Carp', 13794, 28774, 9994400, 53070264, 'Wildrose Worm', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Crimsonleaf Spiketail Pike', 14925, 35761, 11368630, 26147849, 'Crimson Bait', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Briar Guardfin Catfish', 16056, 43448, 12742860, 40267438, 'Thorn Worm', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Thorned Thornwake Grouper', 17187, 51837, 14117090, 56750702, 'Rose Midge', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Rosewood Thornfin Sturgeon', 18318, 60927, 15491320, 75597642, 'Briar Grub', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Bramble Manta', 19450, 70719, 16865550, 96808257, 'Vine Nymph', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Ironbloom Rosefin Barracuda', 20581, 81211, 18239780, 49794599, 'Scarlet Fly', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Hedge-Brambleback Salmon', 21712, 92405, 19614010, 70414296, 'Hedge Shrimp', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Scarlet Vinegill Swordfish', 22843, 47650, 20988240, 93397668, 'Petal Roe', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Blackthorn Spurtail Coelacanth', 23974, 57442, 22362470, 118744716, 'Spur Beetle', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Vinebound Hedgefin Leviathan', 25105, 67934, 23736700, 54594410, 'Stem Larva', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Petalguard Guppy', 26236, 79128, 25110930, 79350539, 'Crown Cricket', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Wildrose Crownthorn Smelt', 27367, 91024, 26485160, 106470343, 'Night Moth', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Stemwood Razorfin Shiner', 28498, 103620, 27859390, 135953823, 'Hawthorn Gnat', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'primordial', 'Nightbloom Stemline Perch', 29630, 116918, 29233620, 167800979, 'Blackthorn Fry', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Crimsonleaf Guardfin Gar', 29524, 71389, 28080000, 161179200, 'Crimson Bait', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Briar Thornwake Snapper', 31945, 87146, 31941000, 87198930, 'Thorn Worm', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Thorned Thornfin Eel', 34366, 104404, 35802000, 128529180, 'Rose Midge', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Rosewood Briarcrest Ray', 36787, 123163, 39663000, 176500350, 'Briar Grub', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Bramble Arowana', 39208, 143422, 43524000, 231112440, 'Vine Nymph', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Ironbloom Brambleback Mackerel', 41629, 165183, 47385000, 108985500, 'Scarlet Fly', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Hedge-Vinegill Marlin', 44050, 188445, 51246000, 161937360, 'Hedge Shrimp', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Scarlet Spurtail Shark', 46471, 97960, 55107000, 221530140, 'Petal Roe', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Blackthorn Hedgefin Tuna', 48892, 118220, 58968000, 287763840, 'Spur Beetle', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Vinebound Petalguard Minnow', 51313, 139981, 62829000, 360638460, 'Stem Larva', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Petalguard Loach', 53734, 163243, 66690000, 182063700, 'Crown Cricket', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Wildrose Razorfin Darter', 56155, 188006, 70551000, 253278090, 'Night Moth', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Stemwood Stemline Chub', 58576, 214270, 74412000, 331133400, 'Hawthorn Gnat', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Nightbloom Bushcrest Bream', 60997, 242034, 78273000, 415629630, 'Blackthorn Fry', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'transcendent', 'Hawthorn Spiketail Trout', 63418, 271300, 82134000, 188908200, 'Wildrose Worm', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Briar Thornfin Grouper', 63162, 173696, 79040000, 181792000, 'Thorn Worm', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Thorned Briarcrest Sturgeon', 68341, 209124, 89908000, 284109280, 'Rose Midge', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Rosewood Rosefin Manta', 73521, 247764, 100776000, 405119520, 'Briar Grub', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Bramble Barracuda', 78700, 289615, 111644000, 544822720, 'Vine Nymph', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Ironbloom Vinegill Salmon', 83879, 334678, 122512000, 703218880, 'Scarlet Fly', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Hedge-Spurtail Swordfish', 89058, 382951, 133380000, 364127400, 'Hedge Shrimp', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Scarlet Hedgefin Coelacanth', 94238, 200726, 144248000, 517850320, 'Petal Roe', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Blackthorn Petalguard Leviathan', 99417, 242577, 155116000, 690266200, 'Spur Beetle', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Vinebound Crownthorn Guppy', 104596, 287640, 165984000, 881375040, 'Stem Larva', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Petalguard Smelt', 109776, 335913, 176852000, 406759600, 'Crown Cricket', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Wildrose Stemline Shiner', 114955, 387398, 187720000, 593195200, 'Night Moth', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Stemwood Bushcrest Perch', 120134, 442094, 198588000, 798323760, 'Hawthorn Gnat', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Nightbloom Spiketail Carp', 125313, 500000, 209456000, 1022145280, 'Blackthorn Fry', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Hawthorn Guardfin Pike', 130493, 561119, 220324000, 1264659760, 'Wildrose Worm', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'apotheosis', 'Crimsonleaf Thornwake Catfish', 135672, 288981, 231192000, 631154160, 'Crimson Bait', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Thorned Rosefin Ray', 135520, 417673, 222560000, 607588800, 'Rose Midge', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Rosewood Brambleback Arowana', 146633, 497378, 253162000, 908851580, 'Briar Grub', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Bramble Mackerel', 157745, 583973, 283764000, 1262749800, 'Vine Nymph', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Ironbloom Spurtail Marlin', 168858, 677458, 314366000, 1669283460, 'Scarlet Fly', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Hedge-Hedgefin Shark', 179971, 777833, 344968000, 793426400, 'Hedge Shrimp', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Scarlet Petalguard Tuna', 191083, 411211, 375570000, 1186801200, 'Petal Roe', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Blackthorn Crownthorn Minnow', 202196, 497806, 406172000, 1632811440, 'Spur Beetle', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Vinebound Razorfin Loach', 213308, 591291, 436774000, 2131457120, 'Stem Larva', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Petalguard Darter', 224421, 691666, 467376000, 2682738240, 'Crown Cricket', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Wildrose Bushcrest Chub', 235534, 798931, 497978000, 1359479940, 'Night Moth', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Stemwood Spiketail Bream', 246646, 913085, 528580000, 1897602200, 'Hawthorn Gnat', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Nightbloom Guardfin Trout', 257759, 1034129, 559182000, 2488359900, 'Blackthorn Fry', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Hawthorn Thornwake Gar', 268872, 1162063, 589784000, 3131753040, 'Wildrose Worm', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Crimsonleaf Thornfin Snapper', 279984, 602526, 620386000, 1426887800, 'Crimson Bait', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'absolute', 'Briar Eel', 291097, 716681, 650988000, 2057122080, 'Thorn Worm', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Rosewood Vinegill Barracuda', 290400, 991426, 627120000, 1981699200, 'Briar Grub', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Bramble Salmon', 314213, 1170128, 713349000, 2867662980, 'Vine Nymph', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Ironbloom Hedgefin Swordfish', 338026, 1363595, 799578000, 3901940640, 'Scarlet Fly', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Hedge-Petalguard Coelacanth', 361838, 1571826, 885807000, 5084532180, 'Hedge Shrimp', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Scarlet Crownthorn Leviathan', 385651, 838406, 972036000, 2653658280, 'Petal Roe', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Blackthorn Razorfin Guppy', 409464, 1017109, 1058265000, 3799171350, 'Spur Beetle', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Vinebound Stemline Smelt', 433277, 1210575, 1144494000, 5092998300, 'Stem Larva', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Petalguard Shiner', 457090, 1418806, 1230723000, 6535139130, 'Crown Cricket', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Wildrose Spiketail Perch', 480902, 1641801, 1316952000, 3028989600, 'Night Moth', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Stemwood Guardfin Carp', 504715, 1879559, 1403181000, 4434051960, 'Hawthorn Gnat', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Nightbloom Thornwake Pike', 528528, 2132082, 1489410000, 5987428200, 'Blackthorn Fry', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Hawthorn Thornfin Catfish', 552341, 2399368, 1575639000, 7689118320, 'Wildrose Worm', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Crimsonleaf Briarcrest Grouper', 576154, 1252558, 1661868000, 9539122320, 'Crimson Bait', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Briar Sturgeon', 599966, 1490317, 1748097000, 4772304810, 'Thorn Worm', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'singularity', 'Thorned Brambleback Manta', 623779, 1742839, 1834326000, 6585230340, 'Rose Midge', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Bramble Marlin', 623150, 2334320, 1768000000, 6347120000, 'Vine Nymph', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Ironbloom Petalguard Shark', 674248, 2734751, 2011100000, 8949395000, 'Scarlet Fly', 'Rests beneath thorn arch overhangs.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Hedge-Crownthorn Tuna', 725347, 3166863, 2254200000, 11969802000, 'Hedge Shrimp', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Scarlet Razorfin Minnow', 776445, 1705073, 2497300000, 5743790000, 'Petal Roe', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Blackthorn Stemline Loach', 827543, 2073823, 2740400000, 8659664000, 'Spur Beetle', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Vinebound Bushcrest Darter', 878642, 2474254, 2983500000, 11993670000, 'Stem Larva', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Petalguard Chub', 929740, 2906367, 3226600000, 15745808000, 'Crown Cricket', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Wildrose Guardfin Bream', 980838, 3370160, 3469700000, 19916078000, 'Night Moth', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Stemwood Thornwake Trout', 1031936, 3865634, 3712800000, 10135944000, 'Hawthorn Gnat', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Nightbloom Thornfin Gar', 1083035, 4392789, 3955900000, 14201681000, 'Blackthorn Fry', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Hawthorn Briarcrest Snapper', 1134133, 4951625, 4199000000, 18685550000, 'Wildrose Worm', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Crimsonleaf Rosefin Eel', 1185231, 2602768, 4442100000, 23587551000, 'Crimson Bait', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Briar Ray', 1236330, 3098242, 4685200000, 10775960000, 'Thorn Worm', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Thorned Vinegill Arowana', 1287428, 3625397, 4928300000, 15573428000, 'Rose Midge', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'paradox', 'Rosewood Spurtail Mackerel', 1338526, 4184233, 5171400000, 20789028000, 'Briar Grub', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Ironbloom Crownthorn Coelacanth', 1335840, 5447556, 4992000000, 20067840000, 'Scarlet Fly', 'Most active after warm rainfall.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Hedge-Razorfin Leviathan', 1445379, 6342323, 5678400000, 27710592000, 'Hedge Shrimp', 'Responds to precise, short casts.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Scarlet Stemline Guppy', 1554918, 3448808, 6364800000, 36533952000, 'Petal Roe', 'Often runs straight into bramble lanes.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Blackthorn Bushcrest Smelt', 1664457, 4207746, 7051200000, 19249776000, 'Spur Beetle', 'Shows deep red hues at sunset.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Vinebound Spiketail Shiner', 1773996, 5034599, 7737600000, 27777984000, 'Stem Larva', 'Spawns in protected vine nests.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Petalguard Perch', 1883534, 5929366, 8424000000, 37486800000, 'Crown Cricket', 'Can break weak leaders on sudden pulls.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Wildrose Thornwake Carp', 1993073, 6892047, 9110400000, 48376224000, 'Night Moth', 'Leaves thin wakes between thorn shadows.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Stemwood Thornfin Pike', 2102612, 7922643, 9796800000, 22532640000, 'Hawthorn Gnat', 'Navigates razor-thorn corridors with ease.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Nightbloom Briarcrest Catfish', 2212151, 9021152, 10483200000, 33126912000, 'Blackthorn Fry', 'Bites hard near sheltered rose pockets.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Hawthorn Rosefin Grouper', 2321690, 10187575, 11169600000, 44901792000, 'Wildrose Worm', 'Scales resist minor line abrasion.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Crimsonleaf Brambleback Sturgeon', 2431229, 5392465, 11856000000, 57857280000, 'Crimson Bait', 'Prefers narrow channels over open water.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Briar Manta', 2540768, 6423061, 12542400000, 71993376000, 'Thorn Worm', 'Can pivot sharply in tight spaces.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Thorned Spurtail Barracuda', 2650307, 7521570, 13228800000, 36114624000, 'Rose Midge', 'Feeds during dusk when petals close.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Rosewood Hedgefin Salmon', 2759845, 8687993, 13915200000, 49955568000, 'Briar Grub', 'Tracks prey through stem vibration.'),
  ('thorn_thicket_trench', 'Thorn-Thicket Trench', 'null', 'Bramble Petalguard Swordfish', 2869384, 9922331, 14601600000, 64977120000, 'Vine Nymph', 'Rests beneath thorn arch overhangs.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Bubble Minnow', 0.26, 0.78, 11.2, 45.02, 'Soap Worm', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Foam Bubbletail Loach', 0.28, 0.93, 12.74, 62.17, 'Foam Midge', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Ceramic Sudswave Darter', 0.3, 1.09, 14.28, 81.97, 'Bubble Grub', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Soapstone Basinrun Chub', 0.32, 1.27, 15.82, 43.19, 'Rinse Fly', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Tiled Tilerun Bream', 0.34, 0.61, 17.36, 62.32, 'Tile Shrimp', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Bathwater Lathergill Trout', 0.36, 0.76, 18.9, 84.1, 'Bath Nymph', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Dawnrinse Gar', 0.38, 0.92, 20.44, 109, 'Lather Roe', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Sudsy Tubcrest Snapper', 0.4, 1.1, 21.98, 50.55, 'Tub Beetle', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Porcelain Splashline Eel', 0.42, 1.29, 23.52, 74.32, 'Splash Larva', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Driftsoap Driftfoam Ray', 0.44, 1.49, 25.06, 101, 'Mist Cricket', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Lather-Washback Arowana', 0.47, 1.71, 26.6, 130, 'Fresh Fry', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Briskwash Mistfin Mackerel', 0.49, 1.93, 28.14, 162, 'Ceramic Gnat', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Clearmist Marlin', 0.51, 0.91, 29.68, 81.03, 'Dawn Moth', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Rippletile Soapwake Shark', 0.53, 1.12, 31.22, 112, 'Cleanwater Worm', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'common', 'Freshwater Clearrun Tuna', 0.55, 1.33, 32.76, 146, 'Suds Pellet', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Foam Sudswave Smelt', 0.87, 2.93, 33.6, 150, 'Foam Midge', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Ceramic Basinrun Shiner', 0.94, 3.47, 38.22, 203, 'Bubble Grub', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Soapstone Tilerun Perch', 1.01, 4.04, 42.84, 98.53, 'Rinse Fly', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Tiled Lathergill Carp', 1.08, 1.98, 47.46, 150, 'Tile Shrimp', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Bathwater Rinsefin Pike', 1.16, 2.46, 52.08, 209, 'Bath Nymph', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Dawnrinse Catfish', 1.23, 3, 56.7, 277, 'Lather Roe', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Sudsy Splashline Grouper', 1.3, 3.57, 61.32, 352, 'Tub Beetle', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Porcelain Driftfoam Sturgeon', 1.37, 4.19, 65.94, 180, 'Splash Larva', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Driftsoap Washback Manta', 1.44, 4.86, 70.56, 253, 'Mist Cricket', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Lather-Mistfin Barracuda', 1.51, 5.57, 75.18, 335, 'Fresh Fry', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Briskwash Softswell Salmon', 1.58, 6.32, 79.8, 424, 'Ceramic Gnat', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Clearmist Swordfish', 1.66, 3.02, 84.42, 194, 'Dawn Moth', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Rippletile Clearrun Coelacanth', 1.73, 3.68, 89.04, 281, 'Cleanwater Worm', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Freshwater Foamfin Leviathan', 1.8, 4.39, 93.66, 377, 'Suds Pellet', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'uncommon', 'Bubble Bubbletail Guppy', 1.87, 5.15, 98.28, 480, 'Soap Worm', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Ceramic Tilerun Chub', 2.18, 8.06, 106, 519, 'Bubble Grub', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Soapstone Lathergill Bream', 2.35, 9.45, 121, 695, 'Rinse Fly', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Tiled Rinsefin Trout', 2.53, 4.67, 136, 370, 'Tile Shrimp', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Bathwater Tubcrest Gar', 2.71, 5.84, 150, 540, 'Bath Nymph', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Dawnrinse Snapper', 2.89, 7.12, 165, 734, 'Lather Roe', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Sudsy Driftfoam Eel', 3.07, 8.51, 180, 953, 'Tub Beetle', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Porcelain Washback Ray', 3.25, 10.01, 194, 447, 'Splash Larva', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Driftsoap Mistfin Arowana', 3.43, 11.62, 209, 660, 'Mist Cricket', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Lather-Softswell Mackerel', 3.6, 13.35, 223, 898, 'Fresh Fry', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Briskwash Soapwake Marlin', 3.78, 15.18, 238, 1162, 'Ceramic Gnat', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Clearmist Shark', 3.96, 7.3, 253, 1450, 'Dawn Moth', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Rippletile Foamfin Tuna', 4.14, 8.91, 267, 730, 'Cleanwater Worm', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Freshwater Bubbletail Minnow', 4.32, 10.64, 282, 1012, 'Suds Pellet', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Bubble Sudswave Loach', 4.5, 12.47, 297, 1320, 'Soap Worm', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'rare', 'Foam Basinrun Darter', 4.67, 14.41, 311, 1653, 'Foam Midge', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Soapstone Rinsefin Carp', 5.76, 23.25, 319, 1695, 'Rinse Fly', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Tiled Tubcrest Pike', 6.23, 11.63, 363, 835, 'Tile Shrimp', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Bathwater Splashline Catfish', 6.7, 14.59, 407, 1286, 'Bath Nymph', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Dawnrinse Grouper', 7.18, 17.84, 451, 1812, 'Lather Roe', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Sudsy Washback Sturgeon', 7.65, 21.39, 495, 2414, 'Tub Beetle', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Porcelain Mistfin Manta', 8.12, 25.23, 539, 3092, 'Splash Larva', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Driftsoap Softswell Barracuda', 8.59, 29.36, 583, 1590, 'Mist Cricket', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Lather-Soapwake Salmon', 9.07, 33.78, 626, 2249, 'Fresh Fry', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Briskwash Clearrun Swordfish', 9.54, 38.5, 670, 2983, 'Ceramic Gnat', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Clearmist Coelacanth', 10.01, 18.68, 714, 3792, 'Dawn Moth', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Rippletile Bubbletail Leviathan', 10.48, 22.81, 758, 1744, 'Cleanwater Worm', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Freshwater Sudswave Guppy', 10.96, 27.24, 802, 2534, 'Suds Pellet', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Bubble Basinrun Smelt', 11.43, 31.95, 846, 3400, 'Soap Worm', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Foam Tilerun Shiner', 11.9, 36.96, 890, 4342, 'Foam Midge', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'epic', 'Ceramic Lathergill Perch', 12.37, 42.26, 934, 5359, 'Bubble Grub', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Tiled Splashline Gar', 15.1, 28.52, 952, 5464, 'Tile Shrimp', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Bathwater Driftfoam Snapper', 16.34, 35.92, 1083, 2956, 'Bath Nymph', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Dawnrinse Eel', 17.58, 44.09, 1214, 4358, 'Lather Roe', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Sudsy Mistfin Ray', 18.82, 53.03, 1345, 5984, 'Tub Beetle', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Porcelain Softswell Arowana', 20.06, 62.74, 1476, 7835, 'Splash Larva', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Driftsoap Soapwake Mackerel', 21.3, 73.22, 1607, 3695, 'Mist Cricket', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Lather-Clearrun Marlin', 22.54, 84.46, 1737, 5490, 'Fresh Fry', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Briskwash Foamfin Shark', 23.77, 96.47, 1868, 7511, 'Ceramic Gnat', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Clearmist Tuna', 25.01, 47.22, 1999, 9756, 'Dawn Moth', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Rippletile Sudswave Minnow', 26.25, 57.7, 2130, 12227, 'Cleanwater Worm', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Freshwater Basinrun Loach', 27.49, 68.94, 2261, 6173, 'Suds Pellet', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Bubble Tilerun Darter', 28.73, 80.95, 2392, 8587, 'Soap Worm', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Foam Lathergill Chub', 29.97, 93.73, 2523, 11226, 'Foam Midge', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Ceramic Rinsefin Bream', 31.2, 107, 2654, 14091, 'Bubble Grub', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'legendary', 'Soapstone Trout', 32.44, 122, 2785, 6405, 'Rinse Fly', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Bathwater Washback Grouper', 33.28, 73.88, 2688, 6182, 'Bath Nymph', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Dawnrinse Sturgeon', 36.01, 91.1, 3058, 9662, 'Lather Roe', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Sudsy Softswell Manta', 38.74, 110, 3427, 13777, 'Tub Beetle', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Porcelain Soapwake Barracuda', 41.47, 131, 3797, 18528, 'Splash Larva', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Driftsoap Clearrun Salmon', 44.2, 153, 4166, 23915, 'Mist Cricket', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Lather-Foamfin Swordfish', 46.92, 177, 4536, 12383, 'Fresh Fry', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Briskwash Bubbletail Coelacanth', 49.65, 203, 4906, 17611, 'Ceramic Gnat', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Clearmist Leviathan', 52.38, 100, 5275, 23475, 'Dawn Moth', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Rippletile Basinrun Guppy', 55.11, 122, 5645, 29974, 'Cleanwater Worm', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Freshwater Tilerun Smelt', 57.84, 146, 6014, 13833, 'Suds Pellet', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Bubble Lathergill Shiner', 60.57, 172, 6384, 20173, 'Soap Worm', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Foam Rinsefin Perch', 63.3, 199, 6754, 27149, 'Foam Midge', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Ceramic Tubcrest Carp', 66.03, 228, 7123, 34761, 'Bubble Grub', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Soapstone Pike', 68.76, 259, 7493, 43009, 'Rinse Fly', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'liminal', 'Tiled Driftfoam Catfish', 71.49, 292, 7862, 21464, 'Tile Shrimp', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Dawnrinse Ray', 72.96, 186, 7616, 20792, 'Lather Roe', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Sudsy Soapwake Arowana', 78.94, 226, 8663, 31101, 'Tub Beetle', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Porcelain Clearrun Mackerel', 84.93, 269, 9710, 43211, 'Splash Larva', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Driftsoap Foamfin Marlin', 90.91, 317, 10758, 57123, 'Mist Cricket', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Lather-Bubbletail Shark', 96.89, 367, 11805, 27151, 'Fresh Fry', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Briskwash Sudswave Tuna', 103, 422, 12852, 40612, 'Ceramic Gnat', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Clearmist Minnow', 109, 210, 13899, 55875, 'Dawn Moth', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Rippletile Tilerun Loach', 115, 257, 14946, 72938, 'Cleanwater Worm', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Freshwater Lathergill Darter', 121, 308, 15994, 91803, 'Suds Pellet', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Bubble Rinsefin Chub', 127, 363, 17041, 46521, 'Soap Worm', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Foam Tubcrest Bream', 133, 421, 18088, 64936, 'Foam Midge', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Ceramic Splashline Trout', 139, 483, 19135, 85152, 'Bubble Grub', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Soapstone Gar', 145, 549, 20182, 107169, 'Rinse Fly', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Tiled Washback Snapper', 151, 618, 21230, 48828, 'Tile Shrimp', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'mythic', 'Bathwater-Mistfin Eel', 157, 303, 22277, 70395, 'Bath Nymph', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Sudsy Clearrun Barracuda', 157, 454, 21504, 67953, 'Tub Beetle', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Porcelain Foamfin Salmon', 170, 544, 24461, 98332, 'Splash Larva', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Driftsoap Bubbletail Swordfish', 183, 642, 27418, 133798, 'Mist Cricket', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Lather-Sudswave Coelacanth', 196, 748, 30374, 174349, 'Fresh Fry', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Briskwash Basinrun Leviathan', 209, 862, 33331, 90994, 'Ceramic Gnat', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Clearmist Guppy', 222, 434, 36288, 130274, 'Dawn Moth', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Rippletile Lathergill Smelt', 235, 532, 39245, 174639, 'Cleanwater Worm', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Freshwater Rinsefin Shiner', 248, 638, 42202, 224090, 'Suds Pellet', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Bubble Tubcrest Perch', 261, 752, 45158, 103864, 'Soap Worm', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Foam Splashline Carp', 274, 874, 48115, 152044, 'Foam Midge', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Ceramic Driftfoam Pike', 287, 1004, 51072, 205309, 'Bubble Grub', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Soapstone Catfish', 299, 1142, 54029, 263661, 'Rinse Fly', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Tiled Mistfin Grouper', 312, 1288, 56986, 327097, 'Tile Shrimp', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Bathwater-Softswell Sturgeon', 325, 636, 59942, 163643, 'Bath Nymph', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'ascendant', 'Dawnrinse Soapwake Manta', 338, 766, 62899, 225808, 'Lather Roe', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Porcelain Bubbletail Marlin', 335, 1079, 60480, 217123, 'Splash Larva', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Driftsoap Sudswave Shark', 363, 1279, 68796, 306142, 'Mist Cricket', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Lather-Basinrun Tuna', 390, 1497, 77112, 409465, 'Fresh Fry', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Briskwash Tilerun Minnow', 418, 1732, 85428, 196484, 'Ceramic Gnat', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Clearmist Loach', 445, 880, 93744, 296231, 'Dawn Moth', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Rippletile Rinsefin Darter', 473, 1081, 102060, 410281, 'Cleanwater Worm', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Freshwater Tubcrest Chub', 500, 1299, 110376, 538635, 'Suds Pellet', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Bubble Splashline Bream', 528, 1534, 118692, 681292, 'Soap Worm', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Foam Driftfoam Trout', 555, 1786, 127008, 346732, 'Foam Midge', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Ceramic Washback Gar', 583, 2055, 135324, 485813, 'Bubble Grub', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Soapstone Snapper', 610, 2341, 143640, 639198, 'Rinse Fly', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Tiled Softswell Eel', 638, 2645, 151956, 806886, 'Tile Shrimp', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Bathwater-Soapwake Ray', 665, 1315, 160272, 368626, 'Bath Nymph', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Dawnrinse Clearrun Arowana', 693, 1584, 168588, 532738, 'Lather Roe', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'celestial', 'Sudsy Foamfin Mackerel', 720, 1870, 176904, 711154, 'Tub Beetle', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Driftsoap Basinrun Coelacanth', 710, 2520, 171360, 688867, 'Mist Cricket', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Lather-Tilerun Leviathan', 769, 2965, 194922, 951219, 'Fresh Fry', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Briskwash Lathergill Guppy', 827, 3447, 218484, 1254098, 'Ceramic Gnat', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Clearmist Smelt', 885, 1769, 242046, 660786, 'Dawn Moth', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Rippletile Tubcrest Shiner', 943, 2177, 265608, 953533, 'Cleanwater Worm', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Freshwater Splashline Perch', 1002, 2622, 289170, 1286806, 'Suds Pellet', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Bubble Driftfoam Carp', 1060, 3103, 312732, 1660607, 'Soap Worm', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Foam Washback Pike', 1118, 3621, 336294, 773476, 'Foam Midge', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Ceramic Mistfin Catfish', 1176, 4174, 359856, 1137145, 'Bubble Grub', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Soapstone Grouper', 1235, 4763, 383418, 1541340, 'Rinse Fly', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Tiled Soapwake Sturgeon', 1293, 5389, 406980, 1986062, 'Tile Shrimp', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Bathwater-Clearrun Manta', 1351, 2700, 430542, 2471311, 'Bath Nymph', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Dawnrinse Foamfin Barracuda', 1409, 3253, 454104, 1239704, 'Lather Roe', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Sudsy Bubbletail Salmon', 1468, 3842, 477666, 1714821, 'Tub Beetle', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'eldritch', 'Porcelain Sudswave Swordfish', 1526, 4468, 501228, 2230465, 'Splash Larva', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Lather-Lathergill Minnow', 1510, 5860, 481600, 2143120, 'Fresh Fry', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Briskwash Rinsefin Loach', 1634, 6848, 547820, 2908924, 'Ceramic Gnat', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Clearmist Darter', 1758, 3551, 614040, 1412292, 'Dawn Moth', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Rippletile Splashline Chub', 1882, 4385, 680260, 2149622, 'Cleanwater Worm', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Freshwater Driftfoam Bream', 2006, 5295, 746480, 3000850, 'Suds Pellet', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Bubble Washback Trout', 2130, 6283, 812700, 3965976, 'Soap Worm', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Foam Mistfin Gar', 2254, 7346, 878920, 5045001, 'Foam Midge', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Ceramic Softswell Snapper', 2377, 8487, 945140, 2580232, 'Bubble Grub', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Soapstone Eel', 2501, 9705, 1011360, 3630782, 'Rinse Fly', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Tiled Clearrun Ray', 2625, 10999, 1077580, 4795231, 'Tile Shrimp', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Bathwater-Foamfin Arowana', 2749, 5553, 1143800, 6073578, 'Bath Nymph', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Dawnrinse Bubbletail Mackerel', 2873, 6694, 1210020, 2783046, 'Lather Roe', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Sudsy Sudswave Marlin', 2997, 7911, 1276240, 4032918, 'Tub Beetle', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Porcelain Basinrun Shark', 3120, 9205, 1342460, 5396689, 'Splash Larva', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'eternal', 'Driftsoap Tuna', 3244, 10577, 1408680, 6874358, 'Mist Cricket', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Briskwash Tubcrest Smelt', 3213, 13532, 1355200, 6613376, 'Ceramic Gnat', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Clearmist Shiner', 3476, 7099, 1541540, 8848440, 'Dawn Moth', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Rippletile Driftfoam Perch', 3740, 8796, 1727880, 4717112, 'Cleanwater Worm', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Freshwater Washback Carp', 4003, 10656, 1914220, 6872050, 'Suds Pellet', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Bubble Mistfin Pike', 4267, 12680, 2100560, 9347492, 'Soap Worm', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Foam Softswell Catfish', 4530, 14868, 2286900, 12143439, 'Foam Midge', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Ceramic Soapwake Grouper', 4793, 17218, 2473240, 5688452, 'Bubble Grub', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Soapstone Sturgeon', 5057, 19732, 2659580, 8404273, 'Rinse Fly', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Tiled Foamfin Manta', 5320, 22410, 2845920, 11440598, 'Tile Shrimp', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Bathwater-Bubbletail Barracuda', 5584, 11402, 3032260, 14797429, 'Bath Nymph', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Dawnrinse Sudswave Salmon', 5847, 13753, 3218600, 18474764, 'Lather Roe', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Sudsy Basinrun Swordfish', 6111, 16267, 3404940, 9295486, 'Tub Beetle', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Porcelain Tilerun Coelacanth', 6374, 18944, 3591280, 12892695, 'Splash Larva', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Driftsoap Leviathan', 6638, 21785, 3777620, 16810409, 'Mist Cricket', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'divine', 'Lather Rinsefin Guppy', 6901, 24789, 3963960, 21048628, 'Fresh Fry', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Clearmist Chub', 6848, 14134, 3819200, 20279952, 'Dawn Moth', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Rippletile Washback Bream', 7410, 17590, 4344340, 9991982, 'Cleanwater Worm', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Freshwater Mistfin Trout', 7971, 21394, 4869480, 15387557, 'Suds Pellet', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Bubble Softswell Gar', 8533, 25547, 5394620, 21686372, 'Soap Worm', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Foam Soapwake Snapper', 9094, 30047, 5919760, 28888429, 'Foam Midge', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Ceramic Clearrun Eel', 9656, 34896, 6444900, 36993726, 'Bubble Grub', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Soapstone Ray', 10217, 40092, 6970040, 19028209, 'Rinse Fly', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Tiled Bubbletail Arowana', 10779, 45637, 7495180, 26907696, 'Tile Shrimp', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Bathwater-Sudswave Mackerel', 11340, 23406, 8020320, 35690424, 'Bath Nymph', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Dawnrinse Basinrun Marlin', 11902, 28255, 8545460, 45376393, 'Lather Roe', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Sudsy Tilerun Shark', 12463, 33452, 9070600, 20862380, 'Tub Beetle', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Porcelain Lathergill Tuna', 13025, 38997, 9595740, 30322538, 'Splash Larva', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Driftsoap Minnow', 13586, 44890, 10120880, 40685938, 'Mist Cricket', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Lather Tubcrest Loach', 14148, 51131, 10646020, 51952578, 'Fresh Fry', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'cosmic', 'Briskwash Splashline Darter', 14710, 57720, 11171160, 64122458, 'Ceramic Gnat', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Rippletile Mistfin Carp', 14592, 34962, 10763200, 61780768, 'Cleanwater Worm', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Freshwater Softswell Pike', 15789, 42724, 12243140, 33423772, 'Suds Pellet', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Bubble Soapwake Catfish', 16985, 51227, 13723080, 49265857, 'Soap Worm', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Foam Clearrun Grouper', 18182, 60472, 15203020, 67653439, 'Foam Midge', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Ceramic Foamfin Sturgeon', 19378, 70459, 16682960, 88586518, 'Bubble Grub', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Soapstone Manta', 20575, 81188, 18162900, 41774670, 'Rinse Fly', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Tiled Sudswave Barracuda', 21771, 92658, 19642840, 62071374, 'Tile Shrimp', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Bathwater-Basinrun Salmon', 22968, 47911, 21122780, 84913576, 'Bath Nymph', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Dawnrinse Tilerun Swordfish', 24164, 57898, 22602720, 110301274, 'Lather Roe', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Sudsy Lathergill Coelacanth', 25361, 68627, 24082660, 138234468, 'Tub Beetle', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Porcelain Rinsefin Leviathan', 26557, 80097, 25562600, 69785898, 'Splash Larva', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Driftsoap Guppy', 27754, 92310, 27042540, 97082719, 'Mist Cricket', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Lather Splashline Smelt', 28951, 105264, 28522480, 126925036, 'Fresh Fry', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Briskwash Driftfoam Shiner', 30147, 118960, 30002420, 159312850, 'Ceramic Gnat', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'primordial', 'Clearmist Washback Perch', 31344, 133398, 31482360, 72409428, 'Dawn Moth', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Freshwater Soapwake Gar', 31232, 85201, 30240000, 69552000, 'Suds Pellet', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Bubble Clearrun Snapper', 33793, 102663, 34398000, 108697680, 'Soap Worm', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Foam Foamfin Eel', 36354, 121713, 38556000, 154995120, 'Foam Midge', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Ceramic Bubbletail Ray', 38915, 142351, 42714000, 208444320, 'Bubble Grub', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Soapstone Arowana', 41476, 164577, 46872000, 269045280, 'Rinse Fly', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Tiled Basinrun Mackerel', 44037, 188391, 51030000, 139311900, 'Tile Shrimp', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Bathwater-Tilerun Marlin', 46598, 98229, 55188000, 198124920, 'Bath Nymph', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Dawnrinse Lathergill Shark', 49159, 118867, 59346000, 264089700, 'Lather Roe', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Sudsy Rinsefin Tuna', 51720, 141093, 63504000, 337206240, 'Tub Beetle', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Porcelain Tubcrest Minnow', 54281, 164906, 67662000, 155622600, 'Splash Larva', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Driftsoap Loach', 56842, 190308, 71820000, 226951200, 'Mist Cricket', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Lather Driftfoam Darter', 59403, 217297, 75978000, 305431560, 'Fresh Fry', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Briskwash Washback Chub', 61964, 245874, 80136000, 391063680, 'Ceramic Gnat', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Clearmist Mistfin Bream', 64525, 276039, 84294000, 483847560, 'Dawn Moth', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'transcendent', 'Rippletile Softswell Trout', 67086, 141418, 88452000, 241473960, 'Cleanwater Worm', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Bubble Foamfin Grouper', 66816, 204457, 85120000, 232377600, 'Soap Worm', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Foam Bubbletail Sturgeon', 72295, 243634, 96824000, 347598160, 'Foam Midge', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Ceramic Sudswave Manta', 77774, 286208, 108528000, 482949600, 'Bubble Grub', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Soapstone Barracuda', 83253, 332178, 120232000, 638431920, 'Rinse Fly', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Tiled Tilerun Salmon', 88732, 381546, 131936000, 303452800, 'Tile Shrimp', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Bathwater-Lathergill Swordfish', 94211, 200668, 143640000, 453902400, 'Bath Nymph', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Dawnrinse Rinsefin Coelacanth', 99689, 243242, 155344000, 624482880, 'Lather Roe', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Sudsy Tubcrest Leviathan', 105168, 289213, 167048000, 815194240, 'Tub Beetle', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Porcelain Splashline Guppy', 110647, 338581, 178752000, 1026036480, 'Splash Larva', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Driftsoap Smelt', 116126, 391345, 190456000, 519944880, 'Mist Cricket', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Lather Washback Shiner', 121605, 447507, 202160000, 725754400, 'Fresh Fry', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Briskwash Mistfin Perch', 127084, 507065, 213864000, 951694800, 'Ceramic Gnat', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Clearmist Softswell Carp', 132563, 570021, 225568000, 1197766080, 'Dawn Moth', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Rippletile Soapwake Pike', 138042, 294029, 237272000, 545725600, 'Cleanwater Worm', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'apotheosis', 'Freshwater Clearrun Catfish', 143521, 350191, 248976000, 786764160, 'Suds Pellet', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Foam Sudswave Ray', 143360, 486277, 239680000, 757388800, 'Foam Midge', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Ceramic Basinrun Arowana', 155116, 574238, 272636000, 1095996720, 'Bubble Grub', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Soapstone Mackerel', 166871, 669487, 305592000, 1491288960, 'Rinse Fly', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Tiled Lathergill Marlin', 178627, 772024, 338548000, 1943265520, 'Tile Shrimp', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Bathwater-Rinsefin Shark', 190382, 409702, 371504000, 1014205920, 'Bath Nymph', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Dawnrinse Tubcrest Tuna', 202138, 497663, 404460000, 1452011400, 'Lather Roe', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Sudsy Splashline Minnow', 213893, 592912, 437416000, 1946501200, 'Tub Beetle', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Porcelain Driftfoam Loach', 225649, 695449, 470372000, 2497675320, 'Splash Larva', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Driftsoap Darter', 237404, 805275, 503328000, 1157654400, 'Mist Cricket', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Lather Mistfin Chub', 249160, 922389, 536284000, 1694657440, 'Fresh Fry', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Briskwash Softswell Bream', 260915, 1046792, 569240000, 2288344800, 'Ceramic Gnat', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Clearmist Soapwake Trout', 272671, 1178483, 602196000, 2938716480, 'Dawn Moth', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Rippletile Clearrun Gar', 284426, 612085, 635152000, 3645772480, 'Cleanwater Worm', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Freshwater Foamfin Snapper', 296182, 729199, 668108000, 1823934840, 'Suds Pellet', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'absolute', 'Bubble Eel', 307937, 853602, 701064000, 2516819760, 'Soap Worm', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Ceramic Tilerun Barracuda', 307200, 1144013, 675360000, 2424542400, 'Bubble Grub', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Soapstone Salmon', 332390, 1340863, 768222000, 3418587900, 'Rinse Fly', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Tiled Rinsefin Swordfish', 357581, 1553331, 861084000, 4572356040, 'Tile Shrimp', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Bathwater-Tubcrest Coelacanth', 382771, 832145, 953946000, 2194075800, 'Bath Nymph', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Dawnrinse Splashline Leviathan', 407962, 1013377, 1046808000, 3307913280, 'Lather Roe', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Sudsy Driftfoam Guppy', 433152, 1210227, 1139670000, 4581473400, 'Tub Beetle', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Porcelain Washback Smelt', 458342, 1422695, 1232532000, 6014756160, 'Splash Larva', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Driftsoap Shiner', 483533, 1650781, 1325394000, 7607761560, 'Mist Cricket', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Lather Softswell Perch', 508723, 1894485, 1418256000, 3871838880, 'Fresh Fry', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Briskwash Soapwake Carp', 533914, 2153807, 1511118000, 5424913620, 'Ceramic Gnat', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Clearmist Clearrun Pike', 559104, 2428748, 1603980000, 7137711000, 'Dawn Moth', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Rippletile Foamfin Catfish', 584294, 1270256, 1696842000, 9010231020, 'Cleanwater Worm', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Freshwater Bubbletail Grouper', 609485, 1513960, 1789704000, 4116319200, 'Suds Pellet', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Bubble Sturgeon', 634675, 1773283, 1882566000, 5948908560, 'Soap Worm', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'singularity', 'Foam Basinrun Manta', 659866, 2048223, 1975428000, 7941220560, 'Foam Midge', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Soapstone Marlin', 659200, 2673715, 1904000000, 7654080000, 'Rinse Fly', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Tiled Tubcrest Shark', 713254, 3114069, 2165800000, 10569104000, 'Tile Shrimp', 'Most active during calm evening water.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Bathwater-Splashline Tuna', 767309, 1685010, 2427600000, 13934424000, 'Bath Nymph', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Dawnrinse Driftfoam Minnow', 821363, 2058336, 2689400000, 7342062000, 'Lather Roe', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Sudsy Washback Loach', 875418, 2465176, 2951200000, 10594808000, 'Tub Beetle', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Porcelain Mistfin Darter', 929472, 2905529, 3213000000, 14297850000, 'Splash Larva', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Driftsoap Chub', 983526, 3379397, 3474800000, 18451188000, 'Mist Cricket', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Lather Soapwake Bream', 1037581, 3886778, 3736600000, 8594180000, 'Fresh Fry', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Briskwash Clearrun Trout', 1091635, 4427672, 3998400000, 12634944000, 'Ceramic Gnat', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Clearmist Foamfin Gar', 1145690, 5002081, 4260200000, 17126004000, 'Dawn Moth', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Rippletile Bubbletail Snapper', 1199744, 2634638, 4522000000, 22067360000, 'Cleanwater Worm', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Freshwater Sudswave Eel', 1253798, 3142019, 4783800000, 27459012000, 'Suds Pellet', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Bubble Ray', 1307853, 3682913, 5045600000, 13774488000, 'Soap Worm', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Foam Tilerun Arowana', 1361907, 4257322, 5307400000, 19053566000, 'Foam Midge', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'paradox', 'Ceramic Lathergill Mackerel', 1415962, 4865244, 5569200000, 24782940000, 'Bubble Grub', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Tiled Splashline Coelacanth', 1413120, 6200771, 5376000000, 23923200000, 'Tile Shrimp', 'Schools in arcs beneath floating foam.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Bathwater-Driftfoam Leviathan', 1528996, 3391313, 6115200000, 32471712000, 'Bath Nymph', 'Spooks when surface turbulence spikes.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Dawnrinse Washback Guppy', 1644872, 4158236, 6854400000, 15765120000, 'Lather Roe', 'Can run long along basin walls.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Sudsy Mistfin Smelt', 1760748, 4997001, 7593600000, 23995776000, 'Tub Beetle', 'Turns pearly in clean, clear water.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Porcelain Softswell Shiner', 1876623, 5907610, 8332800000, 33497856000, 'Splash Larva', 'Rests in corners behind tile ridges.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Driftsoap Perch', 1992499, 6890062, 9072000000, 44271360000, 'Mist Cricket', 'Bites cleaner on slow retrieves.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Lather Clearrun Carp', 2108375, 7944357, 9811200000, 56316288000, 'Fresh Fry', 'Leaves neat ringed wakes after jumps.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Briskwash Foamfin Pike', 2224251, 9070495, 10550400000, 28802592000, 'Ceramic Gnat', 'Glides smoothly through foam layers.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Clearmist Bubbletail Catfish', 2340127, 10268476, 11289600000, 40529664000, 'Dawn Moth', 'Bites best near warm faucet currents.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Rippletile Sudswave Grouper', 2456003, 5447414, 12028800000, 53528160000, 'Cleanwater Worm', 'Holds around deep tile grout channels.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Freshwater Basinrun Sturgeon', 2571878, 6501709, 12768000000, 67798080000, 'Suds Pellet', 'Can burst through bubble clusters quickly.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Bubble Manta', 2687754, 7627847, 13507200000, 31066560000, 'Soap Worm', 'Prefers stable temperatures over sudden chills.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Foam Lathergill Barracuda', 2803630, 8825827, 14246400000, 45018624000, 'Foam Midge', 'Feeds near bath bomb mineral clouds.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Ceramic Rinsefin Salmon', 2919506, 10095651, 14985600000, 60242112000, 'Bubble Grub', 'Responds to bright, reflective lures.'),
  ('bathtub_billows', 'Bathtub Billows', 'null', 'Soapstone Tubcrest Swordfish', 3035382, 11437318, 15724800000, 76737024000, 'Rinse Fly', 'Most active during calm evening water.')
on conflict (biome_key, rarity, fish_name) do update set
  biome_name = excluded.biome_name,
  min_weight_kg = excluded.min_weight_kg,
  max_weight_kg = excluded.max_weight_kg,
  min_price_coins = excluded.min_price_coins,
  max_price_coins = excluded.max_price_coins,
  preferred_bait = excluded.preferred_bait,
  notable_detail = excluded.notable_detail;

create or replace function public.refresh_leaderboards()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refreshed_at timestamp with time zone := timezone('utc'::text, now());
  v_bigint_max constant numeric := 9223372036854775807;
begin
  delete from public.leaderboard_snapshots;

  with source as (
    select
      gs.user_id,
      up.username,
      up.username_normalized,
      least(v_bigint_max, greatest(
        0::numeric,
        floor(
          coalesce(
            case when coalesce(gs.save_data ->> 'totalCoinsEarned', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (gs.save_data ->> 'totalCoinsEarned')::numeric end,
            case when coalesce(gs.save_data ->> 'coins', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (gs.save_data ->> 'coins')::numeric end,
            0
          )
        )
      ))::bigint as money_earned,
      least(v_bigint_max, greatest(
        0::numeric,
        floor(
          coalesce(
            case when coalesce(gs.save_data ->> 'totalCatches', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (gs.save_data ->> 'totalCatches')::numeric end,
            0
          )
        )
      ))::bigint as fish_caught
    from public.game_saves gs
    inner join public.user_profiles up
      on up.user_id = gs.user_id
    where up.username_normalized is not null
  ),
  ranked_money as (
    select
      s.user_id,
      s.username,
      s.money_earned as score,
      row_number() over (
        order by s.money_earned desc, s.fish_caught desc, s.username_normalized asc
      ) as rank
    from source s
    where s.money_earned > 0
  ),
  ranked_fish as (
    select
      s.user_id,
      s.username,
      s.fish_caught as score,
      row_number() over (
        order by s.fish_caught desc, s.money_earned desc, s.username_normalized asc
      ) as rank
    from source s
    where s.fish_caught > 0
  )
  insert into public.leaderboard_snapshots (
    metric,
    rank,
    user_id,
    username,
    score,
    refreshed_at
  )
  select
    'money_earned',
    rm.rank,
    rm.user_id,
    rm.username,
    rm.score,
    v_refreshed_at
  from ranked_money rm
  where rm.rank <= 100
  union all
  select
    'fish_caught',
    rf.rank,
    rf.user_id,
    rf.username,
    rf.score,
    v_refreshed_at
  from ranked_fish rf
  where rf.rank <= 100;
end;
$$;

select public.refresh_leaderboards();

-- ============================================================================
-- SOURCE MIGRATION: 20260315_farmer_leaderboard_snapshot_refresh.sql
-- ============================================================================

-- Virtual Farmer leaderboard snapshot cache with manual refresh RPC
-- and 20-minute cron refresh cadence.

create table if not exists public.farmer_leaderboard_cache (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  total_plants double precision not null default 0 check (total_plants >= 0),
  balance double precision not null default 0 check (balance >= 0),
  xp double precision not null default 0 check (xp >= 0),
  prestige_level integer not null default 0 check (prestige_level >= 0),
  achievements_count integer not null default 0 check (achievements_count >= 0),
  updated_at timestamp with time zone not null default timezone('utc'::text, now()),
  refreshed_at timestamp with time zone not null default timezone('utc'::text, now())
);

create index if not exists idx_farmer_lb_cache_total_plants_desc
  on public.farmer_leaderboard_cache (total_plants desc, updated_at asc);

create index if not exists idx_farmer_lb_cache_balance_desc
  on public.farmer_leaderboard_cache (balance desc, updated_at asc);

create index if not exists idx_farmer_lb_cache_xp_desc
  on public.farmer_leaderboard_cache (xp desc, updated_at asc);

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
    coalesce(pr.display_name, 'Farmer-' || left(p.user_id::text, 8)),
    greatest(0, coalesce(p.total_plants, 0)),
    greatest(0, coalesce(p.balance, 0)),
    greatest(0, coalesce(p.xp, 0)),
    greatest(0, coalesce(p.prestige_level, 0)),
    greatest(0, coalesce(p.achievements_count, 0)),
    coalesce(p.last_saved_at, p.updated_at, v_refreshed_at),
    v_refreshed_at
  from public.player_progress p
  left join public.profiles pr
    on pr.user_id = p.user_id;
end;
$$;

create or replace function public.request_farmer_leaderboard_refresh()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamp with time zone := timezone('utc'::text, now());
  v_last_refreshed_at timestamp with time zone;
begin
  if v_uid is null then
    return jsonb_build_object(
      'ok', false,
      'refreshed', false,
      'reason', 'You must be signed in.'
    );
  end if;

  select max(refreshed_at)
  into v_last_refreshed_at
  from public.farmer_leaderboard_cache;

  if v_last_refreshed_at is not null and (v_now - v_last_refreshed_at) < interval '60 seconds' then
    return jsonb_build_object(
      'ok', true,
      'refreshed', false,
      'reason', 'Leaderboard was refreshed recently.',
      'refreshed_at', v_last_refreshed_at
    );
  end if;

  perform public.refresh_farmer_leaderboard_cache();

  select max(refreshed_at)
  into v_last_refreshed_at
  from public.farmer_leaderboard_cache;

  return jsonb_build_object(
    'ok', true,
    'refreshed', true,
    'refreshed_at', v_last_refreshed_at
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'refreshed', false,
      'reason', sqlerrm
    );
end;
$$;

alter table public.farmer_leaderboard_cache enable row level security;

drop policy if exists farmer_leaderboard_cache_select_authenticated on public.farmer_leaderboard_cache;
create policy farmer_leaderboard_cache_select_authenticated
on public.farmer_leaderboard_cache
for select
to authenticated
using (true);

drop view if exists public.leaderboard;
create view public.leaderboard as
select
  user_id,
  display_name,
  total_plants,
  balance,
  xp,
  prestige_level,
  achievements_count,
  updated_at,
  refreshed_at
from public.farmer_leaderboard_cache;

revoke all on table public.farmer_leaderboard_cache from anon;
grant select on table public.farmer_leaderboard_cache to authenticated;

revoke all on function public.request_farmer_leaderboard_refresh() from public;
grant execute on function public.request_farmer_leaderboard_refresh() to authenticated;

grant select on public.leaderboard to authenticated;

select public.refresh_farmer_leaderboard_cache();

do $$
declare
  v_job_id bigint;
begin
  if to_regclass('cron.job') is null then
    begin
      create extension if not exists pg_cron with schema extensions;
    exception
      when others then
        raise notice 'pg_cron extension could not be created for farmer leaderboard: %', sqlerrm;
    end;
  end if;

  if to_regclass('cron.job') is null then
    raise notice 'pg_cron is not available. Farmer leaderboard auto-refresh schedule skipped.';
    return;
  end if;

  select j.jobid
  into v_job_id
  from cron.job j
  where j.jobname = 'refresh_farmer_leaderboard_every_20_minutes'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'refresh_farmer_leaderboard_every_20_minutes',
    '*/20 * * * *',
    'select public.refresh_farmer_leaderboard_cache();'
  );
exception
  when others then
    raise notice 'Could not configure farmer leaderboard cron schedule: %', sqlerrm;
end;
$$;

-- ============================================================================
-- SOURCE MIGRATION: 20260315_fisher_leaderboard_refresh_20_minutes.sql
-- ============================================================================

-- Change Virtual Fisher leaderboard snapshot cadence from 10 minutes to 20 minutes.

do $$
declare
  v_job_id_10 bigint;
  v_job_id_20 bigint;
begin
  if to_regclass('cron.job') is null then
    begin
      create extension if not exists pg_cron with schema extensions;
    exception
      when others then
        raise notice 'pg_cron extension could not be created for fisher leaderboard schedule: %', sqlerrm;
    end;
  end if;

  if to_regclass('cron.job') is null then
    raise notice 'pg_cron is not available. Fisher leaderboard auto-refresh schedule skipped.';
    return;
  end if;

  select j.jobid
  into v_job_id_10
  from cron.job j
  where j.jobname = 'refresh_leaderboards_every_10_minutes'
  limit 1;

  if v_job_id_10 is not null then
    perform cron.unschedule(v_job_id_10);
  end if;

  select j.jobid
  into v_job_id_20
  from cron.job j
  where j.jobname = 'refresh_leaderboards_every_20_minutes'
  limit 1;

  if v_job_id_20 is not null then
    perform cron.unschedule(v_job_id_20);
  end if;

  perform cron.schedule(
    'refresh_leaderboards_every_20_minutes',
    '*/20 * * * *',
    'select public.refresh_leaderboards();'
  );
exception
  when others then
    raise notice 'Could not configure fisher leaderboard cron schedule: %', sqlerrm;
end;
$$;

-- ============================================================================
-- SOURCE MIGRATION: 20260315_leaderboards_include_zero_scores.sql
-- ============================================================================

-- Keep leaderboard snapshots populated even for new users with zero progress.
-- Also accepts scientific-notation numeric strings from JSON save payloads.

create or replace function public.refresh_leaderboards()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_refreshed_at timestamp with time zone := timezone('utc'::text, now());
  v_bigint_max constant numeric := 9223372036854775807;
begin
  delete from public.leaderboard_snapshots;

  with source as (
    select
      up.user_id,
      up.username,
      up.username_normalized,
      least(v_bigint_max, greatest(
        0::numeric,
        floor(
          coalesce(
            case
              when coalesce(gs.save_data ->> 'totalCoinsEarned', '') ~ '^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$'
                then (gs.save_data ->> 'totalCoinsEarned')::numeric
            end,
            case
              when coalesce(gs.save_data ->> 'coins', '') ~ '^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$'
                then (gs.save_data ->> 'coins')::numeric
            end,
            0
          )
        )
      ))::bigint as money_earned,
      least(v_bigint_max, greatest(
        0::numeric,
        floor(
          coalesce(
            case
              when coalesce(gs.save_data ->> 'totalCatches', '') ~ '^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$'
                then (gs.save_data ->> 'totalCatches')::numeric
            end,
            0
          )
        )
      ))::bigint as fish_caught
    from public.user_profiles up
    left join public.game_saves gs
      on gs.user_id = up.user_id
    where up.username_normalized is not null
  ),
  ranked_money as (
    select
      s.user_id,
      s.username,
      s.money_earned as score,
      row_number() over (
        order by s.money_earned desc, s.fish_caught desc, s.username_normalized asc
      ) as rank
    from source s
  ),
  ranked_fish as (
    select
      s.user_id,
      s.username,
      s.fish_caught as score,
      row_number() over (
        order by s.fish_caught desc, s.money_earned desc, s.username_normalized asc
      ) as rank
    from source s
  )
  insert into public.leaderboard_snapshots (
    metric,
    rank,
    user_id,
    username,
    score,
    refreshed_at
  )
  select
    'money_earned',
    rm.rank,
    rm.user_id,
    rm.username,
    rm.score,
    v_refreshed_at
  from ranked_money rm
  where rm.rank <= 100
  union all
  select
    'fish_caught',
    rf.rank,
    rf.user_id,
    rf.username,
    rf.score,
    v_refreshed_at
  from ranked_fish rf
  where rf.rank <= 100;
end;
$$;

select public.refresh_leaderboards();

-- ============================================================================
-- SOURCE MIGRATION: 20260315_virtual_farmer_schema_compatibility.sql
-- ============================================================================

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

drop view if exists public.leaderboard;
create view public.leaderboard as
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

-- ============================================================================
-- SOURCE MIGRATION: 20260323_platform_features.sql
-- ============================================================================

-- ============================================================
-- Platform Features Migration: Social, Achievements, Shop,
-- Chat, Admin, Onboarding, Extended Profiles
-- 2026-03-23
-- ============================================================

-- ── Extend user_profiles ────────────────────────────────────
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS avatar_url text DEFAULT '',
  ADD COLUMN IF NOT EXISTS bio text DEFAULT '',
  ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboarding_completed boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- ── Follows (asymmetric — mutual follows = friends) ─────────
CREATE TABLE IF NOT EXISTS follows (
  follower_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- ── Blocks / Restrictions ───────────────────────────────────
CREATE TABLE IF NOT EXISTS blocks (
  blocker_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  restriction_type text NOT NULL DEFAULT 'block'
    CHECK (restriction_type IN ('block', 'restrict')),
  created_at       timestamptz DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

-- ── Achievements v2 ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS achievements (
  id                text PRIMARY KEY,
  name              text NOT NULL,
  description       text NOT NULL,
  icon              text NOT NULL DEFAULT 'trophy',
  category          text NOT NULL DEFAULT 'general',
  requirement_type  text NOT NULL DEFAULT 'count',
  requirement_value int  NOT NULL DEFAULT 1,
  rarity            text NOT NULL DEFAULT 'common'
    CHECK (rarity IN ('common','uncommon','rare','epic','legendary')),
  xp_reward         int  DEFAULT 0,
  sort_order        int  DEFAULT 0
);

CREATE TABLE IF NOT EXISTS user_achievements (
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  achievement_id text NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
  unlocked_at    timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, achievement_id)
);

-- Seed 20 achievements
INSERT INTO achievements (id, name, description, icon, category, requirement_type, requirement_value, rarity, xp_reward, sort_order) VALUES
  ('first_cast',        'First Cast',        'Catch your very first fish.',                          'fish',       'fishing',     'fish_caught',     1,        'common',    50,   1),
  ('hooked_10',         'Getting Hooked',    'Catch 10 fish total.',                                 'anchor',     'fishing',     'fish_caught',     10,       'common',    100,  2),
  ('century_catch',     'Century Catch',     'Catch 100 fish across all biomes.',                    'waves',      'fishing',     'fish_caught',     100,      'uncommon',  250,  3),
  ('fish_500',          'Master Angler',     'Catch 500 fish — you live on the water now.',          'sailboat',   'fishing',     'fish_caught',     500,      'rare',      500,  4),
  ('legendary_pull',    'Legendary Pull',    'Land a Legendary-rarity fish.',                        'crown',      'fishing',     'legendary_fish',  1,        'epic',      750,  5),
  ('biome_explorer',    'Biome Explorer',    'Fish in 10 different biomes.',                         'compass',    'exploration', 'biomes_visited',  10,       'uncommon',  200,  6),
  ('world_traveler',    'World Traveler',    'Visit every biome at least once.',                     'globe',      'exploration', 'biomes_visited',  60,       'legendary', 1500, 7),
  ('early_bird',        'Early Bird',        'Log in for 3 consecutive days.',                       'sunrise',    'dedication',  'login_streak',    3,        'common',    100,  8),
  ('devoted_player',    'Devoted Player',    'Log in for 14 consecutive days.',                      'calendar',   'dedication',  'login_streak',    14,       'rare',      400,  9),
  ('social_butterfly',  'Social Butterfly',  'Make 5 mutual friends on the platform.',               'users',      'social',      'friends_count',   5,        'uncommon',  200,  10),
  ('big_spender',       'Big Spender',       'Spend 10,000 coins in the shop.',                      'shopping-bag','economy',    'coins_spent',     10000,    'uncommon',  300,  11),
  ('gold_rush',         'Gold Rush',         'Earn 100,000 total money across all games.',           'coins',      'economy',     'money_earned',    100000,   'rare',      500,  12),
  ('millionaire_club',  'Millionaire Club',  'Accumulate 1,000,000 coins in your balance.',          'gem',        'economy',     'money_earned',    1000000,  'legendary', 2000, 13),
  ('rod_collector',     'Rod Collector',     'Own 5 different fishing rods.',                        'tool',       'collection',  'rods_owned',      5,        'uncommon',  200,  14),
  ('bait_master',       'Bait Master',       'Use 8 different bait types.',                          'bug',        'collection',  'baits_used',      8,        'rare',      350,  15),
  ('species_catalog',   'Species Catalog',   'Discover 50 unique fish species.',                     'book-open',  'collection',  'species_found',   50,       'rare',      500,  16),
  ('chat_champion',     'Chat Champion',     'Send 100 messages in chat.',                           'message-circle','social',   'messages_sent',   100,      'uncommon',  150,  17),
  ('night_owl',         'Night Owl',         'Play a game session between midnight and 4 AM.',       'moon',       'dedication',  'night_sessions',  1,        'uncommon',  100,  18),
  ('completionist',     'Completionist',     'Unlock 15 other achievements.',                        'award',      'meta',        'achievements_unlocked', 15, 'epic',     1000, 19),
  ('platform_pioneer',  'Platform Pioneer',  'Complete the onboarding tutorial.',                    'rocket',     'meta',        'onboarding_done', 1,        'common',    75,   20)
ON CONFLICT (id) DO NOTHING;

-- ── Shop Items ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shop_items (
  id           text PRIMARY KEY,
  name         text NOT NULL,
  description  text NOT NULL,
  price        int  NOT NULL,
  currency     text NOT NULL DEFAULT 'coins' CHECK (currency IN ('coins','gems')),
  category     text NOT NULL DEFAULT 'general',
  icon         text NOT NULL DEFAULT 'package',
  rarity       text NOT NULL DEFAULT 'common'
    CHECK (rarity IN ('common','uncommon','rare','epic','legendary')),
  is_available boolean DEFAULT true,
  metadata     jsonb DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS user_inventory (
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id      text NOT NULL REFERENCES shop_items(id) ON DELETE CASCADE,
  quantity     int  DEFAULT 1,
  purchased_at timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, item_id)
);

CREATE TABLE IF NOT EXISTS user_balances (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  coins   bigint DEFAULT 500,
  gems    int    DEFAULT 0
);

-- Seed shop items
INSERT INTO shop_items (id, name, description, price, currency, category, icon, rarity, metadata) VALUES
  ('rod_bamboo',       'Bamboo Rod',          'A lightweight starter rod. Reliable and humble.',                          200,   'coins', 'rods',      'tool',        'common',    '{"catch_bonus": 0}'),
  ('rod_carbon',       'Carbon Fiber Rod',    'Modern engineering. +10% catch speed.',                                   1500,  'coins', 'rods',      'tool',        'uncommon',  '{"catch_bonus": 10}'),
  ('rod_titanium',     'Titanium Rod',        'Built for deep-water legends. +25% catch speed.',                         5000,  'coins', 'rods',      'tool',        'rare',      '{"catch_bonus": 25}'),
  ('rod_mythic',       'Mythic Rod',          'Forged in starlight. +50% catch speed, +rare fish chance.',               25000, 'coins', 'rods',      'tool',        'legendary', '{"catch_bonus": 50, "rare_boost": true}'),
  ('bait_worm',        'Earthworm Pack',      'Standard bait. 20 uses.',                                                100,   'coins', 'bait',      'bug',         'common',    '{"uses": 20}'),
  ('bait_shrimp',      'Shrimp Bait',         'Attracts mid-tier fish. 15 uses.',                                       350,   'coins', 'bait',      'bug',         'uncommon',  '{"uses": 15}'),
  ('bait_golden',      'Golden Lure',         'Significantly increases rare fish chance. 10 uses.',                      2000,  'coins', 'bait',      'sparkles',    'rare',      '{"uses": 10, "rare_boost": true}'),
  ('bait_phantom',     'Phantom Bait',        'Draws legendary fish from the void. 5 uses.',                             8000,  'coins', 'bait',      'ghost',       'epic',      '{"uses": 5, "legendary_boost": true}'),
  ('amulet_luck',      'Lucky Amulet',        'Slightly boosts rare drop rates while equipped.',                         3000,  'coins', 'amulets',   'gem',         'rare',      '{"luck_bonus": 5}'),
  ('amulet_xp',        'Wisdom Amulet',       'Earn 15% more XP from all activities.',                                  4500,  'coins', 'amulets',   'book-open',   'rare',      '{"xp_bonus": 15}'),
  ('amulet_void',      'Void Amulet',         'Unlocks the Aetherial Void biome.',                                      50000, 'coins', 'amulets',   'eye',         'legendary', '{"unlocks_biome": "aetherial_void"}'),
  ('boost_2x_coins',   'Double Coins (1hr)',  'All coin earnings doubled for 60 minutes.',                               1200,  'coins', 'boosts',    'zap',         'uncommon',  '{"duration_min": 60, "multiplier": 2}'),
  ('boost_2x_xp',      'Double XP (1hr)',     'All XP earnings doubled for 60 minutes.',                                1200,  'coins', 'boosts',    'trending-up', 'uncommon',  '{"duration_min": 60, "multiplier": 2}'),
  ('boost_auto_fish',  'Auto-Fish (30min)',   'Fish are caught automatically for 30 minutes.',                           3000,  'gems',  'boosts',    'cpu',         'rare',      '{"duration_min": 30}'),
  ('cosmetic_hat_1',   'Sailor Hat',          'A classic maritime look for your profile.',                               800,   'coins', 'cosmetics', 'anchor',      'common',    '{"slot": "hat"}'),
  ('cosmetic_hat_2',   'Pirate Tricorn',      'Arr! Strike fear into the fish.',                                         2500,  'coins', 'cosmetics', 'skull',       'uncommon',  '{"slot": "hat"}'),
  ('cosmetic_frame_1', 'Ocean Frame',         'A wave-patterned profile frame.',                                         1500,  'coins', 'cosmetics', 'frame',       'uncommon',  '{"slot": "frame"}'),
  ('cosmetic_frame_2', 'Golden Frame',        'A prestigious golden border for your profile.',                           15000, 'coins', 'cosmetics', 'award',       'epic',      '{"slot": "frame"}'),
  ('cosmetic_title_1', 'Title: The Fisher',   'Display "The Fisher" on your profile.',                                   500,   'coins', 'cosmetics', 'tag',         'common',    '{"title": "The Fisher"}'),
  ('cosmetic_title_2', 'Title: Legend of the Deep', 'Display "Legend of the Deep" on your profile.',                     20000, 'coins', 'cosmetics', 'crown',       'legendary', '{"title": "Legend of the Deep"}')
ON CONFLICT (id) DO NOTHING;

-- ── Chat System ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_rooms (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text,
  type       text NOT NULL DEFAULT 'dm' CHECK (type IN ('dm','group','global')),
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chat_members (
  room_id   uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now(),
  PRIMARY KEY (room_id, user_id)
);

CREATE TABLE IF NOT EXISTS messages (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id    uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content    text NOT NULL CHECK (char_length(content) <= 2000),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_room_created ON messages(room_id, created_at DESC);

-- Seed global chat room
INSERT INTO chat_rooms (id, name, type) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Global Chat', 'global')
ON CONFLICT (id) DO NOTHING;

-- ── Admin Logs ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_logs (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  admin_id       uuid NOT NULL REFERENCES auth.users(id),
  action         text NOT NULL,
  target_user_id uuid REFERENCES auth.users(id),
  details        jsonb DEFAULT '{}',
  created_at     timestamptz DEFAULT now()
);

-- ── Platform Settings (weather, announcements, etc.) ────────
CREATE TABLE IF NOT EXISTS platform_settings (
  key        text PRIMARY KEY,
  value      jsonb NOT NULL DEFAULT '{}',
  updated_by uuid REFERENCES auth.users(id),
  updated_at timestamptz DEFAULT now()
);

INSERT INTO platform_settings (key, value) VALUES
  ('global_weather', '{"condition": "clear", "intensity": 1}'),
  ('motd', '{"message": "Welcome to Virtual Harvest Platform!"}')
ON CONFLICT (key) DO NOTHING;

-- ── Onboarding Progress ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS onboarding_progress (
  user_id         uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  steps_completed text[] DEFAULT '{}',
  skipped         boolean DEFAULT false,
  completed_at    timestamptz
);

-- ── RLS Policies ────────────────────────────────────────────

-- Follows
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY follows_select ON follows FOR SELECT USING (true);
CREATE POLICY follows_insert ON follows FOR INSERT WITH CHECK (auth.uid() = follower_id);
CREATE POLICY follows_delete ON follows FOR DELETE USING (auth.uid() = follower_id);

-- Blocks
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY blocks_select ON blocks FOR SELECT USING (auth.uid() = blocker_id);
CREATE POLICY blocks_insert ON blocks FOR INSERT WITH CHECK (auth.uid() = blocker_id);
CREATE POLICY blocks_delete ON blocks FOR DELETE USING (auth.uid() = blocker_id);

-- Achievements (public read)
ALTER TABLE achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY achievements_select ON achievements FOR SELECT USING (true);

-- User achievements
ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_achievements_select ON user_achievements FOR SELECT USING (true);
CREATE POLICY user_achievements_insert ON user_achievements FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Shop items (public read)
ALTER TABLE shop_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY shop_items_select ON shop_items FOR SELECT USING (true);

-- User inventory
ALTER TABLE user_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_inventory_select ON user_inventory FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_inventory_insert ON user_inventory FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_inventory_update ON user_inventory FOR UPDATE USING (auth.uid() = user_id);

-- User balances
ALTER TABLE user_balances ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_balances_select ON user_balances FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY user_balances_update ON user_balances FOR UPDATE USING (auth.uid() = user_id);

-- Chat rooms (members can read)
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_rooms_select ON chat_rooms FOR SELECT USING (
  type = 'global' OR
  EXISTS (SELECT 1 FROM chat_members WHERE chat_members.room_id = id AND chat_members.user_id = auth.uid())
);

-- Chat members
ALTER TABLE chat_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_members_select ON chat_members FOR SELECT USING (user_id = auth.uid() OR
  EXISTS (SELECT 1 FROM chat_members cm WHERE cm.room_id = chat_members.room_id AND cm.user_id = auth.uid()));
CREATE POLICY chat_members_insert ON chat_members FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Messages
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY messages_select ON messages FOR SELECT USING (
  EXISTS (SELECT 1 FROM chat_rooms WHERE chat_rooms.id = room_id AND chat_rooms.type = 'global') OR
  EXISTS (SELECT 1 FROM chat_members WHERE chat_members.room_id = messages.room_id AND chat_members.user_id = auth.uid())
);
CREATE POLICY messages_insert ON messages FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- Admin logs (admin only)
ALTER TABLE admin_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY admin_logs_select ON admin_logs FOR SELECT USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE user_profiles.user_id = auth.uid() AND user_profiles.is_admin = true)
);
CREATE POLICY admin_logs_insert ON admin_logs FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM user_profiles WHERE user_profiles.user_id = auth.uid() AND user_profiles.is_admin = true)
);

-- Platform settings (public read, admin write)
ALTER TABLE platform_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_settings_select ON platform_settings FOR SELECT USING (true);
CREATE POLICY platform_settings_update ON platform_settings FOR UPDATE USING (
  EXISTS (SELECT 1 FROM user_profiles WHERE user_profiles.user_id = auth.uid() AND user_profiles.is_admin = true)
);

-- Onboarding progress
ALTER TABLE onboarding_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY onboarding_select ON onboarding_progress FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY onboarding_insert ON onboarding_progress FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY onboarding_update ON onboarding_progress FOR UPDATE USING (auth.uid() = user_id);

-- ── Enable Realtime for chat ────────────────────────────────
do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
exception
  when others then
    raise notice 'Could not add public.messages to supabase_realtime: %', sqlerrm;
end;
$$;

-- ============================================================================
-- SOURCE MIGRATION: 20260324_split_weather_keys.sql
-- ============================================================================

-- Split global_weather into separate fisher_weather and farmer_weather keys
-- so each game can have independent weather controlled by admins.

INSERT INTO platform_settings (key, value) VALUES
  ('fisher_weather', '{"condition": "clear", "intensity": 1}'),
  ('farmer_weather', '{"condition": "clear", "intensity": 1}')
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- SOURCE MIGRATION: 20260328_chat_message_retention.sql
-- ============================================================================

-- Enforce a rolling 12-hour retention window for live chat messages.

create or replace function public.cleanup_expired_chat_messages()
returns integer
language plpgsql
set search_path = public
as $$
declare
  v_deleted integer;
begin
  delete from public.messages
  where created_at < timezone('utc'::text, now()) - interval '12 hours';

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

do $$
declare
  v_job_id bigint;
begin
  perform public.cleanup_expired_chat_messages();

  if to_regclass('cron.job') is null then
    begin
      create extension if not exists pg_cron with schema extensions;
    exception
      when others then
        raise notice 'pg_cron extension could not be created for chat retention: %', sqlerrm;
    end;
  end if;

  if to_regclass('cron.job') is null then
    raise notice 'pg_cron is not available. Chat retention schedule skipped.';
    return;
  end if;

  select j.jobid
  into v_job_id
  from cron.job j
  where j.jobname = 'cleanup_expired_chat_messages_every_15_minutes'
  limit 1;

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'cleanup_expired_chat_messages_every_15_minutes',
    '*/15 * * * *',
    'select public.cleanup_expired_chat_messages();'
  );
exception
  when others then
    raise notice 'Could not configure chat retention schedule: %', sqlerrm;
end;
$$;

-- ============================================================================
-- SOURCE MIGRATION: 20260401_global_username_playtime_and_profile_me.sql
-- ============================================================================

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

drop view if exists public.leaderboard;
create view public.leaderboard as
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

