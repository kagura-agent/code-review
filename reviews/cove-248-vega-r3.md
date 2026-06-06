# Review of PR #248 (Round 3)

## 1. Round 2 Issue Status

- **1. 🟡 WebSocket auth path has no tests**: ✅ **Fixed**. Excellent integration tests added in `ws-auth.test.ts` covering both cookie and token flows.
- **2. 🟡 Legacy localStorage tokens remain accessible to XSS**: ✅ **Fixed**. `localStorage.removeItem("cove-token")` added on app load.
- **3. 🟡 Deployment may not set `NODE_ENV=production`**: ✅ **Fixed**. Defaults to `secure: process.env.NODE_ENV !== "development"`.
- **4. 🟢 Register still accepts `pendingToken` from body**: ✅ **Fixed**. Fallback removed.
- **5. 🟢 Token-fallthrough in WS is silent**: ✅ **Fixed**. Clear comments added explaining the fallthrough behavior.
- **6. 🟢 `/api/auth/me` duplicates `resolveUser` logic**: ❌ **Not addressed** (Escalated to 🟡). `/api/auth/me` still manually parses headers and queries the DB instead of reusing the unified `resolveUser` helper or similar logic.
- **7. 🟢 Stray blank line in `api.ts`**: ❌ **Not addressed** (Escalated to 🟡). Blank line remains in the `logout()` function.
- **8. 🟢 No CORS for cross-origin deploys**: ❌ **Not addressed** (Escalated to 🟡). If Cove API and frontend run on different origins, `credentials: "include"` will fail without explicit CORS configuration.

## 2. New Issues Found

- **🟢 WS Auth looseness with valid cookie + invalid token**: If a user connects with a valid session cookie but provides an *invalid* token in the `IDENTIFY` payload, the server will silently discard the invalid explicit token and authenticate them using the cookie. This works but is slightly loose (explicitly invalid tokens might warrant a 4004).

## 3. Summary

Great job on the major security items from Round 2. The BFF pattern is solid, legacy tokens are cleanly mitigated, and the WebSocket integration tests are thorough and verify the exact behaviors we need. The remaining issues are primarily minor technical debt (code duplication in `/api/auth/me`), a formatting nitpick, and a missing CORS setup (which may not impact same-origin reverse-proxied deployments, but is a risk for cross-origin).

## 4. Verdict
⚠️ **Needs Changes** (Due to unaddressed issues escalating per policy, requiring explicit resolution or acknowledgment).
