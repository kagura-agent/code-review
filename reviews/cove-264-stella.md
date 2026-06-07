# 🌟 Stella R4 Re-review — kagura-agent/cove#264

**Verdict: ⚠️ Needs Changes**

Session TTL mechanics are partially implemented (expiry check, lazy cleanup, periodic cleanup hook, tests), but all four R3 issues remain either unchanged or only cosmetically addressed. Per the escalation rule, these are now **🔴 high severity** because they have survived another review round.

## R3 Issue Status

1. ❌ **Unaddressed → 🔴 High: Sliding session threshold still breaks short TTL configs**
   - `packages/server/src/auth.ts:62-66`
   - The code still uses:
     ```ts
     const refreshThreshold = SESSION_TTL_MS - 24 * 60 * 60 * 1000;
     if (remainingMs < refreshThreshold) users.refreshTTL(user.id);
     ```
   - For any `SESSION_TTL_MS < 24h`, `refreshThreshold` is negative. A valid session with positive `remainingMs` will not refresh until it is already very near/past expiry, defeating sliding sessions for short TTL deployments/tests.
   - R3 requested a ratio-safe threshold such as:
     ```ts
     Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86_400_000)
     ```
     or equivalent. That is not present.

2. ❌ **Unaddressed → 🔴 High: No `expires_at` index; cleanup still scans `users`**
   - `packages/server/src/db/schema.ts:26-38`
   - `packages/server/src/db/migrations/v6-session-ttl.ts:4-18`
   - `packages/server/src/repos/users.ts:118-121`
   - `cleanupExpired()` filters on `expires_at IS NOT NULL AND expires_at < ?`, but neither fresh schema nor migration creates an index on `expires_at`.
   - This means hourly cleanup remains a full table scan as the user table grows.
   - Expected fix: `CREATE INDEX IF NOT EXISTS idx_users_expires_at ON users(expires_at) WHERE expires_at IS NOT NULL;` in the migration and fresh schema path.

3. ❌ **Unaddressed → 🔴 High: Periodic cleanup still has no logging**
   - `packages/server/src/index.ts:25-29`
   - `cleanupExpired()` returns a count, but the timer ignores it:
     ```ts
     setInterval(() => {
       repos.users.cleanupExpired();
     }, SESSION_CLEANUP_INTERVAL_MS);
     ```
   - There is still no observability for whether cleanup is running or clearing sessions, which was already escalated from R1.
   - Expected fix: log non-zero cleanup counts, and ideally catch/log cleanup errors so timer failures are visible.

4. ❌ **Unaddressed → 🔴 High: Sliding refresh updates DB TTL but does not reissue cookie**
   - `packages/server/src/auth.ts:57-70`
   - `packages/server/src/routes/auth.ts:98-103`
   - `resolveUser()` can refresh `expires_at`, but it has no access to `Context`, so it cannot send a refreshed `Set-Cookie` with a renewed `Max-Age`.
   - Browser cookie expiry remains anchored to the original login/registration cookie even when the server-side `expires_at` slides forward. Result: active users can still be logged out by client cookie expiry despite the DB session being extended.
   - `/api/auth/me` also returns the pre-refresh `user.expires_at` value, so clients observing `expires_at` receive stale data immediately after a sliding refresh.

## Additional Fresh Findings

### 🔴 High: `expires_at` is not refreshed atomically with the OAuth token update
- `packages/server/src/routes/auth.ts:78-84`
- Existing OAuth login does two separate writes:
  1. update username/avatar/google/email/token/updated_at
  2. `usersRepo.refreshTTL(existing.id)`
- If the process crashes or the second statement fails after the first update, the user can receive a newly generated cookie token while the DB row keeps an old/expired `expires_at`. The next request can immediately 401 and clear the newly issued token.
- Since this is login/session issuance code, token and TTL should be updated in one statement or transaction.

## Positive Notes

- Lazy expiry in `UsersRepo.findByToken()` correctly clears expired tokens instead of deleting the user row.
- Bot tokens remain non-expiring via `expires_at = NULL`.
- New tests cover expired-token rejection, bot non-expiry, cleanup behavior, user creation TTLs, and `/api/auth/me` exposing `expires_at`.
- Existing OAuth login now generates a fresh token instead of reusing a potentially expired token.

## Testing

Not run locally; this review was based on the PR diff and checked-out PR source. The added tests do not currently cover the four R3 regressions above: short `SESSION_TTL_MS`, index existence, cleanup logging, or cookie reissue on sliding refresh.

## Recommendation

Do not merge yet. Fix the four escalated R3 items before another approval pass. The minimum acceptable patch should include:

1. Ratio-safe refresh threshold for short TTLs.
2. Fresh-schema + migration index for `users(expires_at)`.
3. Cleanup logging using the returned count, plus error logging.
4. Route/context-aware sliding refresh that reissues the session cookie and returns the refreshed `expires_at`.
5. Atomic OAuth login update for token + `expires_at`.
