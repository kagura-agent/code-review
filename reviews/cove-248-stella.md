# PR #248 Review — Stella

## Summary
This PR moves Cove’s browser login flow in the right direction: OAuth callbacks no longer redirect with bearer tokens in the URL, API fetches include cookies, and the WebSocket gateway can authenticate browser sessions from the upgrade cookie while preserving explicit token IDENTIFY for bot clients. However, this is a security-sensitive auth change and the current diff has two merge-blocking problems: the new cookie auth/session behavior is effectively untested, and the pending-registration token is still handed back to JavaScript, which weakens the BFF/HttpOnly security goal the PR is trying to establish.

## Critical Issues

1. **Missing positive/negative tests for the new cookie-based auth surface** — `packages/server/src/routes/auth.ts:84`, `packages/server/src/routes/auth.ts:124`, `packages/server/src/routes/auth.ts:140`, `packages/server/src/routes/register.ts:77`, `packages/server/src/ws/index.ts:29`, `packages/server/src/ws/index.ts:80`; existing tests at `packages/server/src/__tests__/api.test.ts:1043-1122` still only verify legacy invite-code registration behavior and do not assert `Set-Cookie`/cookie deletion.  
   This PR changes authentication, session storage, logout, and WebSocket authorization. Per the review standard, security/auth paths without tests are blocking. Please add tests that cover at least:
   - `GET /api/auth/me` succeeds with a valid `cove-session` cookie and fails with missing/invalid cookies.
   - Existing bot/header auth still works for API routes after the cookie fallback change.
   - OAuth/register flow sets `cove-session`, clears `cove-pending`, and does **not** set a session cookie on invalid invite/pending token.
   - `GET /api/auth/pending-status` handles valid, missing, and invalid pending cookies, including invalid-cookie cleanup.
   - `POST /api/auth/logout` clears both cookies.
   - Gateway cookie auth: valid `cove-session` + browser `IDENTIFY { token: null }` succeeds; missing/invalid cookie + null token fails; explicit token IDENTIFY still succeeds for bots.

2. **Pending-registration token is still exposed to browser JavaScript** — `packages/server/src/routes/auth.ts:137`, `packages/client/src/App.tsx:157-160`, `packages/client/src/App.tsx:80-83`, `packages/server/src/routes/register.ts:77-81`.  
   The PR’s stated invariant is “the browser never sees any auth token,” but `/api/auth/pending-status` returns `pendingToken` to JS and the invite-code page sends it back in the request body. A pending token is not a full session bearer token, but it is still a registration secret that can be stolen by XSS or captured in request logging/telemetry, and it partially defeats the HttpOnly-cookie design. Prefer returning only `{ pending: true }` from `pending-status` and making `POST /auth/register` read `PENDING_COOKIE` server-side instead of accepting `pendingToken` from the client. Keep body `pendingToken` support only if needed for explicit legacy compatibility, and test that the cookie path is the browser path.

## Product Impact
- Existing OAuth users should benefit from no token-in-URL/localStorage exposure, which is a strong user-facing security improvement.
- New-user invite completion currently still depends on a JS-visible pending token. If that token is lost, stolen, or mishandled, users may see broken invite completion or potential account-claim risk during registration.
- Logout now waits for the server call before updating UI (`packages/client/src/components/SettingsPanel.tsx:211` and `:224`). If the network request fails, the user may appear unable to sign out locally. Consider clearing local UI state in a `finally` block while still attempting server cookie deletion.

## Suggestions
- In `packages/client/src/lib/api.ts:88-91`, remove the extra blank line and consider having `logout()` call `resetGuildId()` or documenting that callers must do it; otherwise a future same-tab login could reuse a stale cached guild id.
- Consider making cookie options derive `secure` from the public base URL/proxy deployment rather than only `NODE_ENV` (`packages/server/src/auth.ts:15-21`). Staging/prod service definitions often forget `NODE_ENV=production`, and auth cookies should be `Secure` whenever served over HTTPS.
- `packages/server/src/ws/index.ts:97-100` now returns close code `4001 Token required` for both missing and invalid credentials. That is acceptable, but if clients or tests rely on `4004 Authentication failed`, document the intentional compatibility change.

## Positive Notes
- The main OAuth callback no longer redirects with `?token=...`, which directly addresses the original leak vector.
- `HttpOnly`, `SameSite=Lax`, path-scoped cookies are the right architectural direction for a browser BFF flow.
- Keeping explicit token IDENTIFY for bot clients is a good backward-compatibility decision.
- The client-side fetch wrapper consistently uses `credentials: "include"`, reducing the chance of missing cookie auth on individual API calls.

## Verdict
⚠️ Needs Changes

I attempted to run the server test suite locally, but the local checkout’s native `better-sqlite3` addon failed to load (`Module did not self-register`), so test execution was blocked by environment state rather than this diff.