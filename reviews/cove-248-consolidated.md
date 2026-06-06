# Consolidated Review — cove#248: OAuth token leak → BFF cookies

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)

## Summary

Solid security improvement — moving OAuth tokens from URL query strings to `HttpOnly; Secure; SameSite=Lax` cookies is the right fix for #227, and the BFF pattern is well-applied across HTTP and WebSocket. However, all three reviewers flagged blocking issues: a route registration bug that breaks new-user signup, missing test coverage for the new auth surface, and a potential DoS vector in the cookie parser.

**Verdict: ⚠️ Needs Changes** (3/3 reviewers agree)

## Critical Issues (must fix)

### 1. 🔴 `/api/auth/pending-status` and `/api/auth/logout` not in `PUBLIC_PATHS` — breaks new-user signup
*Found by: Nova*

`app.ts` defines `PUBLIC_PATHS` that bypass `requireAuth`, but the two new endpoints aren't listed. A pending user only has a `cove-pending` cookie (no `cove-session`), so `requireAuth` returns 401 before the handler runs. **Result: after Google OAuth, new users land on the login screen instead of the invite-code page.**

Fix: add both to `PUBLIC_PATHS`. Unauthenticated logout that no-ops is standard practice.

### 2. 🔴 No tests for the new auth surface
*Found by: all three reviewers*

Per review standard: "Security/auth paths without tests = Critical." The PR claims 129 tests pass, but those are existing tests. Needed coverage:
- `GET /api/auth/pending-status` — valid cookie, missing cookie, stale cookie cleanup
- `POST /api/auth/logout` — clears both cookies
- `requireAuth` cookie fallback (`auth.ts:58-60`)
- `GET /api/auth/me` cookie path
- WebSocket `verifyClient` cookie pre-auth + IDENTIFY with `null` token
- Negative: bad cookie + no token → 4001

### 3. 🟡 `parseCookies` throws uncaught `URIError` → DoS
*Found by: Vega*

`ws/index.ts` `parseCookies` calls `decodeURIComponent()` without try/catch. A malformed `Cookie: foo=%` header throws `URIError` synchronously in `verifyClient`, potentially crashing the Node process. Wrap in try/catch.

### 4. 🟡 `pendingToken` exposed to JavaScript — weakens BFF invariant
*Found by: Stella, Vega*

The PR's stated invariant is "the browser never sees any auth token," but `/api/auth/pending-status` returns `pendingToken` to JS and the invite-code page sends it back in the request body. The server should read `PENDING_COOKIE` directly during registration instead of round-tripping through the client.

Also: `POST /api/register` still returns `{ token: result }` in the response body. If the client just reloads, change to `{ message: "registered" }`.

## Suggestions (non-blocking)

1. **Legacy localStorage cleanup missing** (Stella, Nova, Vega) — PR body says "cleaned up on load" but `App.tsx` never calls `localStorage.removeItem("cove-token")`. Old tokens remain in users' browsers.

2. **Logout error handling** (Stella, Nova) — `SettingsPanel.tsx:211,224` chains `.then()` after `api.logout()`. If the request fails, the user appears stuck. Use `.finally()` to always clear local state.

3. **`/api/auth/me` duplicates `resolveUser` logic** (Nova) — the handler reimplements header-then-cookie resolution instead of reusing `resolveUser`. Also inconsistent: checks `Bearer` but not `Bot` prefix.

4. **WebSocket close code 4001 vs 4004 collapsed** (Stella, Nova) — previously distinguished missing token (4001) from bad token (4004). Now both return 4001. Minor regression in error specificity for bot clients.

5. **Cookie `secure` from `NODE_ENV`** (Stella, Nova) — if staging deploys forget `NODE_ENV=production`, cookies go over cleartext. Consider deriving from the OAuth redirect URI or the presence of HTTPS.

6. **No CORS for cross-origin deploys** (Nova) — `credentials: "include"` requires `Access-Control-Allow-Credentials: true` if API and SPA are on different origins. Same-origin is fine (documented default), but worth noting.

## Positive Notes

- Clean separation: shared `SESSION_COOKIE` / `PENDING_COOKIE` / `COOKIE_OPTIONS` constants reused everywhere ✅
- `resolveUser` backward-compatible — bots keep using `Authorization: Bot/Bearer` ✅
- WebSocket pre-auth at HTTP upgrade is the right design — no token over WebSocket frame for browsers ✅
- `SameSite=Lax` + `HttpOnly` + `Secure` is correct CSRF/XSS posture ✅
- Appropriately scoped PR — single concern, 193+/64- ✅
- Stale `cove-pending` cookie cleanup branch is a nice touch ✅
