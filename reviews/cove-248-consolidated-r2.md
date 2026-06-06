# Consolidated Review R2 — cove#248: OAuth token leak → BFF cookies

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 2 (re-review after author updates)

## Round 1 Issue Resolution

| # | Issue | Status | Notes |
|---|-------|--------|-------|
| C1 | `PUBLIC_PATHS` missing new endpoints | ✅ Fixed | Both `pending-status` and `logout` added; tests confirm public access |
| C2 | No tests for auth surface | ✅ Fixed (HTTP) | New `auth.test.ts` (228 lines) covers pending-status, logout, requireAuth cookie, /me with Bearer/Bot/cookie, register cookie flow. **WS auth still untested** — see below |
| C3 | `parseCookies` URIError DoS | ✅ Fixed | `try/catch` wrapping `decodeURIComponent` |
| C4 | `pendingToken` leaked to JS | ✅ Fixed | Returns `{ pending: true }` only, register reads from cookie, returns `{ message: "registered" }`. Test asserts `not.toHaveProperty("token")` |
| S1 | Legacy localStorage cleanup | ⚠️ Not addressed | See new issue below |
| S2 | Logout error handling | ✅ Fixed | `.catch(() => {}).finally(...)` |
| S3 | `/api/auth/me` Bot prefix | ✅ Fixed | Handles Bearer, Bot, and cookie. Still duplicates `resolveUser` logic inline (drift risk, not blocking) |
| S4 | WS close codes 4001/4004 | ✅ Fixed | Correctly distinguishes no-credentials vs invalid-token |
| S5 | Cookie `secure` from NODE_ENV | ⚠️ Partial | Code is correct, but see deployment concern below |
| S6 | CORS for cross-origin | ❌ Deferred | Same-origin is the supported topology; acceptable to defer |

**All 4 Critical items from R1 are resolved.** Great work on the test coverage and the strict BFF invariant.

## Remaining Issues

### 🟡 WebSocket auth path has no tests (Stella, Nova)

The WS gateway is the most complex auth surface in this PR — cookie pre-auth at HTTP upgrade, IDENTIFY accepting `token: null`, dual code paths for bot vs browser, fall-through logic. It has **zero tests**. Needed coverage:

- Browser: valid `cove-session` cookie → IDENTIFY `{ token: null }` → READY
- Bot: no cookie → IDENTIFY with valid token → READY  
- Negative: no cookie + no token → 4001
- Negative: invalid explicit token → 4004
- Negative: malformed cookie header → connection survives

**Recommendation:** Add a `ws.test.ts`, or if out of scope for this PR, file a tracking issue and ship.

### 🟡 Legacy localStorage tokens remain accessible to XSS (Vega)

Old clients stored `cove-token` in localStorage. The new code no longer reads it, but never cleans it up. **The token is still valid in the DB** — an XSS attack could still extract it via `localStorage.getItem("cove-token")`, defeating the BFF migration.

**Fix (2 lines in `App.tsx` mount):**
```typescript
localStorage.removeItem("cove-token");
localStorage.removeItem("cove-user");
```

### 🟡 Deployment may not set `NODE_ENV=production` (Stella)

`COOKIE_OPTIONS.secure` depends on `NODE_ENV === "production"`, but the staging deploy systemd unit doesn't set `NODE_ENV`. Cookies on the HTTPS deploy would lack `Secure`. Consider defaulting secure unless `NODE_ENV === "development"`, or adding `Environment=NODE_ENV=production` to deploy units.

### 🟢 Minor: Register still accepts `pendingToken` from body (Stella, Nova)

`register.ts` falls back to `body.pendingToken` for backward compat. The browser no longer sends it, so the main invariant holds. Consider scheduling removal to fully lock the BFF contract.

### 🟢 Minor: Token-fallthrough in WS is silent (Nova)

If a browser sends `{ token: "garbage" }` over a cookie-authenticated socket, the bad token is silently ignored and cookie identity is used. Behaviorally correct but surprising — worth a one-line comment.

## Verdict

**⚠️ Needs Changes (minor)** — 3/3 reviewers agree

The core BFF implementation is solid and all R1 critical issues are properly resolved. The remaining items are:
1. Add WS auth tests (or file tracking issue)
2. Add 2-line localStorage cleanup
3. Verify `NODE_ENV` in deployment

None are architectural — these are cleanup/hardening items that can be addressed quickly.
