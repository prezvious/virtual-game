# Gaming Platform (Virtual Harvest)

Last updated: March 15, 2026

This repo is the active Next.js platform shell for two browser games:

- Virtual Fisher (served from `public/legacy`)
- Virtual Farmer (served from `public/farmer-legacy`)

The main idea is simple: one account center, two game worlds, and shared launch/navigation from the same web app.

## Current System Snapshot

- Runtime checked locally: Node `v24.14.0`, npm `11.9.0`
- Root app stack: Next.js `16.1.6`, React `19.2.3`, TypeScript
- Root package name: `virtual-fisher-next`
- Active routes launch legacy builds in iframes:
  - Fisher iframe source: `/legacy/index.html`
  - Farmer iframe source: `/farmer-legacy/game.html`
- Fisher data pack currently loaded from `public/legacy`:
  - 60 biome files
  - 30 weather definitions
  - 15 rods
  - 14 base baits

## Quick Start

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

Other useful scripts:

```bash
npm run build
npm run start
npm run lint
```

## App Routes

| Route | Purpose |
|---|---|
| `/` | Landing page |
| `/home` | Unified account center and game launcher |
| `/fish` | Launches Virtual Fisher legacy game |
| `/farm` | Launches Virtual Farmer legacy game |
| `/leaderboard` | Public leaderboard page (money + fish) |
| `/auth/callback` | Completes auth callback/token exchange |
| `/play` | Redirects to `/fish` |
| `/farmer` | Redirects to `/farm` |

## API Routes

| Route | Method | What it does |
|---|---|---|
| `/api/leaderboard` | `GET` | Returns leaderboard model for UI polling |
| `/api/auth/exchange` | `POST` | Exchanges Supabase auth `code` or `token_hash` for a session |
| `/api/alerts` | `POST` | Rate-limited alert forwarder to Supabase Edge Function `send-alert` |

Rate limits currently in code:

- Auth exchange: 20 requests per 5 minutes per IP
- Alerts: 10 requests per minute per IP
- Duplicate alert signature throttle: 3 per minute

## Environment Variables

Use these in `.env.local` for local development:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_FUNCTIONS_KEY` (preferred for `/api/alerts`)
- `SUPABASE_SERVICE_ROLE_KEY` (fallback for `/api/alerts`)
- `SUPABASE_SEND_ALERT_URL` (optional override for alert forward URL)

Notes:

- `src/lib/supabase.ts` has baked fallback values, but you should set your own env vars for real deployments.
- `/api/alerts` returns 500 if no usable key is configured.

## Supabase Migrations (Root App)

If you are provisioning a fresh database for the platform side, run SQL files in `supabase/migrations` in filename order:

1. `20260308_create_game_saves.sql`
2. `20260309_usernames_and_leaderboards.sql`
3. `20260309_fix_username_underscore_validation.sql`
4. `20260309_leaderboard_access_and_manual_refresh.sql`
5. `20260313_add_fish_catalog_and_leaderboard_bigint_safety.sql`
6. `20260315_leaderboards_include_zero_scores.sql`
7. `20260315_virtual_farmer_schema_compatibility.sql`
8. `20260315_farmer_leaderboard_snapshot_refresh.sql`
9. `20260315_fisher_leaderboard_refresh_20_minutes.sql`

These migrations define the game save table, username/profile rules, leaderboard snapshots + refresh functions, and fish catalog data.

## Folder Guide

- `src/app`: Next.js routes and API handlers
- `src/components`: platform hub, iframe shell, leaderboard UI, auth callback client
- `src/lib`: Supabase helpers, leaderboard fetch model, in-memory rate limit helper
- `public/legacy`: Virtual Fisher static runtime
- `public/farmer-legacy`: Virtual Farmer static runtime used by `/farm`
- `virtual-farmer`: standalone/development copy of Virtual Farmer sources
- `virtual-fisher/nextjs-scaffold`: archived plain scaffold reference
- `supabase/functions/send-alert`: edge function used by `/api/alerts`

## Important Notes

- Legacy/static directories are intentionally ignored by root ESLint config.
- `virtual-farmer` and `public/farmer-legacy` are similar but not identical deployment targets.
- There is no automated test suite in the root app yet.
