# Virtual Harvest

Last updated: April 1, 2026

This repo is the current web home for Virtual Harvest: a Next.js launcher site that wraps both legacy games in one shared platform. The idea is simple: land on one site, sign in once, open either world, and keep the account-facing parts of the experience in one place instead of bouncing between separate builds.

The site is no longer just a thin shell around old files. It now has a real landing page, a proper account home, dedicated launcher routes for both games, player profile pages, social pages, achievements, a live leaderboard, and an admin surface for platform management.

## What Changed In This Version

- The landing page at `/` is now the front door for the whole project instead of a placeholder.
- `/home` works like the main account center. It shows account status, linked game state, and launch points for Fisher and Farmer.
- `/fish` and `/farm` are the main play routes now. The older `/play` and `/farmer` paths stick around as redirects so old links do not feel broken.
- Profiles are shared across the platform. Players get one username, one profile note, one account page, and a public profile route at `/profile/[username]`.
- Social features are split into their own page at `/friends`, with views for friends, followers, following, and blocked users.
- `/leaderboard` is a standalone page with live refreshing boards instead of a tucked-away extra.
- `/achievements` now has its own filtered tracker with unlock counts and XP totals.
- There is also an `/admin` dashboard for moderation and support work.

## Main Routes

- `/` - landing page
- `/home` - account hub and launcher
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
npm run sync-public-auth-config
npm run build
npm run start
npm run lint
```

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

- the landing page
- the account home layout
- the embedded Fisher and Farmer routes
- the legacy game files themselves

What may stay unavailable unless you add your own local account-sync setup:

- sign-in and account linking
- public profile data
- friends and follow actions
- live leaderboard updates
- achievement sync
- admin actions

### 2. Serve the legacy games directly

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
- `public/legacy` - shipped Virtual Fisher runtime
- `public/farmer-legacy` - shipped Virtual Farmer runtime
- `virtual-fisher` - working source copy for Fisher
- `virtual-farmer` - working source copy for Farmer

## Notes

- This repo intentionally keeps the legacy game runtimes alongside the newer Next.js shell.
- The website is easiest to verify by running it locally and clicking through the main routes.
- `npm run lint` is the main lightweight validation command available at the root right now.
