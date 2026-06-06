# Stella Review — cove PR #248 Round 2

## 1. Round 1 Issue Status

### Critical Issues

1. ✅ **Fixed — `/api/auth/pending-status` and `/api/auth/logout` now public**
   - `packages/server/src/app.ts:18` adds both paths to `PUBLIC_PATHS`, so pending users and logout are no longer blocked by `requireAuth`.
   - New tests cover public access for both endpoints in `packages/server/src/__tests__/auth.test.ts`.

2. ⚠️ **Partially fixed — HTTP auth tests added, but WebSocket auth remains untested**
   - Good progress: `packages/server/src/__tests__/auth.test.ts` adds coverage for pending-status, logout, `requireAuth` cookie auth, `/api/auth/me`, and register cookie flow.
   - Remaining blocking gap: the PR also changes the WebSocket authentication gate (`packages/server/src/ws/index.ts:35-115`) to accept cookies during upgrade and fall back during IDENTIFY. Existing `gateway.test.ts` covers dispatcher behavior only; it does not exercise cookie pre-auth, invalid cookie behavior, explicit token behavior, or the 4001/4004 close-code split.
   - Because this is an auth/security path, this remains a blocking test gap under the review standard.

3. ✅ **Fixed — malformed cookies no longer throw uncaught `URIError`**
   - `parseCookies` now wraps `decodeURIComponent` in `try/catch` and skips malformed values (`packages/server/src/ws/index.ts:21-25`).

4. ⚠️ **Mostly fixed — browser no longer sees `pendingToken`, but server still accepts it in body**
   - Fixed for the BFF/browser flow: `/api/auth/pending-status` returns only `{ pending: true }`, `InviteCodePage` no longer receives/sends `pendingToken`, and register returns `{ message: "registered" }` instead of `{ token }`.
   - Remaining concern: `registerRoutes` still falls back to `body.pendingToken` (`packages/server/src/routes/register.ts:21-23`) solely for backward compatibility with existing tests. Since Cove has no existing users per commit message, I would remove this fallback and update old tests to use the cookie path so the public API fully enforces the BFF invariant.

### Suggestions from Round 1

1. ✅ **Legacy localStorage cleanup addressed by removal**
   - The client no longer reads/writes `cove-token`; stale values are inert. Given the follow-up commit states there are no existing users, explicit cleanup is not required.

2. ✅ **Logout error handling fixed**
   - Sign-out now uses `.catch(() => {}).finally(...)`, so local UI state clears even if the logout request fails (`packages/client/src/components/SettingsPanel.tsx:211`, `:224`).

3. ✅ **`/api/auth/me` Bot prefix support fixed**
   - `/api/auth/me` now accepts both `Bearer` and `Bot` prefixes (`packages/server/src/routes/auth.ts:101-107`).

4. ✅ **WebSocket 4001 vs 4004 mostly restored**
   - Explicit invalid tokens now close with 4004 while missing credentials close with 4001 (`packages/server/src/ws/index.ts:103-110`).
   - Minor edge case: an invalid cookie with `token: null` is still treated as “Token required” because `preAuthUser` is absent, but that is less important than preserving explicit-token semantics.

5. ⚠️ **Code-level cookie `secure` flag added, but deployment makes it ineffective**
   - `COOKIE_OPTIONS.secure` is now `process.env.NODE_ENV === "production"` (`packages/server/src/auth.ts:20-25`).
   - However, the staging deploy systemd unit in `.github/workflows/deploy-staging.yml:81-88` does not set `NODE_ENV=production`, so deployed preview cookies will be sent without `Secure`. See New Issue #1.

6. ❌ **Not addressed — no CORS support for credentialed cross-origin deploys**
   - This is acceptable only if Cove is guaranteed same-origin. If `VITE_COVE_API_URL` points cross-origin, `credentials: "include"` requires explicit CORS headers with `Access-Control-Allow-Credentials: true` and a non-wildcard origin.

## 2. New Issues Found

### 🔴 Blocking: Deployed cookies are likely not `Secure` because deployment does not set `NODE_ENV=production`

`COOKIE_OPTIONS.secure` depends on `process.env.NODE_ENV === "production"` (`packages/server/src/auth.ts:20-25`), but the PR's staging deployment unit sets `PORT`, DB/static paths, `GATEWAY_URL`, `BASE_URL`, and OAuth secrets without setting `NODE_ENV` (`.github/workflows/deploy-staging.yml:81-88`). Running Node directly under systemd does not automatically set `NODE_ENV=production`.

Impact: the PR claims `HttpOnly; Secure; SameSite=Lax`, but in the actual deployed HTTPS preview the auth cookies will likely be `HttpOnly; SameSite=Lax` without `Secure`. Since the cookie contains the bearer session token, this undermines the OAuth-token-leak fix: the token is no longer in the URL, but the browser may still send it on plain HTTP requests if the domain is ever reached over HTTP before redirect/HSTS.

Suggested fix:
- Set `Environment=NODE_ENV=production` in deploy units, and/or
- Make cookie security explicit from deployment config, e.g. derive from `BASE_URL.startsWith("https://")` or default secure unless `NODE_ENV === "development"` / `COOKIE_SECURE=false`.
- Add a test that production/HTTPS config emits `Secure` on `cove-session` and `cove-pending` cookies.

### 🔴 Blocking: WebSocket cookie authentication has no tests

The PR moves browser gateway auth from IDENTIFY token to HTTP upgrade cookie pre-auth (`packages/server/src/ws/index.ts:35-115`). That is a new authentication surface and should be tested directly. Current tests do not prove:

- a valid `cove-session` cookie lets a browser identify with `{ token: null }`;
- no cookie + no token closes with 4001;
- invalid explicit token closes with 4004;
- malformed cookie headers do not crash the upgrade path;
- explicit bot/client token auth still works after the BFF change.

This is exactly the kind of security/auth path that should have positive and negative coverage before merge.

### 🟡 Non-blocking: Register endpoint still accepts `pendingToken` from JSON body

`packages/server/src/routes/register.ts:21-23` still allows `body.pendingToken` as a fallback. The browser no longer sends it, so the main leak is fixed, but keeping it in the public API preserves the old token-in-JS contract and weakens the “browser never sees auth tokens” invariant. Since the commit says no backward compatibility is needed, I recommend removing the body fallback and updating the remaining legacy tests to send `Cookie: cove-pending=...`.

### 🟡 Non-blocking: Cross-origin credentialed deployment still needs a deliberate CORS story

Every client fetch now uses `credentials: "include"` (`packages/client/src/lib/api.ts:14-18`). This is correct for same-origin BFF, but if `VITE_COVE_API_URL` is set to a different origin, browser requests will require CORS with credentials. Either document/enforce same-origin deployment or add credentialed CORS handling.

## 3. Summary

Round 2 fixes most of the original functional blockers: the missing public paths are corrected, HTTP auth tests are much better, pending tokens are no longer exposed to browser code, malformed cookies are handled, logout behavior is safer, and `/api/auth/me` now supports `Bot`. I also verified the CI-equivalent local gates pass: `pnpm -r build`, `pnpm -r exec tsc --noEmit`, `pnpm -r --filter @cove/server exec vitest run` (145 tests), and the esbuild bundle check all succeeded.

The PR is close, but I would not merge yet because the deployed cookie `Secure` flag appears ineffective without `NODE_ENV=production`, and the new WebSocket cookie-auth path still lacks direct tests.

## 4. Verdict

⚠️ **Needs Changes**
