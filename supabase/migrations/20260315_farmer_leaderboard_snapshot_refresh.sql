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

create or replace view public.leaderboard as
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
