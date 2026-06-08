# R4 Re-Review — kagura-agent/cove#269 (Stella)

## Verdict

⚠️ **Needs Changes**

The R3 consensus blocker is fixed: WebSocket session expiry now uses recursive `scheduleExpiry()` and clamps long timeout delays. The previously-fixed items are still intact. However, two R3 minor follow-ups remain unaddressed; per the escalation rule I am raising them to 🟡 Medium rather than letting them stay as optional notes.

Validated locally on `fix/264-followups` at `9d60d8e`:
- `pnpm -F @cove/server build` ✅
- `pnpm -F @cove/server test -- --run packages/server/src/__tests__/session-ttl.test.ts packages/server/src/__tests__/ws-auth.test.ts` ✅ — Vitest ran the server suite: 8 files / 167 tests passed.

## R3 Issues Status

| R3 Issue | Status | Notes |
|---|---:|---|
| 🟡 Expiry timer not rescheduled after sliding refresh | ✅ Fixed | `packages/server/src/ws/index.ts:162-178` now re-reads `expires_at` with `users.findByToken(token)` and recursively calls `scheduleExpiry(token, remaining)` when the token is still valid. |
| 🟢 `setTimeout` delay overflow > 2^31-1 ms | ✅ Fixed | `MAX_TIMEOUT = 2_147_483_647` at `ws/index.ts:159-160`; timer uses `Math.min(delayMs, MAX_TIMEOUT)` at `ws/index.ts:178`. |
| 🟢 Token revocation/logout does not actively disconnect WS | ❌ Unaddressed → 🟡 Escalated | Logout still only clears cookies (`routes/auth.ts:128-131`), token regeneration still updates DB without touching sessions (`routes/agents.ts:45-49`, `repos/users.ts:85-90`), and `GatewayDispatcher` still has no active close path for token/session revocation. Existing sockets remain connected until their expiry timer fires. |
| 🟢 WS expiry behavior lacks tests | ❌ Unaddressed → 🟡 Escalated | New tests in `session-ttl.test.ts:172-308` cover REST/OAuth/threshold behavior, but no WebSocket timer cases were added to `ws-auth.test.ts` or elsewhere. |

## Previously Fixed Items — Still Intact

- ✅ **re-IDENTIFY guard (4005)** remains at `packages/server/src/ws/index.ts:83-87`.
- ✅ **Cookie fallback token tracking** remains at `ws/index.ts:104-110` and `ws/index.ts:126-131`.
- ✅ **`getRefreshThreshold()` pure function extraction** remains at `packages/server/src/auth.ts:20-27`, with `resolveUser()` using it at `auth.ts:72-79`.
- ✅ **`@deprecated` re-export** remains in `packages/server/src/repos/users.ts:6-7`.
- ✅ **OAuth integration test** remains in `packages/server/src/__tests__/session-ttl.test.ts:248-307` and exercises the real callback route.

## Fresh Review Findings

### 🟡 M1 — Revoked/replaced tokens still do not actively close existing WebSockets

`packages/server/src/routes/agents.ts:45-49`, `packages/server/src/repos/users.ts:85-90`, `packages/server/src/ws/dispatcher.ts:6-229`

The new recursive expiry timer eventually detects a replaced token only when the scheduled expiry check fires. That is better than “never”, but it is still not active revocation. A user can regenerate their token and the old WebSocket remains READY/online until the old expiry timestamp. With the default 7-day TTL, this is a large stale-auth window.

`/api/auth/logout` also does not revoke the server-side token at all; it only deletes browser cookies (`routes/auth.ts:128-131`). If product semantics are “logout from this browser only”, that should be documented and the previous revocation issue should target token regeneration/OAuth re-login instead. If product semantics are “logout means current session is no longer authorized”, the route needs a server-side revocation and dispatcher close.

Suggested shape:
- Add a dispatcher method such as `closeUserSessions(userId, code, reason)` or `closeSessionsByToken/sessionId`.
- Call it when token regeneration / OAuth token replacement / real logout revocation occurs.
- Keep `scheduleExpiry()` as the safety net, not the primary revocation mechanism.

### 🟡 M2 — WebSocket expiry timer is still untested

`packages/server/src/__tests__/session-ttl.test.ts:172-308` adds good REST/OAuth coverage, but the code changed in R4 is `packages/server/src/ws/index.ts:162-178`. There is no test proving:

1. a WS closes when `expires_at` passes;
2. a sliding REST refresh before the original timer fires causes a second timer and later close;
3. timeout clamping does not immediately close long-TTL sessions;
4. revoked/replaced tokens are handled according to the intended revocation semantics.

This PR has had multiple review rounds around exactly this timer behavior. At this point, relying only on code inspection is fragile; at least the expiry-close and sliding-refresh-reschedule cases should be covered with fake timers or a short test TTL.

### 🟡 M3 — Cookie pre-auth still uses an upgrade-time identity snapshot at IDENTIFY

`packages/server/src/ws/index.ts:36-47`, `ws/index.ts:102-110`

When falling back to cookie auth, IDENTIFY still assigns `user = preAuthUser`, which was captured during the HTTP upgrade. It parses the cookie token for later expiry checks, but it does not re-read `users.findByToken(cookieToken)` before sending READY.

This leaves a stale window: if the cookie token is valid at upgrade, then regenerated/revoked before IDENTIFY, the socket can still identify using the cached user object and remain connected until the expiry timer checks the old token. This is narrower than the general revocation issue, but it is the same class of stale-auth acceptance.

Suggested fix: in the fallback branch, parse the cookie token, call `users.findByToken(cookieToken)` immediately, and build `user` from that fresh row. Do not identify from the upgrade-time snapshot.

## Positive Notes

- The core R3 timer bug is fixed cleanly; `scheduleExpiry()` is small and easy to reason about.
- The overflow clamp is the right defense for operator-configured long TTLs.
- The config centralization and `getRefreshThreshold()` extraction remain good cleanup.
- Existing server build/tests pass locally.
