# 🌠 Nova — R4 Re-Review · kagura-agent/cove#264

**PR**: Session TTL with lazy + periodic cleanup
**Round**: 4 (escalation review)
**Verdict**: ❌ **Needs Changes** — all four R3 issues still unaddressed, severities escalated.

---

## R3 Issue Status

### 🔴 [ESCALATED from 🟡] Sliding refresh threshold breaks for short TTLs — ❌ Unaddressed

`packages/server/src/auth.ts:65`

```ts
const refreshThreshold = SESSION_TTL_MS - 24 * 60 * 60 * 1000; // refresh after 1 day of use
if (remainingMs < refreshThreshold) {
  users.refreshTTL(user.id);
}
```

R3 prescribed:
```ts
const refreshThreshold = Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86400000);
```

Status: **No change**. With `SESSION_TTL_MS=3600000` (1h test config) the threshold is `-82,800,000`, so `remainingMs < refreshThreshold` is always false → sliding refresh is silently disabled. Worse, with `SESSION_TTL_MS < 24h` the feature appears to work but never triggers, which is exactly the kind of latent failure that escapes tests using the default 7-day value. **This is now a correctness bug for any deployment using non-default TTL** — escalated to 🔴.

**Fix:** apply R3's `Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86400000)`, or simpler: `SESSION_TTL_MS / 2`.

---

### 🔴 [ESCALATED from 🟡] No index on `expires_at` — ❌ Unaddressed

`packages/server/src/db/migrations/v6-session-ttl.ts`

```ts
addColumnIfMissing(db, "users", "expires_at", "INTEGER DEFAULT NULL");
// ...backfill UPDATE...
// no CREATE INDEX
```

Cleanup runs every hour:
```ts
"UPDATE users SET token = NULL, expires_at = NULL WHERE expires_at IS NOT NULL AND expires_at < ?"
```

This is a full-table scan on `users` every hour, plus another scan in the lazy-cleanup `findByToken` path is fine (it's keyed by `token`), but the periodic cleanup will degrade linearly with user count. Two rounds without a fix = escalate 🔴.

**Fix:** in v6 migration:
```ts
db.exec("CREATE INDEX IF NOT EXISTS idx_users_expires_at ON users(expires_at) WHERE expires_at IS NOT NULL");
```
(Partial index avoids indexing the many `NULL` bot rows.)

---

### 🔴 [ESCALATED from 🟡] Cleanup is silent — ❌ Unaddressed

`packages/server/src/index.ts:26-30`

```ts
const sessionCleanupTimer = setInterval(() => {
  repos.users.cleanupExpired();
}, SESSION_CLEANUP_INTERVAL_MS);
```

Return value discarded. No observability whatsoever — if cleanup throws, it'll bubble as an unhandled rejection and may crash the process; if it succeeds, operators have no signal it's running. Third round unaddressed → 🔴.

**Fix:**
```ts
const sessionCleanupTimer = setInterval(() => {
  try {
    const removed = repos.users.cleanupExpired();
    if (removed > 0) console.log(`🧹 Session cleanup: cleared ${removed} expired tokens`);
  } catch (err) {
    console.error("Session cleanup failed:", err);
  }
}, SESSION_CLEANUP_INTERVAL_MS);
```

---

### 🟡 Cookie not reissued on sliding refresh — ❌ Unaddressed

`packages/server/src/auth.ts:60-69`

`resolveUser` extends server-side `expires_at` via `refreshTTL`, but does not call `setCookie`. So for cookie-authenticated browsers:

- DB `expires_at`: rolls forward 7 days on each active day ✅
- Browser cookie `Max-Age`: fixed at the value set during OAuth login → expires after 7 wall-clock days regardless of activity ❌

Net effect: sliding session is broken for the browser flow — exactly the surface where it matters most. Header/Bearer clients don't care because they don't use cookies. Kept at 🟡 (the feature is silently degraded, not destroyed), but this is the second round it's been ignored. **One more round and it escalates to 🔴.**

**Fix:** `resolveUser` needs the Hono `Context` to re-`setCookie` after refresh, or refactor sliding refresh into a middleware that has `c` and can reissue. Minimum viable:
```ts
// in the middleware that calls resolveUser, after success:
if (refreshed) setCookie(c, SESSION_COOKIE, token, COOKIE_OPTIONS);
```
(Requires `resolveUser` to return a `{ user, refreshed }` tuple, or have the middleware compare `user.expires_at` before/after.)

---

## New Issues (Fresh Eyes)

### 🟡 N1 — v6 backfill hardcodes 7 days instead of `SESSION_TTL_MS`

`v6-session-ttl.ts:9-13`

```ts
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const gracePeriod = Date.now() + SEVEN_DAYS_MS;
```

If an operator deploys with `SESSION_TTL_MS=3600000` (1h), every existing human user still gets a 7-day grace window — contradicting the configured policy. Inconsistent with `users.ts` `create()` which uses `SESSION_TTL_MS`. Migration cannot import from `repos/users.ts` cleanly (layer inversion), so either inline `parseInt(process.env.SESSION_TTL_MS ?? "604800000", 10)` here or extract a shared constant module.

### 🟡 N2 — Default-bot footgun in `users.create()`

`repos/users.ts:48`

```ts
const isBot = opts.bot !== false;
```

If a caller passes `opts.bot === undefined`, this evaluates **true** → user is created as a bot with `expires_at=null` (never expires). This is pre-existing behavior preserved from before, but with the TTL feature it now has security implications: any caller that forgets to pass `bot: false` creates an immortal session. Recommend `const isBot = opts.bot === true;` (explicit opt-in to bot) or at minimum a JSDoc warning.

### 🟢 N3 — OAuth callback double-write to `expires_at`

`routes/auth.ts:79-82`

```ts
const token = crypto.randomUUID();
db.prepare("UPDATE users SET username = ?, avatar = ?, google_id = ?, email = ?, token = ?, updated_at = ? WHERE id = ?")
  .run(...);
usersRepo.refreshTTL(existing.id); // separate UPDATE
```

Two SQL UPDATEs where one would do — and they're not transactional, so a crash between them leaves a fresh token with stale `expires_at`. Combine: include `expires_at = ?` in the first UPDATE with `Date.now() + SESSION_TTL_MS`.

### 🟢 N4 — `findByToken` lazy cleanup race

`repos/users.ts:103-106`

```ts
if (row.expires_at !== null && row.expires_at < Date.now()) {
  this.db.prepare("UPDATE users SET token = NULL, expires_at = NULL WHERE token = ?").run(token);
  return null;
}
```

If two concurrent requests hit an expired token simultaneously, both run the UPDATE. Harmless (idempotent) but worth a `AND expires_at IS NOT NULL AND expires_at < ?` guard so it's a true no-op when already cleared.

### 🟢 N5 — Test `bot=true` default doesn't match real callers

`session-ttl.test.ts:131` covers `bot: true` explicitly — good. But no test exercises the `opts.bot === undefined` path, which is the production footgun in N2. Add:

```ts
const u = repos.users.create({ username: "Forgot" }); // no bot key
expect(u.bot).toBe(true); // ← documents footgun
```

### 🟢 N6 — `refreshTTL` calls `Date.now()` twice

Minor: capture once for atomicity.

---

## Testing

✅ New `session-ttl.test.ts` covers: expired→401, bot never expires, cleanup selectivity, create() sets expires_at, refreshTTL extends, `/me` returns expires_at.

❌ Missing:
- Sliding refresh actually triggers (would have caught R3 issue #1 — set `SESSION_TTL_MS` env to small value and assert `refreshTTL` is called within a stale window).
- Cookie reissue after sliding refresh (would have caught R3 issue #4 — assert `Set-Cookie` header on `/api/auth/me` when token is near expiry).
- Index existence test in migration tests.
- `cleanupExpired()` logging behavior (mock console).

---

## Summary

| R3 Issue | R4 Status | New Severity |
|---|---|---|
| Sliding refresh threshold | ❌ Unaddressed | 🔴 |
| No `expires_at` index | ❌ Unaddressed | 🔴 |
| Cleanup no logs | ❌ Unaddressed | 🔴 |
| Cookie not reissued | ❌ Unaddressed | 🟡 (next round → 🔴) |

Plus 2 new 🟡 (N1 hardcoded backfill, N2 default-bot footgun) and 4 🟢 polish items.

**Verdict: ❌ Needs Changes.** Three rounds of unaddressed feedback have promoted yellows to reds. The PR ships the TTL feature in a state where the headline benefit (sliding session for browser users) doesn't actually work end-to-end, and operational visibility is zero. Do not merge until R3 items 1–4 are resolved and N1/N2 are at minimum acknowledged.
