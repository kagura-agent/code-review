# R2 Re-review: kagura-agent/cove#269

Reviewer: 🌟 Stella  
PR: https://github.com/kagura-agent/cove/pull/269  
Head reviewed: `f7372a7baa6482ebef325c32f28d60fc3959b134`

## Verdict

Request changes.

R2 fixed several R1 items, but some R1 concerns remain. Per the escalation rule, all unaddressed R1 items below are escalated in severity. I also found one fresh config-validation issue in the new central config module.

## Validation performed

- Fetched PR metadata/diff with `gh pr view` / `gh pr diff`.
- Checked GitHub checks: `test` and `deploy` passing.
- Ran targeted tests locally:
  - `pnpm -r --filter @cove/server exec vitest run src/__tests__/session-ttl.test.ts` ✅ 9 passed
- Ran server typecheck locally:
  - `pnpm -r --filter @cove/server exec tsc --noEmit` ✅ passed

## R1 issue status

### 🔴 Previous Must Fix

1. ✅ Fixed — re-IDENTIFY leaks intervals / double registration
   - `packages/server/src/ws/index.ts:84-88` rejects a second IDENTIFY with close code `4005` before `session.identify`, `dispatcher.addSession`, or expiry interval setup.

2. ✅ Fixed for the explicit-token/cookie fallback bug — cookie fallback now tracks the cookie token
   - `packages/server/src/ws/index.ts:105-110` replaces the invalid explicit token with the `cove-session` cookie token before starting the expiry checker.
   - Caveat: see escalated pre-auth revalidation finding below; the fallback token is now the right token, but the pre-authenticated user snapshot itself is still not revalidated at IDENTIFY time.

3. ❌ Unaddressed — short-TTL test still does not exercise the production short-TTL branch
   - Escalated to ⛔ Blocker below.

4. ✅ Fixed — OAuth test now drives the actual callback route
   - `packages/server/src/__tests__/session-ttl.test.ts:254-313` calls `/api/auth/callback?code=mock-auth-code` and mocks Google token/userinfo endpoints instead of hand-writing the update SQL.

### 🟡 Previous Should Address

1. ❌ Unaddressed — 60s per-connection polling scalability
   - Escalated to 🔴 Must Fix below.

2. ❌ Unaddressed — `repos/users.ts` re-export needs `@deprecated`
   - Escalated to 🔴 Must Fix below.

3. ❌ Unaddressed — `preAuthUser` not revalidated at IDENTIFY time
   - Escalated to 🔴 Must Fix below.

## Findings

### ⛔ Blocker: R1 short-TTL test is still not testing the production short-TTL path

Location: `packages/server/src/__tests__/session-ttl.test.ts:219-252`

The new test adds a local calculation:

```ts
const shortTTL = 3_600_000;
const shortThreshold = Math.max(shortTTL / 2, shortTTL - 86_400_000);
expect(shortThreshold).toBe(shortTTL / 2);
```

But that only tests the formula copied into the test. It does not execute `resolveUser` or any production helper with `SESSION_TTL_MS < 24h` / `< 2 days`. The integration portion immediately returns to the imported default `SESSION_TTL_MS` (`packages/server/src/__tests__/session-ttl.test.ts:233-251`), so it still exercises the 7-day long-TTL branch.

A production regression such as hard-coding the threshold to `SESSION_TTL_MS - 86_400_000` would still pass the local short-TTL assertions and likely pass the default-TTL integration path. This was the core R1 objection, so it remains unaddressed.

Suggested fixes:

- Extract the refresh-threshold calculation into a production helper, e.g. `getRefreshThreshold(ttlMs)`, and unit-test that helper for both 1h and 7d TTLs; or
- In the integration test, isolate module loading with `vi.stubEnv("SESSION_TTL_MS", "3600000")` + `vi.resetModules()` before importing `config`, `auth`, and `repos/users`, then verify `resolveUser` refresh behavior under an actual 1h configured TTL.

### 🔴 Must Fix: Cookie pre-auth is still not revalidated at IDENTIFY time

Location: `packages/server/src/ws/index.ts:37-47`, `packages/server/src/ws/index.ts:61-62`, `packages/server/src/ws/index.ts:105-110`, `packages/server/src/ws/index.ts:124-140`

The upgrade-time cookie lookup caches `preAuthUser` on the request. Later, IDENTIFY trusts that cached object directly:

```ts
if (!user && preAuthUser) {
  user = preAuthUser;
  const cookies = parseCookies(request.headers.cookie);
  identifyToken = cookies[SESSION_COOKIE] || undefined;
}
```

This means a browser socket can be accepted and receive READY/guild data using a cookie that was valid during HTTP upgrade but expired or was revoked before IDENTIFY. The new 60s expiry checker eventually closes it, but only after `session.identify(...)` and `dispatcher.addSession(...)` have already run.

Impact:

- Expired/revoked sessions can be registered as online for up to 60s.
- READY can leak user/guild/channel/read-state data before the checker closes the socket.
- Presence side effects can be emitted for a session that should have failed authentication.

Fix: at IDENTIFY time, re-read the cookie token and call `users.findByToken(cookieToken)`. Use the fresh row returned from that call, not the cached `preAuthUser`, before calling `session.identify`.

### 🔴 Must Fix: Session expiry uses one polling interval per non-bot WebSocket

Location: `packages/server/src/ws/index.ts:127-140`

The PR still starts a `setInterval(..., 60_000)` for every non-bot gateway session, and every interval performs a DB token lookup. This was called out in R1 as a scalability concern and is unchanged.

At modest fanout this becomes N timers + N DB reads/minute for N connected browser sessions, independent of actual expiry times. It is also imprecise: expired/revoked sockets may remain active until the next poll.

Suggested fixes:

- Prefer scheduling per session with `setTimeout` to the current `expires_at` returned by `findByToken`, refreshing/rescheduling only when TTL is extended; or
- Use one central expiry scheduler/ticker that batches due sessions; or
- Tie token invalidation/logout/regeneration to dispatcher close events, and use expiry-time scheduling for natural expiry.

### 🔴 Must Fix: Deprecated compatibility re-export is still undocumented

Location: `packages/server/src/repos/users.ts:4-6`

R1 requested the compatibility re-export to be marked deprecated. It remains a bare re-export:

```ts
import { SESSION_TTL_MS } from "../config.js";
export { SESSION_TTL_MS };
```

Because the PR centralizes config in `config.ts`, this re-export should be explicitly documented as a temporary compatibility shim so future imports do not continue spreading from `repos/users.ts`.

Suggested fix:

```ts
/** @deprecated Import SESSION_TTL_MS from ../config.js instead. */
export { SESSION_TTL_MS };
```

### 🟡 Should Fix: `SESSION_TTL_MS` validation accepts partially numeric garbage

Location: `packages/server/src/config.ts:10-14`

The new central config uses `parseInt(rawTTL, 10)`. That accepts values like `"60000abc"` as `60000`, despite the file comment saying env vars are parsed and validated once here.

If invalid config should fail fast, use stricter parsing:

```ts
const parsedTTL = Number(rawTTL);
if (!Number.isInteger(parsedTTL) || parsedTTL <= 0) {
  throw new Error(...);
}
```

This is lower risk than the R1 escalations, but it is fresh code in the high-risk `config.ts` path and worth tightening before config centralization becomes the import point for more settings.

## Notes on fixed areas

- OAuth existing-user login now updates `token`, `expires_at`, and `updated_at` in one SQL statement, and the new route-level regression test covers the callback route rather than duplicating the SQL manually.
- Cookie fallback now uses the cookie token for later expiry checks when an explicit bad token is supplied with a valid cookie. That addresses the specific R1 token-tracking bug, but not the stale pre-auth snapshot described above.
- Local targeted tests and typecheck pass on the reviewed head.
