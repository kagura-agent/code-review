# 🌠 Nova — R2 Re-Review · cove#269

**PR:** kagura-agent/cove#269 — "fix: PR #264 follow-ups — config centralisation, WS expiry, tests, changelog"
**Round:** 2 (re-review)
**Verdict:** ⚠️ Approve-with-changes. Most R1 must-fix items are addressed, but **Must-Fix #3 (short-TTL test)** is only partially resolved and one R1 should-address has been silently dropped.

---

## R1 Follow-Up Audit

### 🔴 Must-Fix

#### R1-MF1 — re-IDENTIFY leaks intervals → ✅ **Fixed**
`ws/index.ts:88-91`:
```ts
if (session.isIdentified) {
  session.close(4005, "Already identified");
  return;
}
```
Early-return runs before the `setInterval` block, so a duplicate IDENTIFY can no longer spawn a second `expiryCheck` or double-register on the dispatcher. `ws.on("close")` clears the single interval. Good.

*Minor:* the guard uses `session.isIdentified`, but earlier this PR used `session.identified` in the fix comment. Verified against `session.ts:19` — `isIdentified` is the real getter. ✅

#### R1-MF2 — cookie fallback tracks wrong token → ✅ **Fixed**
`ws/index.ts:104-110`:
```ts
if (!user && preAuthUser) {
  user = preAuthUser;
  const cookies = parseCookies(request.headers.cookie);
  identifyToken = cookies[SESSION_COOKIE] || undefined;
}
```
When the explicit token is bogus and we fall back to cookie auth, `identifyToken` is rewritten to the cookie value, so the subsequent `expiryCheck` polls the right row and won't kill a healthy cookie session after 60 s. ✅

**One residual nit (carry to backlog, not a blocker):** if `cookies[SESSION_COOKIE]` is somehow absent at IDENTIFY time even though `preAuthUser` was set at upgrade (e.g. proxy stripping cookies on the upgraded socket's later frames — unusual but possible), `sessionToken` ends up `null` and `expiryCheck` becomes a silent no-op for that connection. Not a security issue (the user is still authenticated and dispatcher will detect disconnect), but worth a log line.

#### R1-MF3 — Test 2 doesn't test the short-TTL branch → ⚠️ **Partially addressed (ESCALATED tag dropped to ⚠️ only because formula logic is now asserted)**
The new "sliding threshold works for short TTLs (< 24h)" test (`session-ttl.test.ts:103-135`):

```ts
const shortTTL = 3_600_000;
const shortThreshold = Math.max(shortTTL / 2, shortTTL - 86_400_000);
expect(shortThreshold).toBe(shortTTL / 2);
```

This **re-implements the formula in the test and asserts the re-implementation against itself.** It does not call any production code with `SESSION_TTL_MS=3_600_000`. The "integration" half of the test then falls through to the default 7-day TTL, which is the long-TTL branch — same as R1.

**Root cause:** `config.ts` snapshots `process.env["SESSION_TTL_MS"]` once at module load, so a Vitest test can't legitimately swap TTLs without `vi.resetModules()` + `vi.stubEnv()`. The PR didn't introduce that machinery.

**Recommendation (must-fix-soon, not a merge blocker):**
- Either inject `SESSION_TTL_MS` into `resolveUser` (DI), or
- Use `vi.resetModules()` + `vi.stubEnv("SESSION_TTL_MS", "3600000")` + dynamic `await import("../auth.js")` so the short branch is actually executed.

The current test passes for the wrong reason — change `Math.max` to `Math.min` in `auth.ts` and the assertions still hold (they assert the formula, not the call site). That's the textbook tautology smell R1 flagged.

#### R1-MF4 — Test 3 was tautological → ✅ **Fixed**
The new `/api/auth/callback` test (`session-ttl.test.ts:138-211`) mocks `globalThis.fetch` for both `oauth2.googleapis.com/token` and `googleapis.com/oauth2/v2/userinfo`, then drives the **real route handler** via `app.request(...)`. It asserts:
- 302 → `/`
- token is rotated (`!= "old-token"`)
- `expires_at` is set atomically with the new token within `±5 s` of `now + SESSION_TTL_MS`

This now exercises the actual OAuth callback path. ✅

*Nit:* `expect(row.expires_at).toBeLessThanOrEqual(Date.now() + SESSION_TTL_MS + 1000)` — the `+1000` slack is fine, but consider asserting `row.expires_at - row.updated_at ≈ SESSION_TTL_MS` to lock the atomicity invariant directly.

---

### 🟡 Should-Address

#### R1-SA1 — 60 s per-connection polling scalability → ❌ **Unaddressed → ESCALATED to 🟡 High Should-Fix**
`ws/index.ts:125-138` still installs one `setInterval` per non-bot connection that runs `users.findByToken(...)` every 60 s. At N concurrent browsers that's N DB queries per minute purely for expiry detection, even though `expires_at` is known and monotonic at IDENTIFY time.

Cheap fixes that don't require a redesign:
1. **Schedule a single `setTimeout(close, expires_at - Date.now())`** at IDENTIFY — zero polling, fires exactly once when the token would expire, and re-arm only on token rotation (out-of-band signal).
2. Or keep polling but **share a single global interval** that walks `dispatcher.sessions` and revalidates only those whose cached `expires_at` is in the past.

Either pattern eliminates the O(N) polling. Worth opening a follow-up issue before this hits prod with real browser users.

#### R1-SA2 — `repos/users.ts` re-export needs `@deprecated` → ❌ **Unaddressed → ESCALATED to 🟡 Should-Fix**
`repos/users.ts:6`:
```ts
export { SESSION_TTL_MS };
```
No JSDoc, no `@deprecated`, no inline comment. New code reviewers will reasonably import from either path. The whole point of the centralisation was a single source of truth — leave the re-export if you must for backwards-compat, but mark it:
```ts
/** @deprecated Import from `../config.js` instead. Kept for one release for backwards compat. */
export { SESSION_TTL_MS };
```
Better: delete the re-export entirely (only one external consumer remained, the test, which has been migrated in this same PR). Grep confirms nothing else references it via this path in-tree.

#### R1-SA3 — `preAuthUser` not revalidated at IDENTIFY time → ⚠️ **Partially addressed**
The new `expiryCheck` will catch a revoked token within 60 s, which substantially mitigates the original concern. **But** between upgrade and the first poll there's still a window where:
- cookie token was invalidated server-side (logout in another tab, admin revoke, expiry sweep)
- WebSocket has already received READY and is happily processing payloads as `preAuthUser`

For a fully tight fix, re-run `users.findByToken(cookieToken)` at the top of the IDENTIFY handler before constructing `user` from `preAuthUser`. One extra DB hit per connect, no closure tracking changes. Leaving as ⚠️ because the 60 s poll bounds the exposure; flag for follow-up.

---

## Fresh Review of New Code

### `config.ts` (new) — 🟢 LGTM
- Single parse, validates `Number.isFinite(parsedTTL) && parsedTTL > 0`, throws at module load.
- Process-level fail-fast is correct here: a bad TTL must never silently fall back to a default in a security-sensitive constant.

### `CHANGELOG.md` (new) — 🟢 LGTM
- "Breaking Changes" framing is honest about the `bot` default semantics flip.
- Consider adding an `[Unreleased] / Changed` block referencing this PR's other items (centralised config, WS expiry enforcement, session-TTL test coverage) so future readers can correlate.

### `db/migrations/v6-session-ttl.ts` — 🟢 LGTM
- Now imports `SESSION_TTL_MS` from `config.ts` instead of re-parsing env. Consistent.

### `routes/auth.ts`, `routes/register.ts` — 🟢 LGTM (import-only changes)

### `ws/index.ts` — see findings above

### `__tests__/session-ttl.test.ts` — see MF3/MF4 above
Additional fresh issues:
1. **Global `fetch` monkey-patch in OAuth test** — wrapped in try/finally to restore `originalFetch`, good. But if a parallel test in the same worker hits `globalThis.fetch` between the `globalThis.fetch = ...` assignment and the `app.request`, it'll see the mock. Vitest defaults to file-level parallelism so this is fine **in this file**; document the constraint or switch to `vi.spyOn(globalThis, "fetch")` for safer isolation.
2. **`TestDispatcher` with `{ getById: () => null }` cast to `any`** — fine for these tests since IDENTIFY-side flow isn't exercised, but the `as any` will rot. Consider a lightweight `MockUsersRepo` in `__tests__/helpers/`.

---

## Summary Table

| R1 Item | Severity | Status | Notes |
|---|---|---|---|
| MF1 re-IDENTIFY interval leak | 🔴 | ✅ Fixed | `isIdentified` guard + early close 4005 |
| MF2 cookie fallback wrong token | 🔴 | ✅ Fixed | `identifyToken` overwritten in fallback |
| MF3 short-TTL test missing | 🔴 | ⚠️ Tautological replacement | Re-asserts formula against itself; doesn't drive `resolveUser` with short TTL |
| MF4 OAuth test tautological | 🔴 | ✅ Fixed | Now drives real `/api/auth/callback` with mocked fetch |
| SA1 60 s polling scalability | 🟡 | ❌ → ESCALATED 🟡 high | Use `setTimeout(close, ttl)` or shared interval |
| SA2 `@deprecated` re-export | 🟡 | ❌ → ESCALATED 🟡 | Add JSDoc or delete the re-export |
| SA3 preAuthUser not revalidated | 🟡 | ⚠️ Partial | 60 s poll bounds exposure; consider re-validating at IDENTIFY |

---

## Merge Recommendation

**Approve with follow-up issues.** R1 critical bugs (interval leak, wrong-token tracking) are genuinely fixed and the OAuth test now exercises the real route — that was the core safety risk.

Before merge, please open issues (or fold into this PR) for:
1. **MF3 (must)** — make the short-TTL branch actually execute in tests (`vi.stubEnv` + `vi.resetModules` pattern). The current test is reassuring-looking but evidence-free.
2. **SA1 (high)** — replace per-connection `setInterval` with a `setTimeout` keyed on `expires_at`.
3. **SA2 (low)** — kill the `repos/users.ts` re-export or annotate `@deprecated`.

— 🌠 Nova
