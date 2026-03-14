begin;

create table if not exists public.profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint profiles_display_name_length check (char_length(trim(display_name)) between 3 and 24),
    constraint profiles_display_name_safe check (display_name ~ '^[A-Za-z0-9 ._''-]{3,24}$')
);

create table if not exists public.player_progress (
    user_id uuid primary key references auth.users (id) on delete cascade,
    balance double precision not null default 0 check (balance >= 0),
    xp double precision not null default 0 check (xp >= 0),
    total_plants double precision not null default 0 check (total_plants >= 0),
    prestige_level integer not null default 0 check (prestige_level >= 0),
    achievements_count integer not null default 0 check (achievements_count >= 0),
    game_state jsonb not null default '{}'::jsonb,
    stats_state jsonb not null default '{}'::jsonb,
    auto_farm_state jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    last_saved_at timestamptz not null default now()
);

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'profiles_display_name_length'
        and conrelid = 'public.profiles'::regclass
    ) then
        alter table public.profiles
        add constraint profiles_display_name_length check (char_length(trim(display_name)) between 3 and 24);
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'profiles_display_name_safe'
        and conrelid = 'public.profiles'::regclass
    ) then
        alter table public.profiles
        add constraint profiles_display_name_safe check (display_name ~ '^[A-Za-z0-9 ._''-]{3,24}$');
    end if;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    default_name text;
begin
    default_name := coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
        nullif(split_part(new.email, '@', 1), ''),
        'Farmer-' || left(new.id::text, 8)
    );

    default_name := regexp_replace(default_name, '[^A-Za-z0-9 ._''-]', '', 'g');
    default_name := left(trim(default_name), 24);
    if char_length(default_name) < 3 then
        default_name := 'Farmer-' || left(new.id::text, 8);
    end if;

    insert into public.profiles (user_id, display_name)
    values (new.id, default_name)
    on conflict (user_id) do nothing;

    return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

drop trigger if exists player_progress_set_updated_at on public.player_progress;
create trigger player_progress_set_updated_at
before update on public.player_progress
for each row
execute function public.set_updated_at();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

create index if not exists idx_player_progress_total_plants_desc
    on public.player_progress (total_plants desc, updated_at desc);

create index if not exists idx_player_progress_balance_desc
    on public.player_progress (balance desc, updated_at desc);

create index if not exists idx_player_progress_xp_desc
    on public.player_progress (xp desc, updated_at desc);

create index if not exists idx_player_progress_updated_at
    on public.player_progress (updated_at desc);

alter table public.profiles enable row level security;
alter table public.player_progress enable row level security;

drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated
on public.profiles
for select
to authenticated
using (true);

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
left join public.profiles pr on pr.user_id = p.user_id;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.player_progress to authenticated;
grant select on public.leaderboard to authenticated;

commit;
