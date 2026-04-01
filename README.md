# Virtual Harvest

Last updated: April 1, 2026

This repo is the current web home for Virtual Harvest: a Next.js platform that unifies Virtual Fisher and Virtual Farmer behind one consistent route system, one account layer, and one shared profile/community surface.

The goal is simple: use `/home` as the real front door, move account-specific tools into `/account-center`, keep `/fish` and `/farm` as direct game routes, and stop treating the platform as two disconnected website systems.

## What Changed In This Version

- `/home` is the canonical platform home.
- `/account-center` now holds sign-in, linking, sign-out, and onboarding.
- `/` redirects to `/home`.
- `/fish` and `/farm` are the main play routes now. The older `/play` and `/farmer` paths stick around as redirects so old links do not feel broken.
- Profiles are shared across the platform. Players get one username, one profile note, one account page, and a public profile route at `/profile/[username]`.
- Social features are split into their own page at `/friends`, with views for friends, followers, following, and blocked users.
- `/leaderboard` is a standalone page with live refreshing boards instead of a tucked-away extra.
- `/achievements` now has its own filtered tracker with unlock counts and XP totals.
- There is also an `/admin` dashboard for moderation and support work.

## Main Routes

- `/` - redirect to `/home`
- `/home` - platform home
- `/account-center` - account access, linking, and onboarding
- `/fish` - Virtual Fisher in the embedded runtime shell
- `/farm` - Virtual Farmer in the embedded runtime shell
- `/leaderboard` - live leaderboard page
- `/friends` - social connections page
- `/profile` - your own account profile
- `/profile/[username]` - public player profile
- `/achievements` - achievements tracker
- `/admin` - admin dashboard
- `/play` - redirect to `/fish`
- `/farmer` - redirect to `/farm`

## Local Dev

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

Useful scripts:

```bash
npm run build-supabase-baseline
npm run sync-public-auth-config
npm run build
npm run start
npm run lint
```

## Supabase Setup

For a brand-new Supabase project or a full database reset, use `supabase/virtual_harvest_fresh_setup.sql`.

Recommended flow:

```bash
npm run build-supabase-baseline
```

Then paste `supabase/virtual_harvest_fresh_setup.sql` into the Supabase SQL Editor and run it once on the empty database.

Use `supabase/migrations/` for migration history and incremental updates. Do not delete those files just because you now have a fresh-start SQL bundle. Existing environments still rely on migration history.

Auth settings to verify after the SQL is applied:

- Site URL: your deployed app origin, such as `https://virtual-game-theta.vercel.app`
- Redirect URL: `https://virtual-game-theta.vercel.app/auth/callback`
- Public env keys: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- Server env key: `SUPABASE_SERVICE_ROLE_KEY`

## Using It Offline

There are two practical offline setups.

### 1. Run the full site locally

This is the best option if you want the actual website shell, route structure, and launcher flow.

```bash
npm install
npm run dev
```

Then open `http://localhost:3000`.

What still works well in this mode:

- the platform home
- the account center layout
- the embedded Fisher and Farmer routes
- the shipped game runtime files themselves

What may stay unavailable unless you add your own local account-sync setup:

- sign-in and account linking
- public profile data
- friends and follow actions
- live leaderboard updates
- achievement sync
- admin actions

### 2. Serve the game runtimes directly

If you only want the original game runtimes without the Next.js shell around them, serve `public/` as static files:

```bash
npm run sync-public-auth-config
npx serve public -l 3000
```

Then open:

- `http://localhost:3000/legacy/index.html`
- `http://localhost:3000/farmer-legacy/game.html`

Avoid opening the HTML files with `file://`. A small local server is the safer option because workers, fetch calls, and a few browser APIs are much less fragile there.

For auth-enabled static serving, `npm run sync-public-auth-config` generates `public/runtime-supabase-config.js` from your local `NEXT_PUBLIC_SUPABASE_*` env values before you launch the static server.

## Project Layout

- `src/app` - Next.js routes and route-level styling
- `src/components` - account, profile, leaderboard, admin, onboarding, and game shell UI
- `src/lib` - shared client and server helpers
- `supabase` - Supabase migrations, fresh-start SQL bundle, and edge functions
- `public/legacy` - shipped Virtual Fisher runtime
- `public/farmer-legacy` - shipped Virtual Farmer runtime
- `virtual-fisher` - working source copy for Fisher
- `virtual-farmer` - working source copy for Farmer

## Notes

- This repo intentionally keeps the shipped Fisher and Farmer runtimes alongside the Next.js platform shell.
- The website is easiest to verify by running it locally and clicking through `/home`, `/account-center`, `/fish`, and `/farm`.
- `npm run lint` is the main lightweight validation command available at the root right now.
