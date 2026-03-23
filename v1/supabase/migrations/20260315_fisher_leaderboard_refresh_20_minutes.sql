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
