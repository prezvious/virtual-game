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
