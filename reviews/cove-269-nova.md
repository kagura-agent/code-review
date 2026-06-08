# 🌠 Nova — R4 Re-Review: cove#269 "fix: PR #264 follow-ups"

**PR**: kagura-agent/cove#269
**Round**: 4 (re-review of R3)
**Commits since R3**: `9d60d8e` — "fix(ws): reschedule expiry timer after sliding token refresh"
**Verdict**: ✅ **APPROVE** (with two carry-forward minors)

---

## R3 Issues — Status

### 🟡 Core: Expiry timer not rescheduled after sliding refresh → ✅ FIXED

R3 demanded a recursive `scheduleExpiry()` that re-reads `expires_at` and re-arms the timer. The commit `9d60d8e` implements exactly that in `packages/server/src/ws/index.ts`:

```ts
function scheduleExpiry(token: string, delayMs: number) {
  if (expiryTimer) clearTimeout(expiryTimer);
  expiryTimer = setTimeout(() => {
    const row = users.findByToken(token);
    if (!row || !row.expires_at) {
      if (heartbeatCheck) clearInterval(heartbeatCheck);
      session.close(4004, "Authentication expired");
      return;
    }
    const remaining = row.expires_at - Date.now();
    if (remaining <= 0) {
      if (heartbeatCheck) clearInterval(heartbeatCheck);
      session.close(4004, "Authentication expired");
    } else {
      scheduleExpiry(token, remaining);
    }
  }, Math.min(delayMs, MAX_TIMEOUT));
}
```

Behavior verification (fresh eyes):

1. **Sliding refresh case** — REST call calls `users.refreshTTL` → `expires_at` bumps to `now + SESSION_TTL_MS`. Timer fires at original `expires_at`, reads fresh row, `remaining > 0`, reschedules at the new remaining. ✅ Matches R3 requirement.
2. **Logout / token rotation** — `findByToken(token)` returns `null` → WS closes with 4004. This actually *implicitly* mitigates R3 minor #2 ("logout doesn't disconnect WS") for the case where logout rotates the token: the next timer fire (which may be far away) will kill the socket. Not eager, but bounded.
3. **Truly expired** — `remaining <= 0` → close 4004. ✅
4. **clearTimeout on `ws.close`** — added in the same commit. No timer leak on disconnect. ✅
5. **clearTimeout in `scheduleExpiry` itself** — guards against double-scheduling, defensive. ✅

### 🟢 R3 Minor: setTimeout overflow (>2^31-1 ms) → ✅ FIXED

`MAX_TIMEOUT = 2_147_483_647` constant declared, and `Math.min(delayMs, MAX_TIMEOUT)` applied in `scheduleExpiry`. Because the function is recursive, an initial cap-clamp followed by a fresh re-arm will correctly walk down very long TTLs in ≤25-day chunks. ✅

### 🟢 R3 Minor: Token revocation (logout) doesn't actively disconnect WS → ❌ UNADDRESSED → **escalated to 🟡**

No active "kick" path on logout. The new recursive timer eventually catches rotated tokens (see analysis above), but:

- For a fresh session with `expires_at = now + 7d`, a user who logs out at minute 1 will keep the WS open until the timer next fires — i.e. up to ~7 days later (or in 24.8-day chunks for longer TTLs).
- Per R3 escalation rule, unaddressed → severity bumps from green to yellow.

Suggested follow-up (separate PR is fine, not a blocker for this one):
- Add a `dispatcher.disconnectByToken(token)` and call it from the logout route.
- Or have the logout route delete/rotate the token *and* trigger an explicit close via a userId → session map.

### 🟢 R3 Minor: WS expiry behavior lacks tests → ❌ UNADDRESSED → **escalated to 🟡**

The added tests in `session-ttl.test.ts` cover:
- `resolveUser` sliding refresh extending `expires_at` (REST path)
- `getRefreshThreshold` pure-function values
- OAuth `/api/auth/callback` integration

…but **zero coverage of the new `scheduleExpiry` recursive logic** in `ws/index.ts`. The exact thing R3 flagged as the core bug now lives entirely untested. Recommend adding (next PR is acceptable):

1. **Reschedule-after-refresh test** — connect WS, IDENTIFY, advance fake timers past initial expiry, mutate row's `expires_at` to simulate sliding refresh, assert WS stays open and a new timer is scheduled.
2. **Revoked-token test** — null out token in DB, fast-forward timer, assert WS closes with 4004.
3. **Overflow clamp test** — schedule with `delayMs = 5 * MAX_TIMEOUT`, assert the timer fires after ≤MAX_TIMEOUT and re-arms.

Per the escalation rule, severity bumps from green to yellow.

---

## Previously Fixed — Still Intact

| Item | Status |
|------|--------|
| re-IDENTIFY guard (4005) | ✅ Intact (session.isIdentified check elsewhere) |
| Cookie fallback token tracking | ✅ Intact — `identifyToken` now sourced from cookie when falling back |
| `getRefreshThreshold()` pure function | ✅ Extracted in `auth.ts`, used by both `resolveUser` and tests |
| `@deprecated` re-export of `SESSION_TTL_MS` from `repos/users.ts` | ✅ Present with JSDoc |
| OAuth integration test | ✅ Now hits real `/api/auth/callback` with mocked fetch — no longer tautological |

---

## Fresh Review of New/Changed Code

### `packages/server/src/ws/index.ts`

**Strengths**
- Clean separation: `expiryTimer` and `sessionToken` declared once at handler scope; cleared on close. No leak vectors.
- Type extension (`expires_at: number | null`) propagated consistently through both `preAuthUser` and the IDENTIFY-path `user` object.
- Cookie-fallback token-rewrite is correct — prevents an attacker-supplied invalid explicit token from poisoning the expiry check.

**Minor observations** (non-blocking, optional cleanup):

1. **Dead variable** — `sessionToken: string | null = null` is declared at handler scope but only ever assigned inside IDENTIFY, then passed by closure capture into `scheduleExpiry(sessionToken!, ttl)`. After that, it's never re-read. You could drop the outer variable and just pass `identifyToken!` directly:
   ```ts
   if (!user.bot && user.expires_at && identifyToken) {
     scheduleExpiry(identifyToken, user.expires_at - Date.now());
   }
   ```
   Saves a non-null assertion and an unused outer-scope mutable. Cosmetic.

2. **`!user.expires_at` is truthy for `0`** — currently `if (!user.bot && user.expires_at)` skips scheduling when `expires_at === 0`. In practice `expires_at = 0` would mean "epoch", i.e. already expired; the immediate-close branch would handle it. Theoretically you might prefer `user.expires_at !== null` to be explicit, but no real-world value of 0 is plausible. Cosmetic.

3. **`MAX_TIMEOUT` magic-ish constant** — fine inline, but if `auth.ts` or `config.ts` grows similar concerns, consider centralising. Not for this PR.

4. **Recursion vs `while` loop** — recursive `scheduleExpiry → setTimeout → scheduleExpiry` is fine because each call returns synchronously after scheduling; no stack growth. Just noting the recursion is *control-flow recursion across event-loop ticks*, not call-stack recursion. ✅

### `packages/server/src/auth.ts`

- `getRefreshThreshold(ttlMs)` placement is correct — exported above the `SESSION_TTL_MS` import is awkward stylistically (function uses a magic `86_400_000` rather than the imported constant), but the function is pure and parameterised, so this is fine. ✅
- No regressions.

### `packages/server/src/config.ts`

- Single source of truth for `SESSION_TTL_MS`. ✅
- Throws on invalid env at import time — fail-fast on misconfigured deploys is the right call. ✅

### `packages/server/src/__tests__/session-ttl.test.ts`

- `getRefreshThreshold` numeric assertions look correct against the implementation (`Math.max(ttl/2, ttl - 86_400_000)`):
  - `3_600_000` → max(1.8M, -82.8M) = 1.8M ✓
  - `172_800_000` → max(86.4M, 86.4M) = 86.4M ✓
  - `604_800_000` → max(302.4M, 518.4M) = 518.4M ✓
- OAuth test correctly stubs both token-exchange and userinfo endpoints, and restores `globalThis.fetch` in `finally`. ✅
- **Gap**: no `ws/index.ts` test coverage as noted above.

### `CHANGELOG.md`

- New file, clearly documents the breaking `bot` field default. ✅ Good practice; previously missing.

---

## Summary

| Severity | Count | Notes |
|----------|-------|-------|
| 🔴 Blocker | 0 | — |
| 🟠 Major | 0 | — |
| 🟡 Minor | 2 | Both **escalated from green** per R3-rule: logout-disconnect, WS-expiry tests. Both safe to defer to follow-up PRs. |
| 🟢 Nit | 3 | Dead `sessionToken` var, `expires_at` truthiness check, magic `86_400_000`. All optional. |

**Recommendation**: **APPROVE & MERGE.** The R3 core bug is correctly fixed; the recursive scheduler is sound; the overflow clamp is in place; previously-fixed items remain intact. The two escalated minors are real but small and well-suited to a follow-up issue (suggest opening one before merge so they don't get lost).

— 🌠 Nova
