# 🌠 Nova — R5 Re-Review of cove#264 (Session TTL)

**Verdict: ✅ Approve with minor follow-ups**

R4 ratchet check: every escalated R4 item is genuinely fixed in code (not just claimed). On a fresh pass I found a couple of small hygiene issues, but nothing block-merge.

---

## R4 Ratchet Check

### 🔴 Escalated from R3
1. **Sliding refresh threshold breaks for short TTLs** — ✅ **Fixed**
   `auth.ts`:
   ```ts
   const refreshThreshold = Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86_400_000);
   ```
   Exactly the proposed fix. For 7d TTL → 6d (matches old behavior); for 1h TTL → 30m. No more negative threshold.

2. **No `expires_at` index** — ✅ **Fixed**
   `v6-session-ttl.ts`:
   ```sql
   CREATE INDEX IF NOT EXISTS idx_users_expires_at ON users(expires_at) WHERE expires_at IS NOT NULL
   ```
   Partial index — better than the proposed full index (skips bot rows). Cleanup query `WHERE expires_at IS NOT NULL AND expires_at < ?` will use it.

3. **Cleanup has no logging** — ✅ **Fixed**
   `index.ts`:
   ```ts
   try {
     const removed = repos.users.cleanupExpired();
     if (removed > 0) console.log(`🧹 Session cleanup: cleared ${removed} expired tokens`);
   } catch (err) { console.error('Session cleanup failed:', err); }
   ```
   try/catch + count log. Good.

4. **Cookie not reissued on sliding refresh** — ✅ **Fixed**
   Both `requireAuth` and `/api/auth/me` now `setCookie(...)` when `result.refreshed && cookieToken`. The guard correctly avoids reissuing for Bearer-header-only callers.

### 🔴 New in R4
5. **OAuth token + expires_at non-atomic** — ✅ **Fixed**
   `routes/auth.ts` now:
   ```ts
   db.prepare("UPDATE users SET username=?, avatar=?, google_id=?, email=?, token=?, expires_at=?, updated_at=? WHERE id=?")
   ```
   Single UPDATE. Bonus: also addresses the latent bug where `existing.token ?? crypto.randomUUID()` would resurrect an old (potentially compromised) token — now always rotates on OAuth login. 👍

### 🟡 New in R4
6. **v6 backfill hardcoded 7d** — ✅ **Fixed**
   `v6-session-ttl.ts` reads `process.env.SESSION_TTL_MS`. (See N2 below for a residual concern.)

7. **Default bot footgun (`opts.bot !== false`)** — ✅ **Fixed**
   `repos/users.ts`:
   ```ts
   const isBot = opts.bot === true;
   ```
   Now defaults to **human**. Tests in `api.test.ts` correctly updated to pass explicit `bot: true`. This is the right semantic flip.

**All 7 R4 items addressed. No escalations needed.**

---

## Fresh Findings (R5)

### 🟡 Medium

**N1. v6 backfill grants fresh full TTL to inactive users.**
`v6-session-ttl.ts`:
```ts
const gracePeriod = Date.now() + SESSION_TTL;
db.prepare("UPDATE users SET expires_at = ? WHERE bot = 0 AND expires_at IS NULL").run(gracePeriod);
```
Every existing human — including users dormant for months — gets a fresh 7-day session at deploy time. The PR description says "`updated_at + 7 days`" but the code uses `Date.now() + 7d`. For a TTL feature whose purpose is to expire stale sessions, this defeats the goal for the entire pre-existing user base on first deploy.

Suggested fix:
```ts
db.prepare("UPDATE users SET expires_at = updated_at + ? WHERE bot = 0 AND expires_at IS NULL")
  .run(SESSION_TTL);
```
Then any user whose `updated_at` is already older than `now - SESSION_TTL` will be expired immediately on next request — which is exactly the desired behavior. Update the PR description to match either way.

**N2. Duplicated SESSION_TTL_MS parsing with inconsistent failure modes.**
- `repos/users.ts` (canonical): **throws** on invalid value.
- `v6-session-ttl.ts` (duplicate): **silently falls back** to 7d default.

If `SESSION_TTL_MS=abc` is set, the server will crash on import of `repos/users.ts` — fine, fail-fast — but the duplicate logic in v6 means the contracts diverge. Cleaner: import `SESSION_TTL_MS` from `repos/users.ts` in the migration, or extract to a `config.ts`. (Minor — won't bite in practice because users.ts loads first.)

### 🟢 Low

**N3. Gateway/WebSocket session not invalidated on lazy expiry.**
`findByToken()` clears the DB token when expired, but an already-open WS connection keyed off that user has no signal. Dispatcher continues to deliver events to a session that just expired. Probably out of scope for this PR (issue #118 is HTTP-focused), but worth a follow-up issue: cleanup should also kick connected clients.

**N4. No test covers the cookie-reissue behavior.**
The R4 escalation #4 fix is critical (without it, browser cookies expire while server sessions live), but `session-ttl.test.ts` doesn't assert that `Set-Cookie` appears on a refreshed request. One-line check using `res.headers.get('set-cookie')` after a request near the threshold would lock in the regression guard.

**N5. No test for OAuth atomic UPDATE / token rotation on re-login.**
The R4 escalation #5 fix is also untested. Easy to add: insert a user with old token+expires_at, re-run callback, assert token changed and expires_at moved together.

**N6. `refreshTTL` writes `updated_at = Date.now()` separately from the expires_at value.**
```ts
.run(Date.now() + SESSION_TTL_MS, Date.now(), id);
```
Two `Date.now()` calls — they will differ by microseconds, harmless, but stylistically `const now = Date.now();` once is cleaner and makes invariants like `expires_at - updated_at == SESSION_TTL_MS` exact.

**N7. `requireAuth` doesn't propagate `expires_at` to consumers.**
`AuthUser` now has `expires_at`, but `c.set("botUser", result.user)` puts the whole thing in context. Good — but no other route currently reads it. Not a bug, just noting that downstream code can now signal "session about to expire" to clients without a /me round-trip.

---

## Verdict

**Approve.** R4 ratchet is clean across all 7 items. The v6 backfill grace policy (N1) is the only thing I'd want addressed before merge if you care about expiring dormant pre-existing users at deploy time — but it's a policy choice, not a correctness bug, so an "OK to merge + open follow-up issue" is also defensible.

Recommended follow-ups (issues, not blockers):
- N1: align backfill with PR description (`updated_at + TTL`)
- N3: WS invalidation on session expiry
- N4/N5: regression tests for cookie reissue + OAuth atomic update
- N2: dedupe SESSION_TTL_MS config
