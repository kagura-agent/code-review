# 🌠 Nova — Round 2 Review: PR #248 (cove)

**PR**: fix: OAuth token leak — BFF pattern with HttpOnly cookies (closes #227)
**Round**: 2 (re-review after author updates)
**Diff size**: +441 / −81, 12 files

---

## 1. Round 1 Issue Status

### Critical

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| C1 | `/api/auth/pending-status` & `/api/auth/logout` not in `PUBLIC_PATHS` (breaks new-user signup) | ✅ **Fixed** | `app.ts` now includes both: `"/api/auth/pending-status", "/api/auth/logout"`. New test `"is accessible without session auth (public path)"` asserts it. |
| C2 | No tests for new auth surface | ✅ **Fixed** | New `packages/server/src/__tests__/auth.test.ts` (228 lines) covers: pending-status (cookie present/absent/stale), logout (cookie clearing), `requireAuth` with cookie, `/api/auth/me` with Bearer/Bot/cookie/no-creds/invalid-token, register cookie flow & no-token-leak assertion. Good coverage of the HTTP surface. |
| C3 | `parseCookies` throws uncaught `URIError` → DoS | ✅ **Fixed** | `ws/index.ts` wraps `decodeURIComponent` in `try/catch`, silently skips malformed cookie values. Connection survives. |
| C4 | `pendingToken` exposed to JavaScript; `register` returns `{ token }` | ✅ **Fixed** | OAuth callback sets `cove-pending` cookie + redirects to `/` (no query param). `InviteCodePage` no longer takes a `pendingToken` prop and no longer reads it from body. `register` returns `{ message: "registered" }` and sets `cove-session` cookie. Test explicitly asserts `expect(data).not.toHaveProperty("token")`. The BFF invariant ("browser never sees the token") now holds end-to-end. |

### Suggestions

| # | Suggestion | Status | Notes |
|---|------------|--------|-------|
| S1 | Legacy localStorage cleanup missing | ❌ **Not addressed** | Old clients had `localStorage["cove-token"]` and `localStorage["cove-user"]`. The new `useUserStore.logout()` no longer touches localStorage, and `App.tsx` initial load no longer reads/removes it either. Existing users upgrading will carry stale entries forever. Severity remains **low** — they're inert (nothing reads them now), but a one-shot cleanup on `App` mount (`localStorage.removeItem("cove-token"); localStorage.removeItem("cove-user")`) is two lines. *Not escalated (still cosmetic).* |
| S2 | Logout missing `.catch()/.finally()` | ✅ **Fixed** | Both call sites: `api.logout().catch(() => {}).finally(() => { logout(); close(); })`. Local state is cleared even if the server call fails. |
| S3 | `/api/auth/me` duplicates `resolveUser`; doesn't handle `Bot` prefix | ⚠️ **Partially addressed** | The handler now accepts `Bot`, `Bearer`, and the session cookie (tests confirm). But it still implements the parsing inline instead of delegating to the now-cookie-aware `resolveUser(users, authHeader, cookieToken)`. Two parsers for the same logic = future drift risk. *Not escalated — behaviorally correct.* Cleanup suggestion: `const user = resolveUser(usersRepo, c.req.header("Authorization"), getCookie(c, SESSION_COOKIE));` |
| S4 | WS close codes 4001 vs 4004 collapsed | ✅ **Fixed** | `ws/index.ts` distinguishes: no creds → `4001 "Token required"`, invalid token → `4004 "Authentication failed"`. |
| S5 | Cookie `secure` derived from `NODE_ENV` | ⚠️ **Not addressed** | `COOKIE_OPTIONS.secure = process.env.NODE_ENV === "production"`. Still implicit and easy to break in staging/test deployments where `NODE_ENV` may not be set to `"production"`. Lower priority since the staging deploys appear to use Caddy + HTTPS — but an explicit `COVE_COOKIE_SECURE` env override would be one-line and removes the foot-gun. *Not escalated.* |
| S6 | No CORS for cross-origin deploys | ❌ **Not addressed** | Still no `cors` middleware. Same-origin deploy works (Caddy serves both at `cove.kagura-agent.com`), so this is only a blocker if anyone splits the API onto a subdomain. Documenting the same-origin assumption in `app.ts` or the README would suffice for now. *Not escalated — same-origin remains the supported topology.* |

---

## 2. New Issues Found

### 🟡 N1 — WebSocket auth path has no test coverage
`ws/index.ts` is the most security-critical change in this PR (cookie pre-auth at HTTP upgrade, IDENTIFY now accepts `token: null`, dual code paths for bot vs browser, fall-through logic for `preAuthUser`). It has **zero tests**. Round 1 specifically called out "no tests on auth surface" as critical; the new tests cover only HTTP. The WS branches that need coverage:
- Browser flow: connect with valid `cove-session` cookie → IDENTIFY with `{ token: null }` → READY
- Bot flow: connect with no cookie → IDENTIFY with valid token → READY
- Negative: cookie token revoked between upgrade and IDENTIFY → 4004
- Negative: malformed cookie header → connection still opens, IDENTIFY without token → 4001
- Negative: invalid explicit token even when cookie pre-auth succeeded? (currently falls through to `preAuthUser` — is that intended?) See N2.

**Recommend**: add a `ws.test.ts` exercising at least the happy paths and 4001/4004 distinction.

### 🟡 N2 — Token-fallthrough behavior is silent and surprising
In `ws/index.ts` IDENTIFY handler:
```ts
if (token) {
  const row = users.findByToken(token);
  if (row) user = { id: row.id, ... };
}
if (!user && preAuthUser) user = preAuthUser;
```
If a browser sends `{ token: "garbage" }` over a cookie-authenticated socket, the bad token is *silently ignored* and the cookie identity is used. That's probably the intended UX (browser code sends `token: null` anyway), but an attacker injecting a target user's token in IDENTIFY would also be silently downgraded to their own cookie identity — fine. Worth a one-line comment so the next reader doesn't "fix" it into a 4004.

### 🟢 N3 — Pending registration TTL mismatch
`PENDING_COOKIE` has `maxAge: 604800` (7 days), but `pending_registrations` rows have no documented TTL — `/api/auth/pending-status` only checks existence in the DB. If the DB row is cleaned up by a separate process the cookie still claims `pending: true` until the lookup misses and the handler clears it. That self-heal works (existing test confirms), so no action needed; just flagging.

### 🟢 N4 — `api.ts` stray blank line
```ts
export async function logout() {
  await api<...>("/api/auth/logout", { method: "POST" });

}
```
Trailing blank inside function body. Cosmetic.

### 🟢 N5 — `api.test.ts` still passes `pendingToken` in body
The pre-existing register test on line 1050 still sends `pendingToken: "tok-1"` in the JSON body, exercising the backward-compat path. The new `auth.test.ts` covers the cookie path. Backward-compat fallback is reasonable for one release; consider scheduling its removal (`TODO: remove body fallback in vX.Y`) to lock the BFF invariant on the server side too — right now a malicious form-post containing `pendingToken` could still complete registration without a cookie. Risk is low (attacker needs the pending token already), but the body fallback weakens the invariant.

---

## 3. Summary

The author addressed **all 4 Critical items** properly. The redirect→cookie flow now genuinely keeps the token out of every browser-accessible surface (URL, localStorage, JS), and the new HTTP test suite validates that invariant explicitly (`not.toHaveProperty("token")`). The DoS in `parseCookies` is fixed. `PUBLIC_PATHS` no longer locks out new signups.

Of the 6 suggestions: 2 fixed cleanly (S2 logout error handling, S4 WS close codes), 1 partially (S3 `/me` works for all schemes but still duplicates parsing), 3 deferred (S1 localStorage cleanup, S5 explicit secure-cookie env, S6 CORS) — all defensible to defer.

The remaining gap worth raising before merge is **N1: no WebSocket tests**. The WS handshake is the trickiest part of the BFF — dual auth source, pre-auth state stashed on the IncomingMessage, fall-through logic. It deserves at least a smoke test now while the author has context.

## 4. Verdict

⚠️ **Needs Changes (minor)** — block on N1 (add WS auth test). Everything else is either fixed or acceptable to defer with a follow-up issue. If WS tests are out of scope for this PR, file a tracking issue and ✅ ship.
