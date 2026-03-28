# Gaming Platform (Virtual Harvest)

Last updated: March 28, 2026

This repo is the “platform shell” that ties two browser games together:

- Virtual Fisher (served from `public/legacy`)
- Virtual Farmer (served from `public/farmer-legacy`)

The vibe: sign in once, land on a single home hub, then jump between fishing and farming without hopping sites. On top of that, the platform adds a layer of social + progression stuff around the games (profile, friends, achievements, shop, chat, and a public leaderboard).

## What’s In The Platform

- **Landing page** (`/`) that introduces the platform and links to the hub.
- **Account home / launcher** (`/home`) where you log in, see link status for both games, and launch either world.
- **Game shell routes** that embed the legacy runtimes:
  - `/fish` loads `/legacy/index.html`
  - `/farm` loads `/farmer-legacy/game.html`
- **Community features**:
  - `/leaderboard` for the public leaderboard
  - `/chat` for the global chat (history is intentionally short; recent messages only)
  - `/friends`, `/profile`, `/profile/[username]`, `/search`
  - `/achievements`
- **Shop** (`/shop`) for spending coins on gear and upgrades.

## Quick Start (Local Dev)

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

## Using It Offline

There are two “offline” levels depending on what you want.

1. **Offline for gameplay (recommended):** run the app locally and just use the legacy games.
   - Start the dev server (`npm run dev`) or a production server (`npm run build` then `npm run start`).
   - Visit `/fish` or `/farm`.
   - The platform pages will still load, but features that rely on server data (sign-in, profiles, leaderboards, chat, shop, admin) may be limited or show “signed out / unavailable” messages if you haven’t configured backend credentials.

2. **Offline as pure static HTML:** serve the legacy builds directly.
   - Start a simple static server pointed at `public/` (pick one):
     - `npx serve public -l 3000`
     - `python -m http.server 3000 --directory public`
   - Open:
     - `http://localhost:3000/legacy/index.html`
     - `http://localhost:3000/farmer-legacy/game.html`

Tip: opening the HTML files via `file://` can break things like workers, audio loading, or fetches in some browsers. A local server is the safest “offline” setup.

## Main Routes

| Route | What it’s for |
|---|---|
| `/` | Landing page |
| `/home` | Account home + launcher |
| `/fish` | Launch Virtual Fisher |
| `/farm` | Launch Virtual Farmer |
| `/leaderboard` | Public leaderboard |
| `/chat` | Global chat |
| `/friends` | Friends/following UI |
| `/profile` | Your profile |
| `/profile/[username]` | Public profile page |
| `/search` | Player + content search |
| `/shop` | Item shop |
| `/achievements` | Achievements UI |
| `/admin` | Admin panel (intended for internal use) |

## Folder Guide

- `src/app`: Next.js routes (pages + API routes)
- `src/components`: UI and client components (hub, game shell, chat, onboarding, etc.)
- `src/lib`: shared helpers/models
- `public/legacy`: Virtual Fisher static runtime
- `public/farmer-legacy`: Virtual Farmer static runtime
- `virtual-farmer`: standalone/dev copy of the farmer runtime sources
- `virtual-fisher`: standalone/dev copy of the fisher runtime sources

## Notes

- This is intentionally a hybrid: modern platform UI plus legacy game runtimes embedded in a shell.
- There isn’t a full automated test suite at the root yet, so changes are typically validated by running the app locally and clicking through the main flows.
