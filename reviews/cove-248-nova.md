# Nova Review — cove#248: OAuth token leak → BFF cookies

## Summary
Solid direction — moving OAuth tokens out of URL query strings into `HttpOnly; Secure; SameSite=Lax` cookies is the correct fix for #227, and the BFF pattern is well-applied across HTTP (`requireAuth`/`/api/auth/me`) and the WebSocket upgrade (`verifyClient` cookie pre-auth + IDENTIFY fallback for bots). However, the new public endpoints are **not registered as public paths**, which breaks new-user registration in practice. There are no tests for the new auth surface, and a couple of cleanup/UX claims in the PR description don't match the code.

## Critical Issues (must fix before merge)

1. **`/api/auth/pending-status` is gated by `requireAuth` → new-user signup is broken.**
   `packages/server/src/app.ts:18` defines `PUBLIC_PATHS = {"/api/auth/google", "/api/auth/callback", "/api/auth/me", "${API_PREFIX}/auth/register"}`. The new `/api/auth/pending-status` route is added in `routes/auth.ts:124` but **not** added to this set, so `app.use("/api/*"...)` runs `requireAuth` first. A pending user has only a `cove-pending` cookie (no `cove-session`), so `requireAuth` returns `401`. The client (`App.tsx:163-181`) treats this as "no session" → falls through to `fetchMe()` (also 401) → catch handler sets `needsSetup: true`. **Result: after Google OAuth, new users land back on the login screen instead of the invite-code page.** Old flow worked because the pending token rode in the URL.
   - Fix: add `"/api/auth/pending-status"` to `PUBLIC_PATHS` (and probably `/api/auth/logout` too, see #2).

2. **`/api/auth/logout` is also gated by `requireAuth`.**
   Same root cause — not in `PUBLIC_PATHS`. Authenticated users will succeed, but:
   - A user whose session cookie has already expired/been revoked server-side cannot clear stale cookies via logout (gets 401, cookies remain).
   - A pending user can't abandon the pending state cleanly.
   Recommend adding `/api/auth/logout` to `PUBLIC_PATHS`. Logout that no-ops when unauthenticated is the standard pattern.

3. **No tests for the new auth surface.**
   Per the team's review standard, "Security/auth paths without tests = Critical." There are no tests in `packages/server/src/__tests__/` for:
   - `GET /api/auth/pending-status` (happy path, missing cookie, stale cookie cleanup branch at `auth.ts:131-134`)
   - `POST /api/auth/logout`
   - `requireAuth` cookie fallback in `auth.ts:58-60`
   - WebSocket `verifyClient` cookie pre-auth path (`ws/index.ts:29-44`) and the new IDENTIFY-with-`null`-token branch (`ws/index.ts:80-98`)
   The PR body claims "129 tests pass" — but those are existing tests. Negative cases (bad cookie, mismatched token, no token + no cookie → 4001) need explicit coverage given this is a security refactor.

## Product Impact

- **Breaks new-user registration** (see Critical #1). Existing users who already have a session cookie from a future build are fine; everyone signing up after deploy is stuck.
- **Cross-origin deployments will break.** `api.ts:14-19` adds `credentials: "include"` to every request. If `VITE_COVE_API_URL` is set to a different origin (e.g. `api.cove.example.com` while the SPA lives on `cove.example.com`), browsers will reject the response unless the server emits `Access-Control-Allow-Origin: <exact origin>` + `Access-Control-Allow-Credentials: true`. I see no CORS middleware in `app.ts`. Same-origin deploys are fine (which is the documented default), but flag this in the PR description if any user runs split origins.
- **7-day cookie `maxAge` vs. non-expiring DB tokens** (`auth.ts:18-25`): users will get bounced back to Google OAuth every 7 days even though the underlying DB token is permanent. Probably intentional; worth confirming with product.
- **Cookie `secure` defaults to false in dev** (`NODE_ENV !== "production"`). Correct for `http://localhost`, but if anyone deploys without `NODE_ENV=production`, cookies will go over the wire in cleartext. Consider hard-failing OAuth at boot if `NODE_ENV !== "production"` and the OAuth redirect URI is https.

## Suggestions (non-blocking)

- **WebSocket Origin check.** `ws/index.ts:29` accepts the upgrade purely on cookie presence; no Origin header validation. `SameSite=Lax` should prevent the cookie being sent on cross-site WS subresource handshakes, but defense-in-depth: reject `verifyClient` when `req.headers.origin` is set and isn't an allowed value.
- **Legacy `localStorage` cleanup is missing.** PR body says "Token never in localStorage (cleaned up on load)". `useUserStore.ts` removed the `removeItem("cove-token")` calls, and `App.tsx:149-152` only strips URL params — it does **not** delete the existing `cove-token` / `cove-user` keys from localStorage left over from prior versions. Add an explicit `localStorage.removeItem("cove-token"); localStorage.removeItem("cove-user");` on mount so the claim is true.
- **`api.logout()` has no error handling at call sites** (`SettingsPanel.tsx:210, 224`). If the request fails, the chained `.then(() => { logout(); close(); })` never runs — the panel just sits there with the user still "logged in" client-side. Use `.finally()` or `.catch()` to always clear local state.
- **`/api/auth/me` cookie fallback duplicates `requireAuth` logic.** The handler at `routes/auth.ts:96-122` reimplements header-then-cookie token resolution, while `auth.ts:resolveUser` already does this. Consider just removing `/api/auth/me` from `PUBLIC_PATHS` and using `c.get("botUser")` so there's one code path.
- **`session.close(4001, "Token required")` for both missing-token and bad-token cases** (`ws/index.ts:96-98`) collapses what was previously a distinction (4001 vs 4004 "Authentication failed"). Minor regression in error specificity — bot clients debugging bad tokens will find this confusing.
- **`parseCookies` in `ws/index.ts:14-22`** is fine but you could use `cookie` from `hono`'s deps via dynamic import or just `import { parse } from "cookie"`. Not worth a dependency just for this.

## Positive Notes

- Clean separation: shared `SESSION_COOKIE` / `PENDING_COOKIE` / `COOKIE_OPTIONS` constants in `auth.ts` reused everywhere ✅
- `resolveUser` is backward-compatible — bots keep using `Authorization: Bot/Bearer ...`, no breakage ✅
- WebSocket pre-auth at HTTP upgrade is the right design — no token over the WebSocket frame at all for browser clients ✅
- Stale `cove-pending` cookie cleanup branch (`auth.ts:131-134`) is a nice touch ✅
- `SameSite=Lax` (not `None`) + `HttpOnly` + `Secure` is the right CSRF/XSS posture for a same-origin SPA ✅
- The PR is appropriately scoped — 193+/64-, single concern ✅

## Verdict

⚠️ **Needs Changes** — Critical #1 (`pending-status` not in `PUBLIC_PATHS`) breaks new-user signup. Add `pending-status` and `logout` to `PUBLIC_PATHS`, add tests for the new auth surface and WS cookie path, then re-review.
