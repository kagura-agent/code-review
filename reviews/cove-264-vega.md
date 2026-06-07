# Cove PR #264 (Round 5) Code Review
**Reviewer:** 💫 Vega

## 📋 R4 Issues Verification

### 🔴 Escalated from R3:
1. **Sliding refresh threshold breaks for short TTLs**
   - **Status:** ✅ Fixed. Updated to `Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86400000)`.
2. **No `expires_at` index**
   - **Status:** ✅ Fixed. Added `idx_users_expires_at` in the v6 migration for partial indexing.
3. **Cleanup has no logging**
   - **Status:** ✅ Fixed. Added try/catch and logging when tokens are cleared in `index.ts`.
4. **Cookie not reissued on sliding refresh**
   - **Status:** ✅ Fixed. `resolveUser` now returns a `refreshed` boolean flag, and both `requireAuth` and `/api/auth/me` properly reissue the `cove-session` cookie with the extended maxAge.

### 🔴 New in R4:
5. **OAuth token + expires_at non-atomic**
   - **Status:** ✅ Fixed. Login now issues a single atomic `UPDATE` query.

### 🟡 New in R4:
6. **v6 backfill hardcodes 7 days**
   - **Status:** ✅ Fixed. The migration properly parses the `SESSION_TTL_MS` environment variable.
7. **Default bot footgun**
   - **Status:** ✅ Fixed. Safely uses `opts.bot === true` check.

---

## 🔴 New Issue in R5 (Needs Changes)

### 1. `resolveUser` returns stale `expires_at` on sliding refresh
In `src/auth.ts`, when the sliding refresh triggers, you correctly update the database via `users.refreshTTL(user.id)`. However, you forget to update the in-memory `user.expires_at` variable before returning the `AuthUser` object.

**Impact:** The `/api/auth/me` endpoint returns the *old, un-refreshed* expiration date in the JSON response. If the frontend relies on this `expires_at` payload to manage client-side state or auto-logout timers, the client will prematurely log the user out even though the backend extended the session.

**Fix:** Update the in-memory property when `refreshed = true`.
```typescript
  if (user.expires_at !== null && !user.bot) {
    const remainingMs = user.expires_at - Date.now();
    const refreshThreshold = Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86_400_000);
    if (remainingMs < refreshThreshold) {
      users.refreshTTL(user.id);
      refreshed = true;
      user.expires_at = Date.now() + SESSION_TTL_MS; // <-- Add this to prevent stale API responses
    }
  }
```

---

## 🎯 Verdict
**Needs Changes**

The R4 issues were completely addressed and the implementation is vastly more robust. The sole remaining issue is a data staleness bug that breaks frontend timer assumptions. Fix the `expires_at` return value in `resolveUser` and this is ready to merge! 🚀