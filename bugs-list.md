# Bug List — Gaming Platform

## Bugs from `bugs.md` (Console Errors)

### B-0: Supabase Auth Lock Contention
- **Severity:** Critical
- **Symptoms:** `Lock "lock:sb-clgzhgczlafvuagbwapk-auth-token" was not released within 5000ms`, `Lock was released because another request stole it` — cascading failures across profile load, cloud save, cloud load, playtime flush
- **Root cause:** Multiple concurrent Supabase auth operations (each calling `getSession()` internally) compete for the same localStorage-based auth token lock
- **Fix:** Implement a request queue for Supabase auth operations; batch cloud operations; reuse a single `getSession()` token across multiple operations instead of each operation acquiring the lock independently; add retry logic with exponential backoff for lock failures

### B-1: 401 Errors on `/api/auth/ban-status` and `/api/profile/me`
- **Severity:** Critical
- **Symptoms:** Repeated `401` responses on `api/auth/ban-status` and `api/profile/me`
- **Root cause:** Token expiration during page lifetime; lock contention (B-0) causing auth failures; ban-status polling every 5s with no session refresh
- **Fix:** Add automatic token refresh before API calls; stop polling ban-status when session is invalid; fix lock contention (B-0)

### B-2: Unused Preloaded Resources
- **Severity:** Low
- **Symptoms:** 40× "resource was preloaded using link preload but not used within a few seconds"
- **Root cause:** Next.js font preload hints or legacy game system preloading resources that aren't consumed
- **Fix:** Review `next.config.ts` for preload configurations; remove unnecessary `<link rel="preload">` tags from public HTML; ensure font loading strategy is consistent

---

## Discovered Code Bugs

### C-1: `/api/profile/discover` — No Authentication, Full DB Enumeration
- **File:** `src/app/api/profile/discover/route.ts:13-16`
- **Severity:** Critical
- **Issue:** Uses `createServiceSupabaseClient()` (bypasses RLS) with zero auth check. Any unauthenticated user can scrape all usernames, bios, and join dates.
- **Fix:** Add authentication requirement or switch to anon client with proper RLS policies.

### C-2: `/api/achievements` — No Authentication, User Data Exposure
- **File:** `src/app/api/achievements/route.ts:4-34`
- **Severity:** Critical
- **Issue:** Zero auth check. Anyone can query any user's achievement progress by passing arbitrary `user_id` values. Also no rate limiting. Uses `.select("*")` exposing all columns.
- **Fix:** Add auth check for user-specific data, rate limit the endpoint, use explicit column selection instead of `.select("*")`.

### C-3: `rate-limit.ts` — Unbounded Memory Leak
- **File:** `src/lib/rate-limit.ts:14-15`
- **Severity:** Critical
- **Issue:** The `Map` store never evicts expired entries. In a long-running server, this grows unboundedly, eventually causing memory exhaustion.
- **Fix:** Add periodic cleanup of expired buckets via `setInterval`, or use a TTL-based cache (e.g., `lru-cache`).

### C-4: `LegacyGameClient` — XSS via `innerHTML` Injection
- **File:** `src/components/legacy-game/LegacyGameClient.tsx:123`
- **Severity:** Critical
- **Issue:** `host.innerHTML = shellHtml` injects raw HTML from `/legacy/index.html` without sanitization. If the legacy content is compromised, this is direct XSS.
- **Fix:** Add Content Security Policy headers, validate/sanitize the HTML, or use an iframe sandbox instead of innerHTML injection.

### C-5: `AdminClient` — Empty Token Sent on Expired Session
- **File:** `src/components/admin/AdminClient.tsx:119`
- **Severity:** Critical
- **Issue:** `getToken()` can return an empty string when the session expires, and the code sends `Authorization: Bearer ` without validation.
- **Fix:** Guard against empty tokens before the fetch call; redirect to sign-in if token is missing.

---

### H-1: `rate-limit.ts` — IP Spoofing via `x-forwarded-for`
- **File:** `src/lib/rate-limit.ts:56-66`
- **Severity:** High
- **Issue:** Trusts `x-forwarded-for` header without validation. Attackers can spoof IPs to bypass rate limits.
- **Fix:** Use `req.ip` (Next.js provides this) or validate the header against known proxy IPs.

### H-2: `AdminRoute` — No Rate Limiting on GET Endpoints
- **File:** `src/app/api/admin/route.ts:44-113`
- **Severity:** High
- **Issue:** POST has rate limiting but GET (users list, logs, settings) has none. Admin endpoints can be spammed.
- **Fix:** Add rate limiting to GET handlers.

### H-3: `AdminRoute` — SQL Wildcard Injection in Search
- **File:** `src/app/api/admin/route.ts:60`
- **Severity:** High
- **Issue:** `.ilike("username", `%${q}%`)` — special characters like `%` and `_` in the search query are interpreted as SQL wildcards. Searching for `%` matches all usernames.
- **Fix:** Escape wildcard characters: `q.replace(/[%_\\]/g, '\\$&')`.

### H-4: `SocialRoute` — All DB Errors Silently Ignored in GET
- **File:** `src/app/api/social/route.ts:27-103`
- **Severity:** High
- **Issue:** Every Supabase query in the GET handler destructures only `data` and ignores `error`. Failed queries return empty arrays as if the user has no data.
- **Fix:** Check `error` on each query and return appropriate error responses.

### H-5: `AdminRoute` — `delete_user_data` Leaves Orphaned Records
- **File:** `src/app/api/admin/route.ts:295-330`
- **Severity:** High
- **Issue:** `deleteUser()` only removes the auth user. Related records in `user_profiles`, `follows`, `blocks`, `user_achievements`, `user_game_stats`, `admin_logs` are not cleaned up.
- **Fix:** Add cascade deletes for all related tables, or use database-level `ON DELETE CASCADE` constraints.

### H-6: `WeatherAnnouncementClient` — localStorage Without Try/Catch
- **File:** `src/components/weather/WeatherAnnouncementClient.tsx:80-86`
- **Severity:** High
- **Issue:** `localStorage.getItem/setItem` can throw `SecurityError` in private browsing or `QuotaExceededError` when storage is full, crashing the component.
- **Fix:** Wrap all localStorage calls in try/catch.

### H-7: `AuthCallbackClient` — Router Redirect After Unmount
- **File:** `src/components/auth/AuthCallbackClient.tsx:104-106`
- **Severity:** High
- **Issue:** The `setTimeout` callback at 1200ms does not re-check the `mounted` flag before calling `router.replace()`.
- **Fix:** Check `mounted` inside the timeout callback.

---

### M-1: `AdminRoute` — Error Messages Leak Internal Details
- **File:** `src/app/api/admin/route.ts:109-111, 334-336`
- **Severity:** Medium
- **Issue:** Catch blocks return `err.message` directly to clients, potentially exposing table names, column names, or Supabase internals.
- **Fix:** Return generic error messages to clients; log full details server-side only.

### M-2: `ProfileRoute` — PATCH Username Claim and Profile Update Not Atomic
- **File:** `src/app/api/profile/route.ts:293-319`
- **Severity:** Medium
- **Issue:** Username claim via RPC and profile field update are separate queries. If the update fails after a successful claim, the username is claimed but other changes are lost.
- **Fix:** Wrap in a transaction or use an idempotent approach.

### M-3: `ProfileRoute` — Public Profile Query Ignores Errors
- **File:** `src/app/api/profile/route.ts:234-249`
- **Severity:** Medium
- **Issue:** `followersCount` and `followingCount` could be `null` instead of `0` when queries fail.
- **Fix:** Use `count ?? 0` fallback and log errors.

### M-4: `AdminRoute` — Failed Admin Actions Not Audited
- **File:** `src/app/api/admin/route.ts:161-170, 231-240`
- **Severity:** Medium
- **Issue:** When RPC calls fail, the error is returned to the client but not logged to `admin_logs`.
- **Fix:** Log failed admin actions with error details.

### M-5: `LegacyGameClient` — No Timeout on Script Loading
- **File:** `src/components/legacy-game/LegacyGameClient.tsx:68-77`
- **Severity:** Medium
- **Issue:** Script loading promises have no timeout. If a legacy script URL hangs, the component stays in "Booting..." forever.
- **Fix:** Add a timeout (e.g., 15s) to script loading promises.

### M-6: `LegacyGameClient` — `window.supabase` Never Cleaned Up
- **File:** `src/components/legacy-game/LegacyGameClient.tsx:107`
- **Severity:** Medium
- **Issue:** `window.supabase` is assigned but never cleaned up in the useEffect cleanup function.
- **Fix:** Delete `window.supabase` in the cleanup function.

### M-7: `AccountCenterClient` — Event Listeners on Pre-existing Scripts May Never Resolve
- **File:** `src/components/account-center/AccountCenterClient.tsx:88-99`
- **Severity:** Medium
- **Issue:** When attaching `load`/`error` listeners to existing script elements, if the script already loaded, the promise never resolves.
- **Fix:** Check `script.readyState === "complete"` before adding listeners.

### M-8: `AdminRoute` — `set_weather` Accepts Arbitrary Condition Strings
- **File:** `src/app/api/admin/route.ts:177-217`
- **Severity:** Medium
- **Issue:** `condition` defaults to `"clear"` with no validation against allowed values. An admin could set an arbitrary condition string the client can't render.
- **Fix:** Validate against an enum of valid conditions.

### M-9: `SocialRoute` — Follow Upsert Without `onConflict`
- **File:** `src/app/api/social/route.ts:136`
- **Severity:** Medium
- **Issue:** `.upsert()` without `onConflict` specification could create duplicate rows under concurrent requests.
- **Fix:** Add `onConflict: "follower_id,following_id"` or use insert with conflict handling.

### M-10: `LeaderboardRoute` — No Error Handling, No Pagination
- **File:** `src/app/api/leaderboard/route.ts:4-18`
- **Severity:** Medium
- **Issue:** `fetchLeaderboardModel(10)` has no try/catch. Hardcoded limit of 10 with no pagination support.
- **Fix:** Add try/catch, support `limit` and `offset` query params.

### M-11: `BanGuard` — Concurrent `checkBanStatus` Calls
- **File:** `src/components/auth/BanGuard.tsx:88-128`
- **Severity:** Medium
- **Issue:** Multiple rapid triggers (focus + visibility + auth change) can queue multiple fetch calls before the 5s cooldown takes effect.
- **Fix:** Add an in-flight flag (`isCheckingRef`) to prevent concurrent checks.

### M-12: `SignInFlow` — Continue Button Has No Click Handler
- **File:** `src/components/ui/sign-in-flow-1.tsx:555-565`
- **Severity:** Medium
- **Issue:** The "Continue" button appears actionable but does nothing — submission only triggers on the last digit entry.
- **Fix:** Wire the button to call the same submission handler.

---

### L-1: `ban.ts` — `isPermanentBan` Uses Heuristic 10-Year Threshold
- **File:** `src/lib/ban.ts:37-41`
- **Severity:** Low
- **Issue:** Bans >10 years in the future are classified as permanent, which could misclassify very long temporary bans.
- **Fix:** Use an explicit `is_permanent` flag from the database instead of a time heuristic.

### L-2: `leaderboard.ts` — `formatScore` Inconsistent Negative Handling
- **File:** `src/lib/leaderboard.ts:17`
- **Severity:** Low
- **Issue:** `bigint` scores display as negative if negative, but `number` scores are clamped to 0.
- **Fix:** Apply `Math.max(0, ...)` equivalent for bigint values.

### L-3: `FriendsClient` — Array Index in `key` Prop
- **File:** `src/components/social/FriendsClient.tsx:131`
- **Severity:** Low
- **Issue:** `key={\`${tab}-${userId}-${index}\`}` uses index which can cause React reconciliation issues.
- **Fix:** Use `key={\`${tab}-${userId}\`}` since userId is unique per tab.

### L-4: `AuthCallbackClient` — Unnecessary `useMemo` for Singleton
- **File:** `src/components/auth/AuthCallbackClient.tsx:37`
- **Severity:** Low
- **Issue:** `getClientSupabase()` returns a singleton; wrapping in `useMemo` is redundant.
- **Fix:** Call directly without `useMemo`.

### L-5: `PlayRouteClient` — No Sandbox on Iframe
- **File:** `src/components/legacy-game/PlayRouteClient.tsx:6-18`
- **Severity:** Low
- **Issue:** Iframe has no `sandbox` attribute despite loading arbitrary scripts.
- **Fix:** Add `sandbox="allow-scripts allow-same-origin"` (or more restrictive as needed).

---

## Summary

| Severity | Count | IDs |
|----------|-------|-----|
| Critical | 7 | B-0, B-1, C-1, C-2, C-3, C-4, C-5 |
| High | 7 | H-1, H-2, H-3, H-4, H-5, H-6, H-7 |
| Medium | 12 | M-1 through M-12 |
| Low | 5 | L-1 through L-5 |
| **Total** | **31** | |

## Priority Order

| Priority | Bugs | Rationale |
|----------|------|-----------|
| **P0** | C-1, C-2, C-4 | Active security vulnerabilities — data exposure and XSS |
| **P1** | B-0, B-1, C-3, H-1, H-4 | Root cause of console errors + memory leak + silent failures |
| **P2** | H-2, H-3, H-5, H-7, C-5 | Security hardening and data integrity |
| **P3** | M-1 through M-12 | Reliability and correctness improvements |
| **P4** | B-2, L-1 through L-5 | Minor polish and edge cases |
