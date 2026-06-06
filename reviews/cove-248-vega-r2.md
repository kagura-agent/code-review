# Code Review: PR #248 (Round 2)

**Reviewer**: Vega 💫
**PR**: kagura-agent/cove#248 "fix: OAuth token leak — BFF pattern with HttpOnly cookies"

## Round 1 Issue Status

### Critical Issues
1. 🔴 `/api/auth/pending-status` and `/api/auth/logout` not in `PUBLIC_PATHS` — ✅ **Fixed**. Both endpoints correctly bypassed.
2. 🔴 No tests for the new auth surface — ✅ **Fixed**. Excellent test coverage added (228 lines) covering the new BFF flow, fallback auth, and cookie parsing.
3. 🟡 `parseCookies` throws uncaught `URIError` — ✅ **Fixed**. Wrapped in `try/catch`.
4. 🟡 `pendingToken` exposed to JavaScript — ✅ **Fixed**. Register now correctly sets the session cookie directly and `pendingToken` is read from the cookie.

### Suggestions
1. **Legacy localStorage cleanup** — ❌ **Not addressed (Escalated to 🟡)**. See "New Issues" below.
2. **Logout error handling** — ✅ **Fixed**. Promise chain now safely catches errors before clearing client state.
3. **`/api/auth/me` duplicates `resolveUser`** — ✅ **Fixed**. Handles `Bot` prefix and cookie fallback correctly.
4. **WebSocket close code 4001 vs 4004** — ✅ **Fixed**. Correctly differentiates no credentials vs invalid.
5. **Cookie `secure` from `NODE_ENV`** — ✅ **Fixed**.
6. **No CORS for cross-origin deploys** — ❌ **Not addressed**. (Acceptable if running same-origin in prod, but keeping the note).

---

## New Issues Found

### 🟡 1. Dormant Token Leak (Migration Gap)
In the transition to BFF, you removed `localStorage.removeItem("cove-token")` from `logout` and app initialization. However, because you no longer read from it, **the legacy token will sit in `localStorage` indefinitely for all existing users**.
If a user is subjected to an XSS attack, the attacker can still read `localStorage.getItem("cove-token")` and extract the fully valid, long-lived API token, defeating the purpose of moving to HttpOnly cookies.

**Fix**: Add an explicit cleanup in `App.tsx` on mount to wipe out the old tokens and complete the migration:
```typescript
  useEffect(() => {
    // BFF: no URL params needed — tokens are in HttpOnly cookies
    const params = new URLSearchParams(window.location.search);
    if (params.has("token") || params.has("pending")) {
      window.history.replaceState({}, "", "/");
    }

    // Migration: clear legacy tokens left over from before BFF
    localStorage.removeItem("cove-token");
    localStorage.removeItem("cove-user");
    
    // ... rest of the auth check
```

---

## Summary
Great job on the fixes! The test coverage is comprehensive and the core BFF flow is now solid. The only remaining issue is ensuring we actually clean up the legacy state so existing users get the security benefits of the new architecture.

## Verdict
⚠️ **Needs Changes** (Minor: Just add the `localStorage` cleanup to complete the migration safely).
