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
