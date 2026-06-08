# Cove PR #264 — Round 6 Re-Review (Vega)

## 📝 Verdict: ✅ Approved

The previously identified blocking issue has been resolved successfully. The session TTL implementation now provides a robust lazy evaluation and periodic cleanup mechanism.

## 🔄 R5 Issue Verification

### 🟡 `resolveUser` returns stale `expires_at` after sliding refresh
**Status:** ✅ Fixed. 
The in-memory `user.expires_at` is now explicitly updated (`user.expires_at = Date.now() + SESSION_TTL_MS;`) after triggering `users.refreshTTL(user.id)`. The frontend will correctly receive the updated expiry via `/api/auth/me`, preventing premature auto-logouts.

### 🟡 WebSocket sessions outlive expired tokens (Stella R5 finding)
**Status:** ❌ Unaddressed (but Non-Blocking).
As noted in R5, `GatewayDispatcher` still does not periodically check or evict active WebSocket connections when a token expires. This remains a known architectural limitation that should be handled in a follow-up PR specifically targeting Gateway Auth Lifecycle.

### 🟢 Follow-ups from R5
- **v6 backfill policy:** Acknowledged. Existing users get a grace period (`Date.now() + SESSION_TTL`). 
- **Missing tests & OAuth atomic update:** ✅ Tests added in `__tests__/session-ttl.test.ts`. OAuth logic in `routes/auth.ts` now uses a single atomic `UPDATE` for `token` and `expires_at`.
- **Duplicated TTL parsing:** Acceptable. The duplication between `repos/users.ts` and the migration file `v6-session-ttl.ts` is standard practice to prevent migrations from breaking if application code logic/imports change later.

## 🔍 Fresh Review Notes
- **Periodic Cleanup:** Added to `index.ts` running every hour, successfully using `.unref()` so it won't block the Node process from shutting down.
- **API Redundancy:** `/api/auth/me` duplicates the cookie refresh logic found in `requireAuth()`. Not a blocker, but worth considering a refactor later to dry this up if more authenticated routes need to manipulate sliding cookies.

Ready to merge!