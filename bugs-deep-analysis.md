# Deep Bug Analysis — Gaming Platform (Virtual Harvest)

> **Date:** 2026-04-02
> **Scope:** Full codebase audit — API routes, components, libraries, legacy game engines, middleware, configuration
> **Total bugs:** 31 (team-found) + 27 (newly discovered) = **58 bugs**

---

## PART 1: Deep Analysis of Team-Found Bugs (31)

---

### B-0: Supabase Auth Lock Contention — CONFIRMED CRITICAL

- **File:** Multiple (any code calling `getSession()`)
- **Deep Analysis:** This is the **root cause** of B-1 and cascading auth failures across the platform. The Supabase JS client uses a localStorage-based mutex (`lock:sb-*-auth-token`) with a 5000ms timeout. When multiple components simultaneously call `getSession()` — BanGuard polling every 5s, cloud save/load, profile fetch, playtime flush — they all compete for this single lock. Under load, stolen locks cause silent auth failures that propagate as 401s across all dependent APIs.
- **Blast radius:** Every authenticated feature in the platform is affected. Cloud saves can be silently lost.
- **Fix priority:** P1 — This is the single highest-impact fix. A shared session cache with a single `getSession()` call fanning out to all consumers would eliminate the contention entirely.

### B-1: 401 Errors on `/api/auth/ban-status` and `/api/profile/me` — CONFIRMED CRITICAL

- **File:** `src/components/auth/BanGuard.tsx`, API routes
- **Deep Analysis:** Direct downstream symptom of B-0. BanGuard polls `/api/auth/ban-status` every 5 seconds. Each poll triggers `getSession()`, which competes for the auth lock. When the lock is stolen, the session lookup fails, and the request goes out with no/expired token → 401. The 5s polling interval is aggressive and worsens B-0.
- **Compounding factor:** No circuit breaker — BanGuard keeps polling even after repeated 401s, creating a feedback loop.

### B-2: Unused Preloaded Resources — CONFIRMED LOW

- **Deep Analysis:** Next.js automatically injects `<link rel="preload">` for fonts via `next/font`. If the font loading strategy (`display: swap`) causes a mismatch with the preload timing, Chrome logs warnings. This is cosmetic — no functional impact, but 40 warnings per page load pollute the console and mask real errors.

---

### C-1: `/api/profile/discover` — No Auth, Full DB Enumeration — CONFIRMED CRITICAL

- **File:** `src/app/api/profile/discover/route.ts:13-16`
- **Deep Analysis:** Uses `createServiceSupabaseClient()` which bypasses Row Level Security entirely. Zero authentication check. Any anonymous HTTP request can scrape all usernames, bios, join dates. Combined with no rate limiting, an attacker can enumerate the entire user database in seconds.
- **Attack vector:** `curl /api/profile/discover` — returns all user data, no token needed.

### C-2: `/api/achievements` — No Auth, User Data Exposure — CONFIRMED CRITICAL

- **File:** `src/app/api/achievements/route.ts:4-34`
- **Deep Analysis:** Accepts arbitrary `user_id` query parameter with no auth check. `.select("*")` exposes all columns including internal fields. No rate limiting. An attacker can enumerate all users' achievement data by iterating over user IDs.

### C-3: `rate-limit.ts` — Unbounded Memory Leak — CONFIRMED CRITICAL

- **File:** `src/lib/rate-limit.ts:14-15`
- **Deep Analysis:** The global `Map` store (`__vfRateLimitStore`) creates a new bucket for every unique rate-limit key (IP + endpoint). Buckets are never evicted. In a production server, with thousands of unique IPs hitting rate-limited endpoints, this Map grows linearly over time until the Node.js process runs out of memory and crashes. On Vercel serverless, this is mitigated by function recycling, but on a long-running server it's fatal.

### C-4: `LegacyGameClient` — XSS via `innerHTML` — CONFIRMED CRITICAL

- **File:** `src/components/legacy-game/LegacyGameClient.tsx:123`
- **Deep Analysis:** `host.innerHTML = shellHtml` injects the full contents of `/legacy/index.html` as raw HTML. If the static file is modified (supply chain, CDN compromise, or dev mistake), arbitrary JavaScript executes in the main application context with full access to cookies, localStorage, Supabase tokens, and the parent DOM. No CSP headers are configured to mitigate this.

### C-5: `AdminClient` — Empty Token on Expired Session — CONFIRMED CRITICAL

- **File:** `src/components/admin/AdminClient.tsx:119`
- **Deep Analysis:** `getToken()` returns empty string when session expires. Code sends `Authorization: Bearer ` (empty bearer) without checking. The server may interpret this as an anonymous request rather than an expired session, potentially returning public data instead of a 401. Admin actions silently fail.

---

### H-1: `rate-limit.ts` — IP Spoofing via `x-forwarded-for` — CONFIRMED HIGH

- **File:** `src/lib/rate-limit.ts:56-66`
- **Deep Analysis:** Trusts `x-forwarded-for` without validation. Attacker sends `X-Forwarded-For: 1.2.3.4` with each request using a different spoofed IP to bypass rate limits completely. Every request gets a fresh rate-limit bucket.
- **Compounding issue:** When no IP header is present, the code returns `anon:${crypto.randomUUID()}` — a unique key per request, making rate limiting completely ineffective for those requests.

### H-2: `AdminRoute` — No Rate Limiting on GET — CONFIRMED HIGH

- **File:** `src/app/api/admin/route.ts:44-113`
- **Deep Analysis:** POST operations (ban, delete, spawn items) are rate-limited, but GET operations (user list, admin logs, platform settings) have no rate limiting. An attacker with a stolen admin token can exfiltrate the entire user database and admin log history at maximum speed.

### H-3: `AdminRoute` — SQL Wildcard Injection — CONFIRMED HIGH

- **File:** `src/app/api/admin/route.ts:60`
- **Deep Analysis:** `.ilike("username", \`%${q}%\`)` — if `q` is `%`, it matches ALL usernames. If `q` is `_`, it matches all single-character usernames. Attacker can construct patterns to extract username patterns character by character (blind extraction).

### H-4: `SocialRoute` — All DB Errors Silently Ignored — CONFIRMED HIGH

- **File:** `src/app/api/social/route.ts:27-103`
- **Deep Analysis:** Every Supabase query destructures only `{ data }` and ignores `{ error }`. When the database is down, rate-limited, or queries fail, the endpoint returns `{ followers: [], following: [], blocked: [] }` as if the user has no social connections. Users may think they've been unfollowed/unfriended when the DB is simply failing.

### H-5: `AdminRoute` — `delete_user_data` Leaves Orphaned Records — CONFIRMED HIGH

- **File:** `src/app/api/admin/route.ts:295-330`
- **Deep Analysis:** Only deletes the auth user via `admin.deleteUser()`. Records in `user_profiles`, `follows`, `blocks`, `user_achievements`, `user_game_stats`, `admin_logs` remain. Orphaned records accumulate, pollute leaderboards, and may cause foreign key errors in future queries.

### H-6: `WeatherAnnouncementClient` — localStorage Without Try/Catch — CONFIRMED HIGH

- **File:** `src/components/weather/WeatherAnnouncementClient.tsx:80-86`
- **Deep Analysis:** `localStorage.getItem/setItem` throws `SecurityError` in Safari private browsing and `QuotaExceededError` when storage is full. In private browsing on Safari, this crashes the weather component entirely, potentially breaking the entire page if there's no error boundary.

### H-7: `AuthCallbackClient` — Router Redirect After Unmount — CONFIRMED HIGH

- **File:** `src/components/auth/AuthCallbackClient.tsx:104-106`
- **Deep Analysis:** `setTimeout` at 1200ms fires after the component may have unmounted. `router.replace()` on an unmounted component causes a React warning and potentially a navigation to an unexpected route if the user has already navigated away.

---

### M-1: Admin Error Message Leak — CONFIRMED MEDIUM

- **File:** `src/app/api/admin/route.ts:109-111, 334-336`
- **Analysis:** `err.message` returned directly. Could expose: table names (`relation "user_profiles" does not exist`), column names, Supabase connection strings, or RPC function signatures.

### M-2: Profile PATCH Non-Atomic — CONFIRMED MEDIUM

- **File:** `src/app/api/profile/route.ts:293-319`
- **Analysis:** Username claim (RPC) and profile update (separate query) are not transactional. If the update fails, the username is consumed but other fields are lost. User must re-submit but the username is already taken — by themselves, which they can't know.

### M-3: Profile Public Query Ignores Errors — CONFIRMED MEDIUM

- **File:** `src/app/api/profile/route.ts:234-249`
- **Analysis:** `followersCount` could be `null` instead of `0` when queries fail, causing NaN displays in the UI.

### M-4: Failed Admin Actions Not Audited — CONFIRMED MEDIUM

- **File:** `src/app/api/admin/route.ts:161-170, 231-240`
- **Analysis:** Failed actions (ban, unban, delete) return errors to client but are never logged to `admin_logs`. This creates an audit gap — a malicious admin's failed attempts leave no trace.

### M-5: No Timeout on Script Loading — CONFIRMED MEDIUM

- **File:** `src/components/legacy-game/LegacyGameClient.tsx:68-77`
- **Analysis:** If a CDN or script URL hangs, the loading state stays forever. No timeout, no retry, no fallback.

### M-6: `window.supabase` Never Cleaned Up — CONFIRMED MEDIUM

- **File:** `src/components/legacy-game/LegacyGameClient.tsx:107`
- **Analysis:** `window.supabase` persists after component unmount, leaking the Supabase client instance and potentially causing stale auth state if the component re-mounts with a different user.

### M-7: AccountCenter Script Load Race — CONFIRMED MEDIUM

- **File:** `src/components/account-center/AccountCenterClient.tsx:88-99`
- **Analysis:** If a script element exists and has already fired its `load` event, attaching a listener will never resolve the promise. The component hangs indefinitely.

### M-8: `set_weather` Accepts Arbitrary Conditions — CONFIRMED MEDIUM

- **File:** `src/app/api/admin/route.ts:177-217`
- **Analysis:** No enum validation. An admin could set `condition: "<script>alert(1)</script>"` which would be stored and potentially rendered unsanitized in weather UI.

### M-9: Social Follow Upsert Without `onConflict` — CONFIRMED MEDIUM

- **File:** `src/app/api/social/route.ts:136`
- **Analysis:** Without `onConflict` specification, concurrent "follow" requests can create duplicate rows, inflating follower counts.

### M-10: Leaderboard No Error Handling — CONFIRMED MEDIUM

- **File:** `src/app/api/leaderboard/route.ts:4-18`
- **Analysis:** Bare call with no try/catch. If `fetchLeaderboardModel` throws, the entire route crashes with a 500 and no useful error message.

### M-11: BanGuard Concurrent Checks — CONFIRMED MEDIUM

- **File:** `src/components/auth/BanGuard.tsx:88-128`
- **Analysis:** Focus + visibility + auth change events can all fire within milliseconds, queuing 3+ concurrent ban-status fetches before the 5s cooldown activates. Wastes bandwidth and worsens B-0.

### M-12: SignInFlow Continue Button No Handler — CONFIRMED MEDIUM

- **File:** `src/components/ui/sign-in-flow-1.tsx:555-565`
- **Analysis:** Button visually appears clickable but has no `onClick`. Users clicking it get no response — submission only triggers on the last digit of OTP entry. Confusing UX.

---

### L-1: `isPermanentBan` 10-Year Heuristic — CONFIRMED LOW

- **File:** `src/lib/ban.ts:37-41`
- **Analysis:** A 15-year ban would be classified as "permanent." Minor, but could confuse admins reviewing ban status.

### L-2: `formatScore` Negative Handling — CONFIRMED LOW

- **File:** `src/lib/leaderboard.ts:17`
- **Analysis:** Inconsistent: `bigint` shows negative, `number` is clamped to 0. Edge case — scores shouldn't be negative, but if they are, display is inconsistent.

### L-3: Array Index in `key` Prop — CONFIRMED LOW

- **File:** `src/components/social/FriendsClient.tsx:131`
- **Analysis:** `userId` is unique per tab, making the index redundant and potentially harmful for React reconciliation during list reordering.

### L-4: Unnecessary `useMemo` for Singleton — CONFIRMED LOW

- **File:** `src/components/auth/AuthCallbackClient.tsx:37`
- **Analysis:** `getClientSupabase()` returns a module-level singleton. `useMemo` adds overhead for no benefit.

### L-5: No Sandbox on Iframe — CONFIRMED LOW

- **File:** `src/components/legacy-game/PlayRouteClient.tsx:6-18`
- **Analysis:** Iframe loads legacy game without `sandbox` attribute. Legacy scripts have full access to parent page's origin, cookies, and DOM.

---

## PART 2: Newly Discovered Bugs (27)

---

### CRITICAL

#### N-1: `.env.local` — Secrets Potentially Committed to Git

- **File:** `.env.local`
- **Severity:** CRITICAL
- **Issue:** The `.env.local` file contains `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_SECRET_KEY`, and `SUPABASE_FUNCTIONS_KEY`. If this file has ever been committed to git history, all secrets are compromised even if `.gitignore` now excludes it. The service role key grants full admin access to the database, bypassing all RLS.
- **Fix:** Verify git history with `git log --all --full-history -- .env.local`. If found, rotate ALL keys in Supabase immediately. Use environment injection in deployment (Vercel env vars), never file-based secrets.

#### N-2: No `middleware.ts` — Missing Centralized Security Layer

- **File:** (missing) `src/middleware.ts`
- **Severity:** CRITICAL
- **Issue:** The application has no Next.js middleware. This means there is no centralized enforcement of: authentication on protected routes, CSRF validation, security headers, token refresh, or IP-based blocking. Every API route must individually implement all security checks, and several (C-1, C-2) fail to do so.
- **Fix:** Create `middleware.ts` with auth verification for `/api/*` routes (excluding public endpoints), security header injection, and CSRF token validation.

#### N-3: No CSRF Protection on State-Changing Endpoints

- **Files:** `src/app/api/profile/route.ts` (PATCH), `src/app/api/admin/route.ts` (POST), `src/app/api/social/route.ts` (POST/DELETE)
- **Severity:** CRITICAL
- **Issue:** No CSRF tokens are generated or validated anywhere in the codebase. A malicious website can craft a form that POSTs to `/api/admin` with the user's cookies, performing admin actions (banning users, deleting data) without the admin's knowledge.
- **Fix:** Implement CSRF token middleware using double-submit cookie pattern or Supabase's built-in PKCE flow.

---

### HIGH

#### N-4: No Content-Security-Policy Headers

- **File:** `next.config.ts`
- **Severity:** HIGH
- **Issue:** No security headers are configured in Next.js config or middleware. The application is missing: `Content-Security-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `Strict-Transport-Security`, `Referrer-Policy`. Combined with C-4 (innerHTML injection), this makes XSS exploitation trivial.
- **Fix:** Add security headers in `next.config.ts` `headers()` config or via middleware.

#### N-5: `/social/route.ts` — Missing Authorization on Social Data

- **File:** `src/app/api/social/route.ts`
- **Severity:** HIGH
- **Issue:** Any authenticated user can view anyone else's full followers list, following list, and blocked users list by passing an arbitrary `user_id`. Blocked user lists are especially sensitive — revealing who a user has blocked.
- **Fix:** Restrict blocked list to own user only. Consider privacy settings for followers/following.

#### N-6: `/auth/ban-status` — Authorization Bypass via JWT Extraction

- **File:** `src/app/api/auth/ban-status/route.ts:24-28`
- **Severity:** HIGH
- **Issue:** When `getUser()` fails (expired session), the code extracts `userId` from the JWT payload directly via `extractUserIdFromAccessToken()`. This means a banned user with an expired (but not revoked) JWT can still check their ban status and potentially use the extracted userId to probe other endpoints.
- **Fix:** Require valid session for ban-status checks. If session is invalid, return 401 — the client should handle re-auth.

#### N-7: `farmer-legacy/game.js` — Weather Poll Timer Never Cleared

- **File:** `public/farmer-legacy/game.js:403` and `:251`
- **Severity:** HIGH
- **Issue:** `startWeatherPolling()` creates `weatherPollTimer = setInterval(fetchFarmerWeather, 180000)`. But `stopWeatherPolling()` only clears `weatherResetTimer`, never `weatherPollTimer`. Repeated calls to `startWeatherPolling()` accumulate unclearable intervals, with each one firing `fetchFarmerWeather` every 3 minutes. After 10 restarts, that's 10 concurrent polling loops.
- **Fix:** Clear `weatherPollTimer` in `stopWeatherPolling()`.

#### N-8: `farmer-legacy/ui.js` — 19 Event Listeners Never Removed

- **File:** `public/farmer-legacy/ui.js:447, 491, 812-947`
- **Severity:** HIGH
- **Issue:** 19 `addEventListener` calls across the file with zero corresponding `removeEventListener`. If the UI re-initializes (e.g., navigating away and back), all listeners accumulate. Clicking a button once fires multiple handlers.
- **Fix:** Store listener references and remove them on cleanup, or use `{ once: true }` where appropriate.

#### N-9: `legacy/engine.js` — 18 Event Listeners Never Removed

- **File:** `public/legacy/js/engine.js:544, 656-657, 771-825, 948-1015, 3645-3704`
- **Severity:** HIGH
- **Issue:** 18 `addEventListener` calls (media query, resize, scroll, keyboard, click handlers) with zero cleanup. Same accumulation problem as N-8.
- **Fix:** Implement cleanup pattern for all event listeners.

#### N-10: `farmer-legacy/ui.js` — Uncleared Save Interval

- **File:** `public/farmer-legacy/ui.js:1039`
- **Severity:** HIGH
- **Issue:** `setInterval(saveGame, 30000)` creates a 30-second auto-save loop without storing the interval ID. Cannot be stopped. Continues running even after logout or navigation, potentially saving stale data.
- **Fix:** Store interval ID and clear on page unload/logout.

#### N-11: Timing Attack in Token Verification

- **File:** `src/app/api/auth/exchange/route.ts:64`
- **Severity:** HIGH
- **Issue:** OTP `token_hash` is compared using standard string equality, not constant-time comparison. An attacker can measure response times to determine correct token characters progressively.
- **Fix:** Use `crypto.timingSafeEqual()` for token hash comparison.

---

### MEDIUM

#### N-12: `rate-limit.ts` — Rate Limit Bypass for Unknown IPs

- **File:** `src/lib/rate-limit.ts:60`
- **Severity:** MEDIUM
- **Issue:** When no IP header is found, the function returns `anon:${crypto.randomUUID()}` — a unique key per request. This means requests without IP headers (certain proxies, localhost) completely bypass rate limiting, as each request gets its own fresh bucket.
- **Fix:** Fall back to session ID or user ID when IP is unavailable.

#### N-13: Profile API — User Enumeration

- **File:** `src/app/api/profile/route.ts:239-245`
- **Severity:** MEDIUM
- **Issue:** The public profile GET endpoint allows case-insensitive username lookup. An attacker can enumerate all valid usernames by iterating common names and checking for 200 vs 404 responses. No rate limiting on this endpoint.
- **Fix:** Add rate limiting, consider CAPTCHA for repeated lookups.

#### N-14: Profile PATCH — No Rate Limiting

- **File:** `src/app/api/profile/route.ts:277+`
- **Severity:** MEDIUM
- **Issue:** Profile update endpoint has no rate limiting. An attacker with a valid session can spam profile updates, potentially causing database load or abusing the username claim RPC.
- **Fix:** Add rate limiting (e.g., 10 updates per minute).

#### N-15: Profile PATCH — Weak Username Validation

- **File:** `src/app/api/profile/route.ts:288`
- **Severity:** MEDIUM
- **Issue:** Username accepted with only `.slice(0, 500)` length check. No character whitelist, no regex validation. Usernames could contain HTML entities, zero-width characters, Unicode lookalikes (homograph attacks), or SQL-significant characters.
- **Fix:** Validate against `^[a-zA-Z0-9_-]{3,30}$` or similar whitelist pattern.

#### N-16: `AdminClient.tsx` — useEffect Missing Dependency

- **File:** `src/components/admin/AdminClient.tsx:58-60`
- **Severity:** MEDIUM
- **Issue:** `useEffect` has `[submittedSearchQ]` in its dependency array but operates on `submittedSearchQRef`. The ref update doesn't trigger re-runs, creating a stale reference that causes search to show outdated results.
- **Fix:** Use state instead of ref, or restructure the effect logic.

#### N-17: `AdminClient.tsx` — Race Condition with AbortController

- **File:** `src/components/admin/AdminClient.tsx:62-104`
- **Severity:** MEDIUM
- **Issue:** Rapid tab switches can interleave fetch requests. While AbortController is used, the abort and new controller creation aren't atomic — a small window exists where two requests can be in-flight simultaneously.
- **Fix:** Ensure abort completes before initiating new request.

#### N-18: `WeatherAnnouncementClient.tsx` — Realtime Subscription Leak

- **File:** `src/components/weather/WeatherAnnouncementClient.tsx:155-179`
- **Severity:** MEDIUM
- **Issue:** Supabase realtime subscription cleanup only triggers when `suppressOnPage` changes. If the component unmounts for other reasons, the subscription persists, consuming resources and potentially firing callbacks on an unmounted component.
- **Fix:** Move subscription cleanup to the effect's cleanup function unconditionally.

#### N-19: `SignInFlow` — Uncleared Timeouts

- **File:** `src/components/ui/sign-in-flow-1.tsx:386-387`
- **Severity:** MEDIUM
- **Issue:** Two `setTimeout` calls in `handleCodeChange` are never cleared. If the component unmounts during the animation timeout, state updates fire on an unmounted component.
- **Fix:** Store timeout IDs in refs, clear them in cleanup.

#### N-20: `farmer-legacy/supabase/client.js` — Race Condition in signIn

- **File:** `public/farmer-legacy/supabase/client.js:296-318`
- **Severity:** MEDIUM
- **Issue:** After sign-in, a hardcoded `setTimeout(150ms)` attempts to read bridge state. If the bridge isn't ready within 150ms (slow network, heavy page), `farmerUser` remains null despite successful auth. No retry mechanism.
- **Fix:** Use event-based synchronization or retry with exponential backoff.

#### N-21: `farmer-legacy/supabase/client.js` — Save Race Condition

- **File:** `public/farmer-legacy/supabase/client.js:403-410`
- **Severity:** MEDIUM
- **Issue:** `flushQueuedSave()` checks `saveInFlight` flag, but multiple near-simultaneous calls can pass the check before the flag is set (time-of-check vs time-of-use). Can result in duplicate save requests or lost queued snapshots.
- **Fix:** Use a promise-based queue pattern.

#### N-22: `farmer-legacy/ui.js` — XSS via innerHTML (8 Locations)

- **File:** `public/farmer-legacy/ui.js:389, 429, 473, 527, 584, 615, 768, 787`
- **Severity:** MEDIUM
- **Issue:** Template literals injected into `innerHTML` at 8 locations. While some paths use `escapeHtml()`, not all do. If game data (plant names, fertilizer names) ever contains user-controlled content or is modified via a compromised API, XSS is possible.
- **Fix:** Use `textContent` for text, `createElement` for DOM structure. Apply `escapeHtml()` consistently.

#### N-23: `useAuth` Hook — Stale Closure Risk

- **File:** `src/hooks/useAuth.ts:18-30`
- **Severity:** MEDIUM
- **Issue:** The `getSession()` promise can resolve after unmount. While the `mounted` flag exists, rapid auth state changes can cause state update stacking. The `onAuthStateChange` subscription fires synchronously but `getSession` is async, creating a window where state is inconsistent.
- **Fix:** Add explicit cancellation token for the `getSession()` promise chain.

#### N-24: `localStorage` Without Try/Catch — Additional Locations

- **Files:** `src/components/auth/BanGuard.tsx:10,56,70,100,142` and `src/components/onboarding/OnboardingFlow.tsx:58,74,116`
- **Severity:** MEDIUM
- **Issue:** Extends H-6 to two additional components. BanGuard stores ban state in localStorage (10+ access points). OnboardingFlow stores onboarding progress. All crash in Safari private browsing.
- **Fix:** Create a safe localStorage wrapper with try/catch that returns defaults on failure.

#### N-25: `farmer-legacy/supabase/client.js` — Playtime Interval Never Cleared

- **File:** `public/farmer-legacy/supabase/client.js:227`
- **Severity:** MEDIUM
- **Issue:** `playtimeIntervalId = window.setInterval(...)` tracks playtime but is never cleared on logout or page transition. Continues accumulating playtime even when the user isn't actively playing.
- **Fix:** Clear interval on logout/navigation, verify game is active before incrementing.

#### N-26: Missing Secure Cookie Configuration

- **File:** (configuration-level)
- **Severity:** MEDIUM
- **Issue:** No explicit cookie configuration for Supabase auth. Default Supabase JS client stores tokens in localStorage (not cookies), but if cookies are used for SSR, they may lack `HttpOnly`, `Secure`, and `SameSite` flags.
- **Fix:** Audit cookie settings in Supabase client configuration. Ensure `Secure` and `SameSite=Lax` at minimum.

---

## PART 3: Updated Summary

| Severity | Team Bugs | New Bugs | Total | IDs |
|----------|-----------|----------|-------|-----|
| **Critical** | 7 | 3 | **10** | B-0, B-1, C-1–C-5, N-1, N-2, N-3 |
| **High** | 7 | 8 | **15** | H-1–H-7, N-4–N-11 |
| **Medium** | 12 | 15 | **27** | M-1–M-12, N-12–N-26 |
| **Low** | 5 | 1 | **6** | L-1–L-5, B-2 |
| **Total** | **31** | **27** | **58** | |

---

## PART 4: Updated Priority Matrix

| Priority | Bugs | Rationale |
|----------|------|-----------|
| **P0 — Immediate** | C-1, C-2, C-4, N-1, N-2, N-3 | Active security vulnerabilities: data exposure, XSS, CSRF, potential secret leak |
| **P1 — Urgent** | B-0, B-1, C-3, H-1, H-4, N-4, N-11 | Root cause of cascading failures, memory leak, missing security headers, timing attack |
| **P2 — High** | C-5, H-2, H-3, H-5, H-7, N-5, N-6, N-7, N-8, N-9, N-10 | Security hardening, data integrity, resource leaks in legacy code |
| **P3 — Medium** | H-6, M-1–M-12, N-12–N-26 | Reliability, correctness, additional localStorage/leak fixes |
| **P4 — Low** | B-2, L-1–L-5 | Cosmetic, edge cases, minor polish |

---

## PART 5: Systemic Issues

Beyond individual bugs, the codebase has several **architectural patterns** that produce bugs:

1. **No centralized auth enforcement** — Each API route independently implements auth checks. When one forgets (C-1, C-2), there's no safety net. A `middleware.ts` would prevent entire categories of bugs.

2. **No security headers anywhere** — CSP, HSTS, X-Frame-Options are all absent. Combined with multiple innerHTML/XSS vectors, this is a systemic vulnerability.

3. **Inconsistent Supabase client usage** — Some routes use service client (bypasses RLS), some use anon client. No clear pattern for when each is appropriate.

4. **No error propagation strategy** — Some routes swallow errors (H-4), some leak them (M-1). No unified error handling middleware.

5. **Legacy code has zero cleanup** — Both `farmer-legacy` and `legacy` engines create intervals, timeouts, and event listeners without any cleanup mechanism. This is the source of 37+ resource leaks.

6. **Rate limiting is structurally broken** — IP spoofing (H-1), random UUID fallback (N-12), memory leak (C-3), and missing coverage (H-2, N-14) mean the rate limiter provides false security.
