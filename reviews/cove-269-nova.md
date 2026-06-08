# 🌠 Nova — Round 3 Re-Review: kagura-agent/cove#269

**Branch:** `fix/264-followups` → `main`
**Scope:** R2 follow-ups + fresh review of new code.

---

## R2 Issue Check

| # | R2 Issue | Status | Notes |
|---|---|---|---|
| R2-1 | 🟡 Short-TTL test tautological | ✅ **Fixed** | Extracted `getRefreshThreshold(ttlMs)` pure fn (`auth.ts:24`). New test asserts the fn directly with 5 TTL values **and** drives `resolveUser` end-to-end with a forged near-expiry row (`expires_at = now + threshold*0.5`) → asserts `refreshed === true` and bumped `expires_at`. Real coverage now. |
| R2-2 | 🟡 60s per-connection polling | ✅ **Fixed** | Replaced `setInterval(…, 60_000)` with one-shot `setTimeout(close, expires_at - now)` per session (`ws/index.ts:125`). Cleared in `ws.on("close")`. No DB query per minute. Big win. |
| R2-3 | 🟢 `@deprecated` on `repos/users.ts` re-export | ✅ **Fixed** | JSDoc present (`repos/users.ts:6`). |
| R2-4 | 🟢 preAuthUser not revalidated at IDENTIFY | ✅ **Fixed (indirectly)** | Cookie token now captured at IDENTIFY (`ws/index.ts:108`) and used as `sessionToken` for the deferred expiry check via `findByToken`. Since `findByToken` itself nulls the token when `expires_at < now`, expired cookie sessions get caught at expiry-fire. Note: at the **moment** of IDENTIFY there's still no explicit re-check, but `findByToken` is the entry that produced `preAuthUser` at upgrade — so a stale cookie wouldn't have reached IDENTIFY anyway. |

Plus the previously-confirmed R2 fixes still hold: 4005 close on re-IDENTIFY guard, cookie fallback token tracking, OAuth integration test against the real `/api/auth/callback` route (now even more solid — see new test mocking Google token + userinfo endpoints).

---

## ✅ Strong improvements this round

1. **`config.ts` centralization** — `SESSION_TTL_MS` parsed once, validated once, imported from one place. `repos/users.ts`, `auth.ts`, `routes/auth.ts`, `routes/register.ts`, and the v6 migration all import from `../config.js`. The migration no longer re-implements parsing. Old export kept as `@deprecated` for one-cycle migration. Clean.
2. **`getRefreshThreshold` extraction** — pure, testable, single source of truth. Comment correctly explains the >24h vs <24h regimes.
3. **OAuth callback test** — mocks `globalThis.fetch` for both `oauth2.googleapis.com/token` and `googleapis.com/oauth2/v2/userinfo`, calls the real route, asserts redirect AND the DB row (`token != old`, `expires_at` within ±5s of `now + TTL`). This is the right way to test it.
4. **CHANGELOG.md** — clear Breaking Changes section documenting the `bot` field default. Good for downstream consumers.

---

## 🆕 New Findings

### 🟡 M1 — Expiry timer is **not rescheduled after sliding refresh**
`ws/index.ts:124-141`

```js
expiryTimer = setTimeout(() => {
  if (sessionToken) {
    const valid = users.findByToken(sessionToken);
    if (!valid) {
      if (heartbeatCheck) clearInterval(heartbeatCheck);
      session.close(4004, "Authentication expired");
    }
  }
}, ttl);
```

The timer fires once at the original `expires_at`. If the user hit `/api/auth/me` in the meantime and triggered `refreshTTL` (sliding refresh extends `expires_at` by another full TTL), the callback finds `valid !== null`, **logs nothing, does nothing, and never schedules a new timer**. The WS connection then has no further server-side expiry enforcement until disconnect — it can live indefinitely past the refreshed expiry.

**Concrete scenario (default 7d TTL):**
- t=0: IDENTIFY, timer scheduled for t=7d.
- t=4d: user hits `/api/auth/me`, refresh extends to t=11d.
- t=7d: timer fires, `findByToken` returns valid → no close, no reschedule.
- t=11d→∞: session lives forever (until network drop or explicit `cleanupExpired` cron nulls the token, at which point the next REST call would 401 but the WS is untouched).

This partially defeats the purpose of expiry enforcement on the WS layer.

**Fix:** in the callback, if `valid` is truthy and `valid.expires_at` is in the future, reschedule:
```js
if (valid && valid.expires_at && valid.expires_at > Date.now()) {
  expiryTimer = setTimeout(arguments.callee, valid.expires_at - Date.now());
} else if (!valid) {
  session.close(4004, "Authentication expired");
}
```
Or extract a `scheduleExpiry(user)` helper and call it recursively / from a `refreshed` signal.

---

### 🟢 L1 — `setTimeout` delay overflow for very large TTLs
`ws/index.ts:127`

`setTimeout` clamps delays > 2^31-1 ms (~24.8 days) and fires immediately. Default `SESSION_TTL_MS` is 7 days so fine, but an operator setting `SESSION_TTL_MS=2592000000` (30 days) would cause every WS to immediately enter the expiry branch, re-query `findByToken` (valid), and silently no-op — masked by M1 above. Worth a clamp:
```js
const delay = Math.min(ttl, 2_147_483_647);
```
or document the supported TTL range in `config.ts`.

---

### 🟢 L2 — `sessionToken` typing
`ws/index.ts:57` declares `let sessionToken: string | null = null;` at the outer scope but is only assigned inside the IDENTIFY branch. If multiple identify attempts ever became possible (currently guarded by `session.isIdentified()`), the variable would stick to the last value. Currently safe due to the 4005 guard, but a small comment linking the two would future-proof it.

---

### 🟢 L3 — Test uses real `SESSION_TTL_MS` in the "short TTL" integration tail
`session-ttl.test.ts:236-243`

The integration portion of `"sliding threshold works for short TTLs"` is actually exercising the **production** `SESSION_TTL_MS`, not a short one — it just forges a row whose remaining time is below the production threshold. That's fine and verifies the wiring, but the test name is slightly misleading. The pure-function assertions above it do cover the actual short-TTL math. Rename to `"sliding threshold pure function + integration with forged near-expiry"` or split into two tests.

---

## Severity Summary

| Severity | Count | Items |
|---|---|---|
| 🔴 Critical | 0 | — |
| 🟠 High | 0 | — |
| 🟡 Medium | 1 | M1 (expiry timer not rescheduled after refresh) |
| 🟢 Low | 3 | L1 (setTimeout overflow), L2 (sessionToken comment), L3 (test name) |

All R2 issues are fixed. Recommend addressing **M1** before merge (the refresh-then-survive-forever path is a real correctness gap), L1–L3 can be follow-ups.

**Verdict:** ⚠️ Request changes — one Medium blocker (M1). Solid R3 overall; the polling→timer migration and config centralization are clean wins.
