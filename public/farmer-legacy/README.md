# Virtual Farmer (Next.js Served Legacy Copy)

Last updated: March 15, 2026

This folder is the Virtual Farmer build served by the root Next.js app under `/farmer-legacy/*`.

It mirrors the standalone Virtual Farmer gameplay loop, but this copy is tuned for platform hosting.

## Current Status

What is working right now:

- Core loop: farm, collect plants, sell inventory for money
- Progression systems: hoes, fertilizers, upgrades, XP, achievements, prestige
- Auto Farm mode with background ticking
- Offline Auto Farm catch-up capped at 24 hours
- Email/password login and signup pages with inline password checks
- Cloud save and load through Supabase (`player_progress`)
- Leaderboard tabs for total plants, balance, and XP
- Local/cloud conflict handling by comparing save timestamps

## Page Flow

- `index.html` redirects to `game.html`
- `game.html` is the main app
- `login.html` and `signup.html` handle authentication

When Supabase is configured, `game.html` requires auth and redirects to login if the user is signed out.

## Local Run (without Next.js)

You can still run this folder as plain static files:

```bash
python -m http.server 8080
```

Then open `http://localhost:8080/game.html`.

## Supabase Setup

1. Create a Supabase project.
2. Run `supabase/001_progress_schema.sql` in Supabase SQL Editor.
3. Set `window.__SUPABASE_CONFIG__` in `supabase/config.js` with your project URL and anon key.
4. Enable Email auth provider in Supabase Auth.
5. If email confirmation is enabled, verify the email before first login.

## Save and Sync Behavior

Local storage keys:

- `virtualFarmerSave`
- `autoFarmState`
- `virtualFarmerSupabaseConfig`

Behavior summary:

- Local save on gameplay actions plus autosave every 30 seconds
- Cloud saves are queued/debounced and flushed on important actions
- Cloud load happens on startup for authenticated users
- Newer timestamp wins when local and cloud snapshots differ

## Platform Hosting Differences

Compared with `virtual-farmer/`:

- Supabase JS is loaded from `/vendor/supabase/supabase.js` (not CDN)
- Account bridge script is expected at `/platform-account-bridge.js` from root `public/`
- This copy is the one embedded by route `/farm`

## File Map

- `data.js`: plants, hoes, fertilizers, upgrades, achievements
- `game.js`: gameplay, prestige, auto-farm, save/load, cloud merge logic
- `ui.js`: rendering, tabs/modals, leaderboard UI, auth state display
- `auth.js`: login/signup validation and auth form flow
- `supabase/client.js`: Supabase wrapper and cloud operations
- `supabase/001_progress_schema.sql`: schema, triggers, RLS, leaderboard view
