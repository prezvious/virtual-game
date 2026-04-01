# Bug Audit Report

## Summary

This audit confirmed 4 additional implementation bugs outside the original fix list and reviewed all 10 planned fixes. The highest-risk issues are in the social API and admin moderation flow.

## Review Findings

### 1. [P1] Social mutations run under anon RLS context

**File:** `C:/Users/prezv/Documents/Coding/gaming-platform/src/app/api/social/route.ts:21-160`

**Issue:**  
This route verifies the bearer token with `auth.getUser()`, but all later reads and writes use a fresh anon Supabase client that never receives that token.

**Impact:**  
Because the `follows_*` and `blocks_*` policies rely on `auth.uid()`, follow, unfollow, block, and unblock requests will be rejected by RLS. The blocked list query will also read as empty.

**Recommended fix:**  
Execute these queries with a client that carries the caller's access token, or use a service-role client plus explicit authorization checks.

---

### 2. [P1] Auth-user deletion is blocked by non-cascading foreign keys

**File:** `C:/Users/prezv/Documents/Coding/gaming-platform/supabase/migrations/20260323_platform_features.sql:168-181`

**Issue:**  
The proposed `auth.admin.deleteUser(targetId)` step is not safe with the current schema.

**Impact:**  
`admin_logs.admin_id`, `admin_logs.target_user_id`, and `platform_settings.updated_by` all reference `auth.users(id)` without `ON DELETE CASCADE` or `SET NULL`. Deleting a user who appears in moderation logs or settings history can fail on foreign-key constraints.

**Recommended fix:**  
Add a migration first. Update those foreign keys to use either `ON DELETE SET NULL` or another deliberate cleanup strategy before enabling auth-user deletion.

---

### 3. [P1] Admin moderation can target the current admin or another admin

**File:** `C:/Users/prezv/Documents/Coding/gaming-platform/src/app/api/admin/route.ts:219-242`

**Issue:**  
Neither `ban_user` nor `delete_user_data` prevents an administrator from acting on their own account or another administrator's account.

**Impact:**  
This is already risky for bans. It becomes much worse if auth-user deletion is added, because one request could remove the last admin account.

**Recommended fix:**  
Explicitly reject self-targeting and require a second guard before mutating any admin profile.

---

### 4. [P2] Several admin write paths report success without checking write errors

**File:** `C:/Users/prezv/Documents/Coding/gaming-platform/src/app/api/admin/route.ts:146-215`

**Issue:**  
`spawn_item`, `set_weather`, and `add_money` / `remove_money` ignore the result of their insert, update, and upsert calls.

**Impact:**  
If a write fails, for example because the item id is invalid or the database returns an error, the handler still logs a successful action and returns `ok: true`.

**Recommended fix:**  
Check every write result before logging success or returning success to the client.

---

## Plan Audit

### Fix 1a: `set_weather`
**Status:** Valid

`set_weather` has a check-then-act race and also treats any `.single()` error as "missing."  
Using `.upsert()` is the right direction, but the returned `error` still needs to be checked.

### Fix 1b: `add_money` / `remove_money`
**Status:** Valid but incomplete

Replacing the existence check with `.upsert()` removes the TOCTOU issue on row existence, but it does not solve the lost-update problem.  
The real fix is a DB-side increment or RPC.

### Fix 1c: `spawn_item`
**Status:** Valid but incomplete

`spawn_item` races today, and the proposed `existing ? existing.quantity + quantity : quantity` logic still depends on stale state.  
This should also be moved to a DB-side increment on `(user_id, item_id)`.

### Fix 2: `delete_user_data`
**Status:** Valid but blocked

Error collection is needed, and the route should delete more related records.  
However, the `auth.admin.deleteUser(targetId)` part is blocked by the foreign-key issue above and should not ship before a migration.

### Fix 3: `ban_user`
**Status:** Valid

`ban_user` ignores the error returned by `updateUserById`.

### Fix 4: Standardize bearer token stripping
**Status:** Valid

The admin route, password route, and social route all use case-sensitive bearer stripping.  
A shared `stripBearer()` helper is appropriate.

### Fix 5: Remove duplicate browser Supabase client
**Status:** Partial

`src/lib/supabase-browser.ts` is redundant, but the duplication is not limited to that file.  
`AuthCallbackClient.tsx` also creates its own browser Supabase client inline.

### Fix 6: Add environment validation
**Status:** Valid

`src/lib/supabase.ts` falls back to placeholder values, which turns configuration mistakes into opaque runtime failures.  
Runtime validation should fail fast instead.

### Fix 7: Rename `createServerSupabaseClient` to `createAnonServerClient`
**Status:** Useful refactor, not a runtime fix by itself

This rename would make the auth model clearer and likely reduce misuse.  
The current name likely contributed to the social-route bug.

### Fix 8: Clean up injected scripts in `LegacyGameClient.tsx`
**Status:** Valid

Injected scripts are never removed on unmount.  
Cleanup should remove injected nodes and avoid state updates after unmount.

### Fix 9a: Add error handling to `AchievementsClient.tsx`
**Status:** Valid

The component has no error state and silently degrades on auth or fetch failure.

### Fix 9b: Add error handling to `FriendsClient.tsx`
**Status:** Valid

The component ignores failed fetches and failed action responses, which hides the underlying social API failure.

### Fix 10: Debounce admin search and add `AbortController`
**Status:** Valid

`AdminClient` refetches on every `searchQ` change because `fetchTab` depends on it, and it has no cancellation for stale in-flight requests.

--- 