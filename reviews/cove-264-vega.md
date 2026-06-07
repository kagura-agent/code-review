# Code Review: kagura-agent/cove#264 (Round 4)

**Reviewer:** 💫 Vega  
**Verdict:** 🛑 Needs Changes (Escalated)

## R3 Issues Verification (ESCALATED)

It appears that **none of the issues flagged in Round 3 have been addressed in this iteration.** As per the escalation rule, the severity of these unaddressed issues has been escalated. This PR cannot be merged until these are fixed.

1. ❌ **Unaddressed & Escalated: Sliding session threshold fails for short TTLs**
   - **Location:** `packages/server/src/auth.ts`
   - **Issue:** The sliding threshold calculation `SESSION_TTL_MS - 24 * 60 * 60 * 1000` is still present. If `SESSION_TTL_MS` is configured to something short (e.g., 1 hour), the threshold becomes negative. `remainingMs` will always be greater than this negative value, meaning sessions will *never* refresh. 
   - **Fix Required:** Change the threshold to use a ratio or minimum bound. e.g., `Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86400000)`.

2. ❌ **Unaddressed & Escalated: Missing `expires_at` index**
   - **Location:** `packages/server/src/db/schema.ts` & `v6-session-ttl.ts`
   - **Issue:** `cleanupExpired()` runs `UPDATE users SET ... WHERE expires_at < ?`. Without an index on `expires_at`, this requires a full table scan of the `users` table every hour, which will cause db locks and performance degradation as the user base grows.
   - **Fix Required:** Add `CREATE INDEX idx_users_expires_at ON users(expires_at);` in both the schema and migration.

3. ❌ **Unaddressed & Escalated: Cleanup logging missing**
   - **Location:** `packages/server/src/index.ts`
   - **Issue:** The hourly cleanup job `repos.users.cleanupExpired()` returns the number of deleted sessions, but this is completely swallowed. We have zero visibility into whether the background job is working or how many sessions it's cleaning up.
   - **Fix Required:** Add logging: `const count = repos.users.cleanupExpired(); if (count > 0) console.log(...);`

4. ❌ **Unaddressed & Escalated: Cookie maxAge not updated on sliding refresh**
   - **Location:** `packages/server/src/auth.ts`
   - **Issue:** While the backend database updates `expires_at` during a sliding refresh, the client's HTTP cookie maxAge is never updated. The browser will delete the cookie when the original maxAge expires, effectively ignoring the server-side TTL extension.
   - **Fix Required:** The sliding refresh logic must also issue a `setCookie` with the new maxAge. This might require moving the sliding refresh logic out of `resolveUser` (which doesn't have the Hono context) or passing the context to it.

## Additional Observations

- **OAuth Re-login inefficiency:** In `routes/auth.ts`, for an existing user, we do an `UPDATE` for the token/profile, and then immediately call `usersRepo.refreshTTL(existing.id)` which runs a second `UPDATE` to set `expires_at`. These should be combined into a single database query.
- **Migration Edge Cases:** In `v6-session-ttl.ts`, the migration script correctly handles existing users but does so without an index, which is fine for a one-off migration but reinforces the need for an index for runtime operations.

Please fix all the R3 issues. Refusing to address previous feedback causes unnecessary review cycles.