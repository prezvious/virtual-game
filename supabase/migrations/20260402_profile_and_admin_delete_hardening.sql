-- Atomic profile updates and admin-driven auth user deletion that preserves logs.

alter table public.admin_logs
  drop constraint if exists admin_logs_target_user_id_fkey;

alter table public.admin_logs
  add constraint admin_logs_target_user_id_fkey
    foreign key (target_user_id) references auth.users(id) on delete set null;

create or replace function public.update_user_profile_atomic(
  p_target_user_id uuid,
  p_candidate text default null,
  p_avatar_url text default null,
  p_bio text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claim jsonb := jsonb_build_object('ok', true);
  v_profile public.user_profiles%rowtype;
begin
  if p_target_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing user id.');
  end if;

  insert into public.user_profiles (user_id)
  values (p_target_user_id)
  on conflict (user_id) do nothing;

  if p_candidate is not null then
    v_claim := public._claim_username_for_user(p_target_user_id, p_candidate);

    if coalesce((v_claim ->> 'ok')::boolean, false) = false then
      return v_claim;
    end if;
  end if;

  update public.user_profiles
  set
    avatar_url = case when p_avatar_url is null then avatar_url else p_avatar_url end,
    bio = case when p_bio is null then bio else p_bio end
  where user_id = p_target_user_id
  returning *
  into v_profile;

  return jsonb_build_object(
    'ok', true,
    'username', coalesce(v_profile.username, ''),
    'avatar_url', coalesce(v_profile.avatar_url, ''),
    'bio', coalesce(v_profile.bio, '')
  );
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'reason', 'That username is already in use.');
end;
$$;

revoke all on function public.update_user_profile_atomic(uuid, text, text, text) from public;
grant execute on function public.update_user_profile_atomic(uuid, text, text, text) to service_role;

create or replace function public.admin_delete_user_account(
  p_target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_deleted_count integer := 0;
begin
  if p_target_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing target user id.');
  end if;

  update public.admin_logs
  set target_user_id = null
  where target_user_id = p_target_user_id;

  delete from auth.users
  where id = p_target_user_id;

  get diagnostics v_deleted_count = row_count;

  if v_deleted_count = 0 then
    return jsonb_build_object('ok', false, 'reason', 'User not found.');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_delete_user_account(uuid) from public;
grant execute on function public.admin_delete_user_account(uuid) to service_role;
