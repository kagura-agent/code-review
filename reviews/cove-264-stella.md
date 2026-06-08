# Stella R6 Re-review — kagura-agent/cove#264

Verdict: **✅ Ready**

R6 only adds the R5 one-line fix in `packages/server/src/auth.ts`; I rechecked the full TTL path and did not find a new merge-blocking issue. The remaining WebSocket expiry gap is still real, but R5 explicitly classified it as a follow-up rather than a blocker for this PR.

## R5 issue checklist

1. ✅ Fixed — `resolveUser` no longer returns stale `expires_at` after sliding refresh.
   - `packages/server/src/auth.ts:66-70` now calls `users.refreshTTL(user.id)`, sets `refreshed = true`, and updates `user.expires_at = Date.now() + SESSION_TTL_MS` before returning the API user.
   - `/api/auth/me` therefore returns the refreshed expiry from `packages/server/src/routes/auth.ts:100-109` instead of the pre-refresh row value.

2. ❌ Unaddressed — WebSocket sessions can still outlive expired browser session tokens.
   - `packages/server/src/ws/index.ts:36-47` still validates the cookie once during upgrade, and `packages/server/src/ws/index.ts:87-117` still authenticates IDENTIFY once and stores the user on the `GatewaySession`.
   - There is still no expiry timer, heartbeat recheck, dispatch-time recheck, or token validity re-read after `expires_at` passes / cleanup clears the token.
   - Per the R5 instruction, this remains a **follow-up issue, not a blocker for #264**. If this were treated as an R5 blocker, the escalation rule would make it blocking now; however the current task explicitly says to just note whether it was addressed.

3. 🟢 Follow-up still open — v6 backfill grants fresh TTL to dormant human users.
   - `packages/server/src/db/migrations/v6-session-ttl.ts:11-16` uses deployment time + `SESSION_TTL`, not `updated_at + TTL`.
   - This is a policy choice and was previously non-blocking.

4. 🟢 Follow-up still open — tests are still missing for cookie reissue and OAuth atomic token/expiry update.
   - The core TTL tests are present in `packages/server/src/__tests__/session-ttl.test.ts`, but there is no direct regression for `Set-Cookie` on sliding refresh or the existing-user OAuth single UPDATE path.
   - Non-blocking, but worth adding before this logic grows further.

5. 🟢 Follow-up still open — duplicated `SESSION_TTL_MS` parsing.
   - Runtime parsing lives in `packages/server/src/repos/users.ts:5-9`; migration fallback parsing lives in `packages/server/src/db/migrations/v6-session-ttl.ts:4-5`.
   - Still acceptable for this PR because the migration intentionally avoids importing runtime repos, but it is duplicated policy.

## Fresh review notes

### No new blocking findings

The main REST/session TTL flow now looks consistent:

- Human sessions get `expires_at` at user creation (`packages/server/src/repos/users.ts:48-53`), invite registration (`packages/server/src/routes/register.ts:51-53`), and OAuth login (`packages/server/src/routes/auth.ts:82-86`).
- Expired tokens are rejected lazily and cleared without deleting the user (`packages/server/src/repos/users.ts:99-107`).
- Periodic cleanup clears expired tokens and logs non-zero cleanup counts while catching interval errors (`packages/server/src/index.ts:25-35`).
- Cookies use the same configured TTL as the DB session (`packages/server/src/auth.ts:23-32`).
- Sliding refresh updates DB state, reissues the cookie for cookie-authenticated requests, and now returns the refreshed expiry in memory (`packages/server/src/auth.ts:63-73`, `packages/server/src/routes/auth.ts:105-109`).

### Minor risk: regenerated human tokens keep the previous session expiry

`packages/server/src/repos/users.ts:87-92` still regenerates a token without updating `expires_at`. Because the route requires a currently-authenticated user, this does not bypass expiry, and `requireAuth` may already refresh near-threshold sessions before the route runs. Still, the generated token can inherit an old, not-full TTL when the old session is not yet inside the sliding-refresh window. I would not block #264 on this because token regeneration can reasonably preserve the current session lifetime rather than acting as a login, but it is worth making explicit in product semantics.

## Validation performed

- Pulled PR diff with `gh pr diff 264 --repo kagura-agent/cove`.
- Checked out PR head `a671a622ba873488839e466414b9a5a851ec0f1f` locally.
- Ran targeted server tests:
  - `pnpm -F @cove/server test -- --run packages/server/src/__tests__/session-ttl.test.ts packages/server/src/__tests__/migration.test.ts packages/server/src/__tests__/api.test.ts`
  - Result: **passed** — 8 server test files, 164 tests.
- Ran server typecheck/build:
  - `pnpm -F @cove/server build`
  - Result: **passed**.

## Recommendation

Merge #264 after opening/tracking the WebSocket session-expiry follow-up. The R5 stale `expires_at` blocker is fixed, and I found no new issue severe enough to hold this PR.
