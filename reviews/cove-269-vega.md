# Code Review - PR #269 (Round 3)

Reviewer: 💫 Vega

## 1. R2 Issues Verification

| Issue | Status | Notes |
|-------|--------|-------|
| **1. Short TTL test still tautological** (🟡) | ✅ Fixed | `getRefreshThreshold` was extracted into a pure function and is properly tested with hardcoded assertions (e.g. `1h -> 30m`). Integration test also directly controls DB setup without circular dependencies. Excellent. |
| **2. 60s per-connection polling** (🟡) | ✅ Fixed | Removed the per-connection `setInterval` polling and replaced it with a `setTimeout(..., ttl)` bound to the session expiry. *(Note: See critical regressions introduced by this change below).* |
| **3. `@deprecated` on `repos/users.ts`** (🟢) | ✅ Fixed | Added proper JSDoc `@deprecated` tag. |
| **4. preAuthUser not revalidated at IDENTIFY** (🟢) | ✅ Fixed | The session expiry is now scheduled via `setTimeout(..., expires_at - Date.now())` using the timestamp fetched at UPGRADE. This perfectly bounds the connection without leaking out-of-bounds uptime. |

## 2. New Findings & Regressions

While replacing the 60s polling interval fixed the performance concern, the specific `setTimeout` implementation introduced two major session management bugs:

### 🔴 Regression: Session Revocation (Logout) No Longer Drops WebSockets
By removing the 60s polling interval, you removed the server's ability to detect early session revocations. 
- **Scenario:** A user logs in, receives a 7-day TTL, and connects via WebSocket. The user then manually logs out (or their token is deleted/regenerated from the DB by OAuth re-login). 
- **Bug:** Their existing WebSocket connection will now stay alive for up to 7 days because the DB check only happens when the timer fires at the end of the TTL.
- **Fix:** You must explicitly close the WebSocket when a session is invalidated. Since the `GatewayDispatcher` tracks sessions, when a user logs out, the server should find the `GatewaySession` associated with that user/token and forcefully `close()` it. Alternatively, implement a shared background ticker that sweeps active WS sessions and checks them against the DB periodically (batching the queries).

### 🔴 Bug: Timer Not Rescheduled After Refresh
When the `setTimeout` fires, you query the DB to check if the session is still valid (`const valid = users.findByToken(sessionToken);`). If the user recently made an HTTP request and triggered a sliding refresh, `valid` will be true.
- **Bug:** If the session was refreshed, the `if (!valid)` block correctly skips the close, but the callback finishes without setting a **new** timer. The WebSocket is now entirely unmonitored and will remain connected indefinitely, even after the new `expires_at` timestamp passes.
- **Fix:** If `valid` is true, you must calculate the new TTL (`valid.expires_at - Date.now()`) and schedule a new `setTimeout` to continue monitoring the connection.

## 3. Verdict
**Status:** ❌ Changes Requested (Escalated to 🔴 due to regressions)

All R2 feedback was cleanly addressed, but the structural change to WebSocket session timers introduced regressions where revoked tokens aren't disconnected and refreshed tokens are left unmonitored indefinitely. Please fix the timer rescheduling and revocation logic.