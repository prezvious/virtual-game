# Supabase Setup (Virtual Farmer Legacy Copy)

Last updated: March 15, 2026

This folder contains the SQL and browser config used by the Next-served Virtual Farmer copy (`/farmer-legacy/*`) for auth, cloud save, and leaderboard reads.

## Quick Setup

1. Create a Supabase project.
2. In SQL Editor, run `001_progress_schema.sql`.
3. From the repo root, run `npm run sync-public-auth-config`.
4. The generated `/runtime-supabase-config.js` file will be read by `config.js` automatically.
5. In Supabase Auth, enable the Email provider.
6. If you enable email confirmation, complete confirmation before first login.

## What The SQL Creates

- `public.profiles`
  - Per-user display name profile
  - 3-24 character validation and safe-character regex
- `public.player_progress`
  - Main cloud save row per user
  - Stores numeric progress plus `game_state`, `stats_state`, and `auto_farm_state` JSONB
- Triggers/functions
  - `set_updated_at` for automatic `updated_at` refresh
  - `handle_new_user` to seed default profile rows
- `public.leaderboard` view
  - Joins `player_progress` with display names
- RLS policies
  - Authenticated users can read/update only their own profile/progress rows

## Data Persisted By The Frontend

The game writes full progression snapshots including:

- Balance, XP, total plants, prestige level
- Achievements count
- Serialized `game_state` and `stats_state`
- `auto_farm_state`
- `last_saved_at`

Leaderboard reads are pulled from `public.leaderboard` for:

- `total_plants`
- `balance`
- `xp`

## Practical Notes

- If Supabase config is missing, the game can still run with local save only.
- Keep the root `NEXT_PUBLIC_SUPABASE_*` env values synced with the project used by your auth and database tables before regenerating the runtime config.
