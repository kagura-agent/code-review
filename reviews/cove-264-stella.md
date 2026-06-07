# Stella R5 Re-review — kagura-agent/cove#264

Verdict: **Needs Changes**

The R4 items were mostly addressed, but fresh review found a session-TTL bypass for already-open WebSocket gateway sessions. If merged as-is, an expired browser session can remain connected to the gateway indefinitely and continue receiving real-time events after its token/cookie has expired or even after periodic cleanup has cleared the token.

## R4 issue checklist

1. ✅ Fixed — Sliding refresh threshold now uses `Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86_400_000)` in `packages/server/src/auth.ts:64-66`, so short TTLs no longer produce a negative threshold.
2. ✅ Fixed — V6 migration creates the partial `expires_at` index in `packages/server/src/db/migrations/v6-session-ttl.ts:19-20`.
3. ✅ Fixed — Periodic cleanup now wraps `cleanupExpired()` in `try/catch` and logs non-zero cleanup counts in `packages/server/src/index.ts:27-34`.
4. ✅ Fixed — Sliding refresh now reissues the session cookie from both middleware and `/api/auth/me` via `setCookie(..., COOKIE_OPTIONS)` in `packages/server/src/auth.ts:82-84` and `packages/server/src/routes/auth.ts:105-108`.
5. ✅ Fixed — OAuth token and `expires_at` are updated atomically in one statement in `packages/server/src/routes/auth.ts:82-85`.
6. ✅ Fixed — V6 backfill now reads `SESSION_TTL_MS` instead of hardcoding 7 days in `packages/server/src/db/migrations/v6-session-ttl.ts:4-15`.
7. ✅ Fixed — `UsersRepo.create()` now treats only `opts.bot === true` as a bot, so omitted `bot` no longer creates immortal sessions (`packages/server/src/repos/users.ts:47-53`).

## Findings

### 🔴 High — WebSocket gateway sessions outlive expired session tokens indefinitely

**Where:** `packages/server/src/ws/index.ts:35-46`, `packages/server/src/ws/index.ts:87-117`

The TTL is enforced only when `users.findByToken()` is called. The gateway calls `findByToken()` once during cookie pre-auth / IDENTIFY, stores the resulting user on the `GatewaySession`, and then never rechecks token validity or the user’s `expires_at` again.

That means this sequence still works after the TTL expires:

1. Browser opens `/gateway` while its cookie token is still valid.
2. `verifyClient` authenticates once with `users.findByToken(sessionToken)` and stores `__coveUser`.
3. The session IDENTIFYs and is added to the dispatcher.
4. Time passes beyond `expires_at`; REST now returns 401 and periodic cleanup may clear `users.token` / `users.expires_at`.
5. The existing `GatewaySession` remains `identified` and continues receiving dispatches/presence/message events because no code disconnects it on session expiry.

This defeats the product/security goal of session TTL for browser sessions: closing REST access is not enough if the authenticated real-time channel stays open. A user with an expired session can keep a tab open and continue receiving private channel activity indefinitely.

**Suggested fix:** carry `expires_at` into the gateway auth state and enforce it for non-bot sessions. Options:

- On IDENTIFY/pre-auth, schedule a disconnect timer for `expires_at - Date.now()` and clear it on close; or
- On each heartbeat / before dispatch, re-read `users.findByToken()` or a lighter `isSessionValid(userId, token)` and close with an auth/session-expired close code when invalid.

If you keep sliding sessions, decide whether gateway heartbeats count as activity. If yes, refresh and reissue is impossible over WS cookie headers, so the safer/product-consistent behavior is probably: REST activity refreshes cookies; gateway disconnects when the stored session expiry is reached and lets the browser reconnect only if the cookie was refreshed elsewhere.

Add a WebSocket regression test: connect with a human cookie whose `expires_at` is near/behind `Date.now()`, advance fake timers or set a tiny `SESSION_TTL_MS`, run cleanup, then assert the socket is closed / no longer receives dispatches.

### 🟡 Medium — Sliding refresh returns stale `expires_at` in `/api/auth/me`

**Where:** `packages/server/src/auth.ts:63-72`, `packages/server/src/routes/auth.ts:100-109`

When `resolveUser()` refreshes a user, it calls `users.refreshTTL(user.id)` but returns the original `user.expires_at` read before the update. `/api/auth/me` then returns that stale timestamp even though the server-side expiry has just been extended and the cookie was reissued.

This can mislead clients that rely on `/api/auth/me.expires_at` for session UI or renewal timing: immediately after a successful sliding refresh, the API still says the session expires at the old time.

**Suggested fix:** make `refreshTTL()` return the new `expires_at`, or compute `const newExpiresAt = Date.now() + SESSION_TTL_MS` once in `resolveUser()` and pass/return it so `result.user.expires_at` matches the database.

## Validation performed

- Pulled PR diff with `gh pr diff 264 --repo kagura-agent/cove`.
- Checked out PR branch locally.
- Ran targeted server tests:
  - `pnpm -F @cove/server test -- --run packages/server/src/__tests__/session-ttl.test.ts packages/server/src/__tests__/auth.test.ts`
  - Result: passed (`8` server test files, `164` tests; Vitest interpreted the extra args broadly).
- Ran `pnpm -r build` successfully. Follow-up `pnpm -r exec tsc --noEmit` was started in the same shell but the overall process was SIGKILLed after the build completed, so no typecheck result is claimed.
