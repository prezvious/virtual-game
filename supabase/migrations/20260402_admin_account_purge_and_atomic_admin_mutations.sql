-- Safe auth-user deletion for admin flows plus atomic admin-only mutation RPCs.

alter table public.admin_logs
  drop constraint if exists admin_logs_admin_id_fkey,
  drop constraint if exists admin_logs_target_user_id_fkey;

alter table public.admin_logs
  add constraint admin_logs_admin_id_fkey
    foreign key (admin_id) references auth.users(id) on delete cascade,
  add constraint admin_logs_target_user_id_fkey
    foreign key (target_user_id) references auth.users(id) on delete cascade;

alter table public.platform_settings
  drop constraint if exists platform_settings_updated_by_fkey;

alter table public.platform_settings
  add constraint platform_settings_updated_by_fkey
    foreign key (updated_by) references auth.users(id) on delete set null;

create or replace function public.admin_increment_inventory(
  p_target_user_id uuid,
  p_item_id text,
  p_delta integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id text := trim(coalesce(p_item_id, ''));
  v_delta integer := coalesce(p_delta, 0);
  v_quantity integer;
begin
  if p_target_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing target user id.');
  end if;

  if v_item_id = '' then
    return jsonb_build_object('ok', false, 'reason', 'Missing item id.');
  end if;

  if v_delta <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'Delta must be greater than zero.');
  end if;

  insert into public.user_inventory (
    user_id,
    item_id,
    quantity
  )
  values (
    p_target_user_id,
    v_item_id,
    v_delta
  )
  on conflict (user_id, item_id) do update
    set quantity = public.user_inventory.quantity + excluded.quantity
  returning quantity
  into v_quantity;

  return jsonb_build_object(
    'ok', true,
    'quantity', v_quantity
  );
end;
$$;

revoke all on function public.admin_increment_inventory(uuid, text, integer) from public;
grant execute on function public.admin_increment_inventory(uuid, text, integer) to service_role;

create or replace function public.admin_adjust_user_balance(
  p_target_user_id uuid,
  p_delta bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_delta bigint := coalesce(p_delta, 0);
  v_coins bigint;
begin
  if p_target_user_id is null then
    return jsonb_build_object('ok', false, 'reason', 'Missing target user id.');
  end if;

  if v_delta = 0 then
    return jsonb_build_object('ok', false, 'reason', 'Delta must be non-zero.');
  end if;

  insert into public.user_balances (
    user_id,
    coins
  )
  values (
    p_target_user_id,
    greatest(0::bigint, v_delta)
  )
  on conflict (user_id) do update
    set coins = greatest(0::bigint, public.user_balances.coins + v_delta)
  returning coins
  into v_coins;

  return jsonb_build_object(
    'ok', true,
    'coins', v_coins
  );
end;
$$;

revoke all on function public.admin_adjust_user_balance(uuid, bigint) from public;
grant execute on function public.admin_adjust_user_balance(uuid, bigint) to service_role;
