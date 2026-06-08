# R3 Review — kagura-agent/cove#269 (Stella)

## Verdict

⚠️ **Needs Changes**

The R2 test/documentation follow-ups are mostly addressed, and the old per-connection 60s DB polling is gone. However, the replacement one-shot WebSocket expiry timer does not correctly preserve the session-expiry guarantee: refreshed sessions stop being monitored after the first timer fires, and cookie pre-auth is still not revalidated at IDENTIFY. Because these were carry-over auth/session issues, I am escalating the remaining ones per the re-review rule.

Validated locally:
- `pnpm -F @cove/server build` ✅
- `pnpm -F @cove/server test -- --run packages/server/src/__tests__/session-ttl.test.ts` ✅ (Vitest ran the server suite successfully)

## Previous R2 Issues Status

### Already fixed in R2 — verify still fixed

1. ✅ **re-IDENTIFY guard (close 4005) remains fixed**
   - `packages/server/src/ws/index.ts:83-87` closes already-identified sessions with `4005` before doing any second identify work.

2. ✅ **Cookie fallback token tracking is addressed**
   - `packages/server/src/ws/index.ts:104-109` replaces an invalid/missing explicit identify token with the cookie token when falling back to `preAuthUser`.
   - `packages/server/src/ws/index.ts:127-129` stores that token for expiry validation.
   - Caveat: this still relies on stale `preAuthUser` identity; see escalated issue below.

3. ✅ **OAuth test now drives the real route**
   - `packages/server/src/__tests__/session-ttl.test.ts:282-287` calls `/api/auth/callback?code=mock-auth-code`, verifies the redirect, and checks the DB update afterward.

### Remaining from R2

1. ✅ **Short TTL test no longer tautologically re-implements the hidden formula**
   - `packages/server/src/auth.ts:20-27` extracts `getRefreshThreshold(ttlMs)`.
   - `packages/server/src/auth.ts:73-75` makes `resolveUser` consume the extracted function.
   - `packages/server/src/__tests__/session-ttl.test.ts:219-246` covers short TTL threshold values and also verifies `resolveUser` refresh behavior. This is acceptable for the requested “extract pure function” fix path.

2. ❌ **Escalated: WebSocket expiry monitoring is still incorrect after replacing the 60s polling**
   - Severity: 🟡 R2 → 🟠 R3
   - The per-connection `setInterval` DB polling was removed, but the new one-shot timer only checks once at the original `expires_at`.
   - At `packages/server/src/ws/index.ts:131-140`, when the timer fires it calls `users.findByToken(sessionToken)`. If the user refreshed their TTL via REST before the original expiry, `findByToken` returns a valid row and the callback does nothing. No new timer is scheduled for the refreshed `expires_at`.
   - Result: a non-bot WebSocket can remain connected indefinitely after the first refresh unless another close path happens. This breaks the intended bounded session lifetime.
   - Suggested fix: wrap expiry scheduling in a function. On timer fire, re-fetch the row; if missing/expired, close; if still valid with a future `expires_at`, schedule the next timer for `row.expires_at - Date.now()`.

3. ✅ **`@deprecated` on `repos/users.ts` re-export is fixed**
   - `packages/server/src/repos/users.ts:6-7` adds the requested JSDoc deprecation marker.

4. ❌ **Escalated: `preAuthUser` is still not revalidated at IDENTIFY, and the old 60s bound is gone**
   - Severity: 🟢 R2 → 🟡 R3
   - `verifyClient` snapshots `preAuthUser` at upgrade time (`packages/server/src/ws/index.ts:36-47`). Later, IDENTIFY can accept that cached object directly (`packages/server/src/ws/index.ts:104-105`) without re-reading `users.findByToken(cookieToken)`.
   - In R2 this was lower-risk because the 60s polling would eventually re-check the token. In R3 the polling is gone, and the new timer does not validate until the originally captured `expires_at` (`packages/server/src/ws/index.ts:126-140`). For a 7-day TTL, a token invalidated after upgrade but before IDENTIFY can still identify successfully and remain connected until the old expiry timer fires.
   - Suggested fix: when falling back to cookie auth during IDENTIFY, parse the cookie token and call `users.findByToken(cookieToken)` immediately. Build `user` from the fresh row, not from the upgrade-time snapshot.

## Fresh Review Findings

### 🟠 One-shot expiry timer must reschedule after sliding refresh

This is the main correctness issue in the new code. The timer comments say “Re-validate in case session was refreshed” (`packages/server/src/ws/index.ts:132`), but the implementation only avoids closing when refreshed; it does not continue monitoring the refreshed expiry.

Minimal shape:

```ts
function scheduleExpiry(token: string, delayMs: number) {
  if (expiryTimer) clearTimeout(expiryTimer);
  expiryTimer = setTimeout(() => {
    const row = users.findByToken(token);
    if (!row || row.bot || !row.expires_at) {
      closeExpired();
      return;
    }
    const nextDelay = row.expires_at - Date.now();
    if (nextDelay <= 0) closeExpired();
    else scheduleExpiry(token, nextDelay);
  }, delayMs);
}
```

### 🟡 Add WebSocket regression tests for expiry behavior

The current tests cover REST/session TTL behavior well, but not the new Gateway timer behavior. I would add at least:

- cookie-authenticated WS with `expires_at` already past by IDENTIFY time closes/rejects without READY
- WS expiry timer closes after token expiry
- if TTL is refreshed before the initial timer fires, the session gets a second timer and eventually closes at the refreshed expiry
- pre-auth cookie fallback revalidates the cookie token at IDENTIFY time

## Positive Notes

- Centralizing `SESSION_TTL_MS` in `packages/server/src/config.ts` is a good cleanup and avoids env parsing drift.
- The OAuth callback regression test is much stronger now because it exercises the actual route and verifies atomic token/expiry update.
- Removing the 60s interval is the right direction; it just needs rescheduling semantics to preserve correctness.
