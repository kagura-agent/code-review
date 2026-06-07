# Consolidated Review R2 — cove#255: plugin mega-refactor

**Reviewers:** 🌟 Stella (pending) · 🌠 Nova · 💫 Vega
**Round:** 2

## R1 Issue Resolution

| # | Issue | Status |
|---|-------|--------|
| C1 | RESUMED aborts dispatches | ✅ Fixed — new `resumed` event, `reconnect` only on hard IDENTIFY |
| C2 | REST retry 5xx/network/backoff | ✅ Fixed — try/catch, 5xx retry, `1000 * 2^attempt + jitter` |
| C3 | Retry-After NaN/unbounded | ✅ Fixed — `Math.min(parseFloat(raw) \|\| 1, 30)` |
| C4 | INVALID_SESSION socket guard | ✅ Fixed — `currentWs` ref captured, readyState checked |
| C5 | Channel refetch discarded | ⚠️ Documented TODO — acceptable, file follow-up issue |
| C6 | RECONNECT undocumented | ✅ Fixed — clear comment added |
| C7 | invalidSessionTimer not tracked | ✅ Fixed — stored + cleared in destroy |

**All 3 blocking issues from R1 resolved.** 🎉

## New Issues Found in R2

### 🔴 `res.json()` on 204 No Content triggers retry storm (Vega)

`requestVoid` now delegates to `request<unknown>()`, which unconditionally calls `res.json()`. DELETE and POST /typing return 204 No Content with empty body → `SyntaxError: Unexpected end of JSON input` → caught as network error → retried 3 times → throw.

**Fix:**
```ts
if (res.status === 204) return undefined as unknown as T;
return res.json() as Promise<T>;
```

### 🟡 POST retries can duplicate messages (Nova)

`sendMessage` POST gets retried on 5xx/network errors. If server processed the request but response was lost → duplicate message. No idempotency key exists.

**Recommendation:** Gate 5xx/network retries on idempotent methods (GET, DELETE), or thread `idempotent: boolean` through `request()`.

### 🟡 `sendTyping` inherits full ~50s retry budget (Nova)

Typing has 5s keepalive cadence but now retries for up to 50s worst-case. Stacks up on slow gateway.

**Recommendation:** Tight timeout (3s) + zero retries for sendTyping.

### 🟢 `invalidSessionTimer` not cleared in `cleanup()` (Nova)

Cleared in `destroy()` but not `cleanup()`. Socket guard makes it benign, but symmetry with `clearResumeTimer()` would be cleaner.

## Verdict

**⚠️ Needs One Fix** — the 204 JSON parsing regression (Vega's 🔴) is a functional bug that will break deleteMessage and sendTyping at runtime. Fix that → ✅ Ready.

Nova's N1 (duplicate POST) and N2 (typing budget) are real concerns but can be follow-up issues since they don't cause crashes.
