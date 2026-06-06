# Cove PR #248 — Stella Review Round 3

PR: `kagura-agent/cove#248` — `fix: OAuth token leak — BFF pattern with HttpOnly cookies (closes #227)`

## Round 2 Issue Status

1. ✅ Fixed — WebSocket auth path has tests
   - Added `packages/server/src/__tests__/ws-auth.test.ts` covering browser cookie auth with `{ token: null }`, bot token auth, missing credentials, invalid token, and malformed cookie handling.

2. ✅ Fixed — Legacy `localStorage` tokens remain accessible to XSS
   - Client no longer reads/stores bearer tokens and removes legacy `cove-token` / `cove-user` on startup (`packages/client/src/App.tsx`).

3. ✅ Fixed — Deployment may not set `NODE_ENV=production`, making `Secure` ineffective
   - Cookie options now default to `secure: true` unless `NODE_ENV === "development"` (`packages/server/src/auth.ts:19-26`). Staging deploy still does not set `NODE_ENV`, but that now results in Secure cookies, which is the safer production/staging behavior.

4. ✅ Fixed — Register still accepts `pendingToken` from body
   - Register now reads `pendingToken` only from the `cove-pending` cookie (`packages/server/src/routes/register.ts:17-24`).

5. ✅ Fixed — Token-fallthrough in WS was silent/surprising
   - Added comments explaining explicit-token-first and cookie pre-auth fallback behavior (`packages/server/src/ws/index.ts:89-103`).

6. ⚠️ Partially fixed — `/api/auth/me` duplicates `resolveUser` logic
   - `resolveUser` exists and `requireAuth` uses it (`packages/server/src/auth.ts:33-65`), but `/api/auth/me` still hand-parses `Bearer`, `Bot`, and cookie auth separately in `packages/server/src/routes/auth.ts:98-123` instead of calling `resolveUser`. Drift risk remains, although current behavior is covered by tests.

7. ❌ Not addressed — Stray blank line in `api.ts` logout function
   - `packages/client/src/lib/api.ts` still has a blank line before the closing brace in `logout()`.

8. ❌ Not addressed — No CORS for cross-origin deploys
   - The client now uses `credentials: "include"`, but the server still has no CORS middleware / `Access-Control-Allow-Credentials` handling. Same-origin deploys are fine; cross-origin `VITE_COVE_API_URL` deploys will fail browser credentialed requests.
   - Escalated from R2 🟢 to R3 🟡 because it remains unaddressed.

## New Issues Found

### 🟡 Sign-out does not close the authenticated WebSocket session

`SettingsPanel` calls `api.logout()` and then only clears the Zustand user state (`packages/client/src/components/SettingsPanel.tsx`). The existing browser WebSocket is not closed. `App` cleanup tears down gateway subscriptions, but it does not call `useWebSocketStore.disconnect()`, so the already-identified socket can remain connected to the server dispatcher and keep heartbeating after the user signs out.

Why it matters:
- Product/security expectation: after Sign Out, the browser should stop receiving authenticated realtime traffic.
- The server-side logout only deletes cookies; it does not invalidate the DB token or close existing gateway sessions.
- This path is not covered by tests; current tests verify cookies clear, not that the active gateway session ends.

Suggested fix:
- On logout, call `useWebSocketStore.getState().disconnect()` before/after clearing local user state, or centralize auth teardown so transitioning to `needsSetup` closes the socket.
- Add a regression test or client-level test for logout invoking websocket disconnect, plus optionally a gateway/session integration check if test infrastructure supports it.

### 🟢 Local HTTP dev OAuth may break unless `NODE_ENV=development` is explicitly set

`COOKIE_OPTIONS.secure` is now true by default unless `NODE_ENV === "development"` (`packages/server/src/auth.ts:19-26`). That is correct for staging/prod and fixes the R2 deployment concern, but `packages/server/package.json` runs `tsx watch src/index.ts` without setting `NODE_ENV=development`. On local `http://localhost`, browsers will reject Secure cookies.

Suggested fix:
- Set `NODE_ENV=development` in the server dev script, or derive local dev from `BASE_URL`/localhost explicitly.

## Verification

- `gh pr view 248 --json title,body,files,additions,deletions`
- `gh pr diff 248`
- `gh pr checkout 248`
- `pnpm -r build` under Node 24: ✅ passed
- `pnpm -r test` under Node 24: ✅ 150 server tests + client/plugin tests passed
- Note: the first test attempt under Node 22 failed because `better-sqlite3` had been compiled for Node 24 (`NODE_MODULE_VERSION 137` vs 127); rerunning with the repo's current Node 24 native module succeeded.

## Summary

Round 3 substantially improves the PR: the main BFF flow no longer exposes OAuth/session tokens to URL/localStorage, pending registration moved to HttpOnly cookies, WebSocket browser auth has integration tests, and cookie `Secure` defaults are now safe for staging/prod even without `NODE_ENV=production`.

Remaining concerns are mostly cleanup/edge cases, but one security/product issue is still important: Sign Out should close the active authenticated WebSocket. Also, two R2 green items remain unaddressed (`/api/auth/me` drift partially, blank line, CORS), with CORS escalated per review instructions.

## Verdict

⚠️ Needs Changes

The BFF/token-leak fix is close, but I would not mark this ready until logout closes the active WebSocket session, and the lingering R2 items are either fixed or explicitly documented as intentionally out of scope.