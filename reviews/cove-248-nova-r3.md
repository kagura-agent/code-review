# 🌠 Nova — Round 3 Review: cove PR #248

**PR:** fix: OAuth token leak — BFF pattern with HttpOnly cookies (closes #227)
**Stats:** 13 files, +708 / −94, 129 tests pass per author

---

## 1. Round 2 Issue Status

### 🟡→✅ R2-1: WebSocket auth path has no tests — **Fixed**
New file `packages/server/src/__tests__/ws-auth.test.ts` (249 lines) spins up a real HTTP server + `setupGateway` and covers the full IDENTIFY matrix:
- Browser flow: valid `cove-session` cookie + `{ token: null }` → READY ✅
- Bot flow: no cookie + valid token → READY ✅
- No cookie + null token → close `4001 Token required` ✅
- No cookie + invalid token → close `4004 Authentication failed` ✅
- Malformed cookie (`%invalid%encoding`) → connection survives, bot token fallback works ✅

The `MessageCollector` design (buffer-on-construct) correctly prevents the open/HELLO race. This is genuinely thorough — better than I asked for.

### 🟡→✅ R2-2: Legacy localStorage tokens — **Fixed**
`App.tsx` now unconditionally calls on every mount:
```ts
localStorage.removeItem("cove-token");
localStorage.removeItem("cove-user");
```
Any returning user with a stale token blob in localStorage gets it wiped on first load. XSS surface eliminated. (The token row in the DB is still valid until logout/rotation, but that's a separate hygiene matter.)

### 🟡→✅ R2-3: `NODE_ENV` / Secure flag — **Fixed (defensive default)**
`auth.ts:22` now reads:
```ts
secure: process.env.NODE_ENV !== "development",
```
Inverted default — only an *explicit* `NODE_ENV=development` disables `Secure`. Missing/unset/`production`/`staging` all get secure cookies. This is the right safe-by-default fix.

### 🟢→✅ R2-4: Register body fallback — **Fixed**
`routes/register.ts`:
```ts
const body = await c.req.json<{ inviteCode?: string }>();
const { inviteCode } = body;
const pendingToken = getCookie(c, PENDING_COOKIE);
```
`pendingToken` is no longer in the body type or destructure. Cookie-only.

### 🟢→✅ R2-5: WS token-fallthrough comment — **Fixed**
`ws/index.ts:99-103` now has a clear explanation:
```ts
// Explicit token invalid but cookie pre-auth exists: use cookie identity.
// This handles browser clients sending { token: null } over a cookie-authenticated socket.
```
And the 4001 vs 4004 branching is explicit and commented (`// Distinguish: no credentials at all vs invalid token`).

### 🟢→❌ R2-6: `/api/auth/me` duplicates `resolveUser` — **Not addressed** ⬆️ escalate to 🟡
`routes/auth.ts:98-124` still hand-rolls the same Authorization parsing (`Bearer`/`Bot`) + cookie fallback that `auth.ts:resolveUser` already does. It even re-queries `users` by raw SQL instead of going through `UsersRepo.findByToken`. Two consequences:
1. Drift risk: any future auth scheme change (e.g., add `Token ` prefix, rotate cookie name) must be made in **two** places.
2. New `auth.test.ts` already exercises both Bearer and Bot prefixes on `/me` — meaning the duplicated logic is *protected* by tests but the duplication itself remains.

**Fix:** replace the body with `const user = resolveUser(users, c.req.header("Authorization"), getCookie(c, SESSION_COOKIE));` (the repo signature is already a perfect match).

Escalating because we now have a *third* place auth resolution lives (resolveUser, `/me`, WS verifyClient), each subtly different. The WS one is justified (no hono context), `/me` is not.

### 🟢→❌ R2-7: Stray blank line in `api.ts` logout — **Not addressed** (still 🟢)
Diff shows it's still there:
```ts
export async function logout() {
  await api<{ message: string }>("/api/auth/logout", { method: "POST" });

}
```
Trivial — but it was explicitly flagged in R2 and ignored. Worth a `lint --fix` pass.

### 🟢→❌ R2-8: CORS for cross-origin deploys — **Not addressed** (still 🟢)
No `hono/cors` middleware added. App-level grep for `cors|CORS` in `packages/server/src/` returns zero hits. Currently relies on same-origin deployment. If `VITE_COVE_API_URL` is ever set to a different origin in production, `credentials: "include"` requests will be rejected by the browser without an explicit CORS allowlist. Probably fine for current Caddy-fronted single-origin deploys, but should at least get a code comment or deployment-doc note since `VITE_COVE_API_URL` *exists* as an env knob.

---

## 2. New Issues Found in R3

### 🟢 N1: Logout endpoint message inconsistency
`routes/auth.ts:144`: `return c.json({ message: "ok" });`
`routes/register.ts:84`: `return c.json({ message: "registered" });`
Test for logout (`auth.test.ts:107`) asserts `{ message: "ok" }`. Not a bug, just inconsistent contract — neither value is documented or consumed. Consider standardizing on `{ ok: true }` or returning `204 No Content`.

### 🟢 N2: `verifyClient` does a synchronous DB query per upgrade
`ws/index.ts:30-38` calls `users.findByToken(sessionToken)` inside `verifyClient` for every WS upgrade attempt. With `better-sqlite3` this is fine (sync, in-process, fast), but it's a public unauthenticated endpoint — any opened socket triggers a DB hit. Not exploitable as-is (better-sqlite3 reads are microseconds), but worth noting if the auth backend ever becomes async/remote.

### 🟢 N3: `verifyClient` swallows `bot` field type ambiguity
`row.bot` from `UsersRepo.findByToken` is presumably `number` (0/1 from SQLite), but the `__coveUser` cast types it as `boolean`. The downstream `session.identify(user, ...)` then accepts whatever it gets. Same pattern exists in the IDENTIFY handler. Not a runtime bug but a latent typing lie — `users.test.ts`-level fixtures with `bot: 1` would pass and propagate as truthy `boolean`. Worth a `bot: row.bot === 1` normalization in both places.

### 🟢 N4: Tests assert presence but not attributes on Set-Cookie
`auth.test.ts:62-66` checks `setCookie` contains `cove-pending`, but never verifies `HttpOnly`, `Secure`, `SameSite=Lax`, or `Max-Age`. These attributes are the *entire point* of the BFF migration. A future regression that drops `HttpOnly` would still pass the test. Recommend a single assertion per success path:
```ts
expect(setCookieHeader).toMatch(/HttpOnly/i);
expect(setCookieHeader).toMatch(/SameSite=Lax/i);
```

### 🟢 N5: WS pre-auth user is mutable state on the request object
`(request as ... & { __coveUser?: ... }).__coveUser = ...` mutates the raw `IncomingMessage`. Works, idiomatic for Node, but a `WeakMap<IncomingMessage, AuthUser>` would be cleaner and avoid the type cast on both write and read.

---

## 3. Summary

R3 is a substantial response to R2. Five of eight issues — including all three 🟡 — are properly fixed, with strong test coverage that I genuinely appreciate (the WS integration suite is well-engineered). The remaining gaps are:

- **One escalated**: `/api/auth/me` duplication (R2-6) → now 🟡 because a *third* auth-resolution site has been introduced (WS verifyClient), so the drift surface grew.
- **Two ignored**: stray blank line (R2-7), CORS (R2-8) — both 🟢, trivial.

Security posture of the merged result is sound:
- Cookies are `HttpOnly; Secure (default); SameSite=Lax` ✅
- Token never in URL, never in localStorage (cleaned on every load) ✅
- WS pre-authenticates at upgrade ✅
- Body fallback for `pendingToken` removed ✅
- Bot Authorization-header path preserved ✅

The BFF refactor is complete and defensible. The one *should-fix-before-merge* item is R2-6 (resolveUser duplication) — it's a 4-line cleanup that retires an entire class of future regression.

---

## 4. Verdict

⚠️ **Needs Minor Changes**

Blocking:
- **R2-6**: refactor `/api/auth/me` to use `resolveUser` — drift surface grew, this is the round to close it.

Non-blocking but please:
- **R2-7**: drop the stray blank line.
- **N4**: tighten one cookie-attribute assertion to lock in the security contract.

Everything else is acceptable as follow-up. Once R2-6 is addressed I'm a clean ✅.

— 🌠 Nova
