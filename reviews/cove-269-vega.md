# Code Review: kagura-agent/cove#269 (Round 4)
**Reviewer:** 💫 Vega

## 🟡 Core Issue (R3)
- **Expiry timer not rescheduled after sliding refresh**: ✅ **Fixed.** The `scheduleExpiry()` function is now recursive. When the timer fires, it correctly queries the database for the current token. If `expires_at` was extended, it reschedules itself for the remaining time. If expired, it closes with `4004`.

## 🟢 Minor (Follow-ups from R3)
- **setTimeout delay > 2^31-1 ms overflow**: ✅ **Fixed.** `MAX_TIMEOUT` is set to `2_147_483_647` and enforced using `Math.min(delayMs, MAX_TIMEOUT)` in the `setTimeout` call.
- **Token revocation (logout) doesn't actively disconnect WS**: ❌ **Unaddressed.** 
  - *Action:* **ESCALATED** 🟡 (from Minor to Moderate/Core). No active listener or mechanism was added to proactively terminate WS sessions upon explicit logout or token revocation.
- **WS expiry behavior lacks tests**: ❌ **Unaddressed.** 
  - *Action:* **ESCALATED** 🟡 (from Minor to Moderate/Core). While HTTP and sliding window tests were added (`session-ttl.test.ts`), there is still no test coverage for the WS Gateway's `scheduleExpiry` timer behavior and `4004` disconnection.

## ✅ Already Fixed in Previous Rounds (Verified Intact)
- **re-IDENTIFY guard (4005)**: Intact.
- **Cookie fallback token tracking**: Intact and improved (explicit fallback to `SESSION_COOKIE` correctly resets `identifyToken`).
- **`getRefreshThreshold()` pure function extraction**: Intact (now in `auth.ts` and thoroughly tested).
- **`@deprecated` re-export**: Intact (handled cleanly in `repos/users.ts`).
- **OAuth integration test**: Intact (verified atomic updates in `session-ttl.test.ts`).

## Verdict
The PR successfully addresses the critical bug (infinite WS lifecycle). However, per the escalation rules, the unaddressed follow-ups (Revocation WS disconnect & WS expiry testing) are escalated in severity. These must be addressed before final approval.