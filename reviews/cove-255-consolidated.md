# Consolidated Review R3 — cove#255: plugin mega-refactor

**Reviewers:** 🌟 Stella (GPT-5.5) · 🌠 Nova (Claude Opus 4.7) · 💫 Vega (Gemini 3.1 Pro)
**Round:** 3

## R2 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| 🔴 R2 | `res.json()` on 204 No Content → retry storm | ✅ Fixed — `if (res.status === 204) return undefined as unknown as T;` |
| 🟡 R2 | `invalidSessionTimer` not cleared in `cleanup()` | ✅ Fixed — now cleared in both `cleanup()` and `destroy()` |
| 🟡 R2 | POST retries can duplicate messages | ❌ Unaddressed → **escalated to 🔴** |
| 🟡 R2 | `sendTyping` inherits full ~50s retry budget | ❌ Unaddressed → **escalated to 🟠** |

## Critical Issues (must fix)

### 🔴 M1: POST `sendMessage` retries on 5xx → duplicate user messages (3/3 reviewers, escalated from R2)

`request()` retries network errors and 5xx uniformly regardless of HTTP method. When `sendMessage` (POST) gets a 5xx or network timeout **after the server already committed the message**, the retry creates a duplicate. Users see the same bot reply 2-4 times.

This is the third round this has been flagged. Per escalation protocol: 🟡 → 🔴.

**Fix:** Restrict 5xx/network retries to idempotent methods (`GET`, `DELETE`). POST should not retry on ambiguous failures unless an idempotency key is supported. 429 retry on POST is still safe (server explicitly says "not processed").

```ts
const isIdempotent = method === "GET" || method === "DELETE" || method === "HEAD";
if (res.status >= 500 && !isIdempotent) throw new Error(...);
```

### 🟠 M2: `sendTyping` inherits full ~50s retry budget (3/3 reviewers, escalated from R2)

Typing is cosmetic best-effort UX, but it shares the same 30s timeout + 3 retries path as real API calls. Under gateway brownout, typing requests pile up (5s keepalive interval vs 50s+ worst-case per call).

**Fix:** Zero retries + 3s timeout for typing:
```ts
async sendTyping(channelId: string): Promise<void> {
  return this.requestVoid("POST", `...typing`, undefined, AbortSignal.timeout(3000));
}
```

## Everything Else — Confirmed Good ✅

All R1 issues remain resolved:
- ✅ RESUMED vs reconnect event split — correct, no dispatch abort on soft resume
- ✅ REST 5xx + network retry + exponential backoff — working (just needs method-awareness)
- ✅ Retry-After NaN/unbounded — clamped at 30s with fallback
- ✅ INVALID_SESSION socket guard — `currentWs` ref captured + readyState checked
- ✅ RECONNECT documented — clear inline comment about seq/sessionId preservation
- ✅ HEARTBEAT now carries `seq` — latent bug fix
- ✅ `dispatch.ts` extraction — behavior-preserving, clean refactor
- ✅ `send()` made private — correct API lockdown
- ✅ 204 No Content — fixed correctly

## Suggestions (non-blocking)

1. Add unit tests for: 204 returns undefined, POST doesn't retry on 5xx (once M1 fixed), typing uses short timeout
2. `VOICE_STATE_UPDATE = 4` comment says "locked out" but adding to enum enables it — clarify intent (Nova)
3. Channel refetch result still log-only (documented TODO) — file follow-up issue so it doesn't rot

## Verdict

**⚠️ Needs Changes** (3/3 reviewers agree)

**Must fix:** M1 (POST duplicate risk) — third round, escalated to blocker
**Should fix:** M2 (typing retry budget)

Once M1 lands → ✅ Ready. The structural work, gateway hardening, and 204 fix are all solid.
