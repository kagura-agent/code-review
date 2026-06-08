# PR #264 Review — Round 6 (Nova 🌠)

Branch: `feat/session-ttl-118` @ `a671a62`
Scope: Session TTL with lazy + periodic cleanup (closes #118).

---

## R5 Issue Follow-up

### 🟡 → ✅ Fixed: `resolveUser` returned stale `expires_at` after sliding refresh
Commit `a671a62` adds `user.expires_at = Date.now() + SESSION_TTL_MS;` immediately after `users.refreshTTL(user.id)` in `auth.ts:71`. The returned `AuthUser` now carries the new expiry, so `/api/auth/me` and `requireAuth` consumers see the post-refresh value. Verified by `__tests__/session-ttl.test.ts` which exercises the `/me` payload and the standalone `refreshTTL` path — though there is still no test that asserts the sliding-refresh path *via* `resolveUser` returns the **bumped** `expires_at` (i.e., no regression test for the exact bug R5 caught). Recommend adding one in a follow-up, but the fix itself is correct.

### 🟡 WebSocket sessions outlive expired tokens
Still unaddressed in this PR (was explicitly out-of-scope per R5). `packages/server/src/ws/index.ts:41,94` call `users.findByToken(sessionToken)` only at upgrade/identify — once authenticated, expired tokens keep streaming. Re-confirming the follow-up issue; not blocking #264, but worth filing now while the context is fresh.

### 🟢 Carry-overs from R5 (still open, all non-blocking)
- **v6 backfill grants `Date.now() + SESSION_TTL` to every dormant non-bot user.** Old, idle accounts effectively get a fresh 7-day window the moment the migration runs. Policy choice — flagged for visibility, not changed.
- **Duplicated `SESSION_TTL_MS` parsing.** `repos/users.ts` and `db/migrations/v6-session-ttl.ts` independently parse `process.env["SESSION_TTL_MS"]` with subtly different validation (the repo throws on invalid; the migration silently falls back to `604800000`). Should be hoisted into a single `config.ts` so the two cannot diverge. Not addressed.
- **No tests for OAuth atomic `token+expires_at` update** (`routes/auth.ts:80–86`) and **no tests for cookie reissue on sliding refresh** in `requireAuth` (`auth.ts:88–90`). Both code paths are now load-bearing for session safety; adding `expect(res.headers.get('set-cookie')).toMatch(/cove-session=/)` and a callback-flow expiry assertion would close the loop.

---

## Fresh Review of New Code

### 🟡 `findByToken` may clear someone else's token on race — minor
`repos/users.ts:103`:
```ts
this.db.prepare("UPDATE users SET token = NULL, expires_at = NULL WHERE token = ?").run(token);
```
Race window: if `regenerateToken` rotates the token between the SELECT and this UPDATE *and* (cryptographically improbable) the new token equals the queried `token`, we'd nuke the rotated session. UUID v4 collision is negligible, so this is theoretical. Still cleaner to `WHERE token = ? AND expires_at IS NOT NULL AND expires_at < ?` — would also prevent clearing if the row was just refreshed by a concurrent request. Worth a one-line tweak.

### 🟡 Sliding-refresh threshold has surprising semantics for short TTLs
`auth.ts:67`:
```ts
const refreshThreshold = Math.max(SESSION_TTL_MS / 2, SESSION_TTL_MS - 86_400_000);
```
For the default 7d TTL this evaluates to `max(3.5d, 6d) = 6d`, i.e., refresh once a day has elapsed — sensible. But for any operator who sets `SESSION_TTL_MS` below ~2 days (e.g., testing, kiosk deployments), `SESSION_TTL_MS - 86_400_000` goes negative and `SESSION_TTL_MS / 2` wins, meaning refresh fires on every single request once half-life is crossed. Likely fine in practice, but the comment "extend TTL if more than 1 day has passed" no longer holds for short TTLs. Either document the asymmetric behaviour or clamp the constant explicitly: `Math.min(SESSION_TTL_MS / 2, 86_400_000)` would express "refresh once per ~day, or at half-life, whichever is sooner" more honestly.

### 🟡 Behavioural change in `POST /api/users` (verify intent)
`repos/users.ts:48`: `const isBot = opts.bot === true;`
Previously (`opts.bot !== false`) the default for an omitted `bot` field was `true`. Now the default is `false`, meaning agents posted *without* an explicit `bot: true` become **human** users with a 7-day TTL — and after seven days, the bot stops working with `401`. The PR's own test diff (`api.test.ts:85, 662`) had to add `bot: true` to every existing call site, which is the canary for downstream impact. Anyone using the public API in scripts/automation will get the same surprise. At minimum:
1. Call this out in CHANGELOG / release notes as a breaking default flip.
2. Consider documenting in the route handler (`routes/agents.ts:31`) that bot-style integrations must pass `bot: true`.
Not strictly a bug (tests pass), but a behaviour change of this kind deserves explicit acknowledgement and probably an issue tracking documentation updates.

### 🟢 Periodic cleanup wiring
`index.ts:26–35` — interval is `unref()`'d (good, won't block shutdown), errors are caught, only logs on `removed > 0`. The `cleanupExpired` UPDATE is index-supported by the partial index added in the migration (`idx_users_expires_at`). Looks right. One nit: the interval is allocated even for `:memory:`/test DBs that spin up `createApp` separately — fine because `index.ts` is the production entrypoint, but worth a quick comment that test harnesses bypass this code path (which they do, via `createApp`).

### 🟢 Migration `v6-session-ttl.ts`
- `addColumnIfMissing` + `DEFAULT NULL` is idempotent and re-running the migration is safe.
- `CREATE INDEX IF NOT EXISTS ... WHERE expires_at IS NOT NULL` correctly excludes bots from the index — a partial index is the right call here.
- The `hasColumn(db, "users", "updated_at")` guard is defensive but slightly odd: at v5→v6 we know the column exists. Harmless.
- Silent fallback on bad `SESSION_TTL_MS` differs from the repo's `throw`. See duplicated-parsing follow-up above.

### 🟢 Schema seed (`schema.ts:148–164`)
`seedUsers` now writes `expires_at = null` for both bots and seed humans (the in-memory dev seeds don't get TTLs). Comment explains the intent. Reasonable.

### 🟢 Test coverage
`__tests__/session-ttl.test.ts` cleanly covers:
- Expired token → 401 + token cleared (lazy cleanup).
- Bot token never expires.
- `cleanupExpired` is selective and returns the right count.
- `create()` sets `expires_at` correctly per bot flag.
- `refreshTTL` extends expiry and is no-op for bots (implicit via `WHERE bot = 0`).
- `/api/auth/me` returns `expires_at`.

Gaps (already enumerated above): sliding-refresh-via-`resolveUser` regression test for R5 bug; OAuth callback atomic update; cookie reissue header; refresh-threshold edge cases.

---

## Verdict

**Approve with non-blocking comments.**

The R5 blocker is correctly fixed and the new test suite covers the core TTL semantics. Remaining items are either (a) explicitly deferred follow-ups (WebSocket recheck), (b) test-coverage gaps that aren't safety-critical for merge, or (c) ergonomic/policy nits (duplicated env parsing, threshold comment, breaking default flip on `bot`). The breaking default for `POST /api/users` is the only item I'd want to see at least *documented* before this lands — but tests reflect the new contract, so it's not a correctness defect.

Recommended follow-up issues to file alongside merge:
1. WebSocket session re-authentication on token expiry.
2. Centralise `SESSION_TTL_MS` env parsing (single source of truth).
3. Add regression test for sliding refresh returning bumped `expires_at` via `resolveUser`.
4. CHANGELOG entry for `POST /api/users` `bot` default change.
