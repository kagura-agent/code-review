# 🌠 Nova — Round 4 Review: cove PR #255

**Verdict: ✅ Ready**

## R3 Carryover Issues — Re-verification

### 🔴 M1 (R3) — POST `sendMessage` retries on 5xx → duplicate user messages
**Status: ✅ Fixed (correctly)**

`packages/plugin/src/rest-client.ts:34`:
```ts
const isIdempotent = method === "GET" || method === "DELETE" || method === "HEAD" || method === "PUT";
```

- **5xx path** (`:50-58`): retries only when `isIdempotent && attempt < MAX_RETRIES`. POST and PATCH now bypass retry and throw immediately. ✅
- **Network error path** (`:71-75`): same `isIdempotent` gate. POST/PATCH no longer retry on `fetch` rejection. ✅
- **429 path** (`:42-47`): still retries all methods unconditionally. Correct — 429 is a server-side rejection before processing, so retrying POST is safe. ✅
- **AbortError pass-through** (`:69`): user-supplied `signal` aborts bail out instantly without retry. ✅

User-message duplication risk is eliminated. The fix is exactly what R3 specified.

### 🟠 M2 (R3) — `sendTyping` inherits full retry budget
**Status: ✅ Substantially fixed (with one minor nit)**

`rest-client.ts:135`:
```ts
return this.requestVoid("POST", `${API_PREFIX}/channels/${channelId}/typing`, undefined, AbortSignal.timeout(3000));
```

- 3s per-attempt timeout: ✅ matches spec
- POST + 5xx → no retry (per M1 fix): ✅
- POST + network error → no retry: ✅
- **Minor gap**: 429 still retries up to `MAX_RETRIES` times with `Retry-After` honored (up to 30s each). Worst-case typing call could block ~120s on persistent 429s. Practically benign because: (a) call sites use `.catch(() => {})` and don't await, (b) 429 on typing is extremely unlikely, (c) blocking only delays the next keepalive tick. Not a blocker — the dominant fix (network/5xx no longer retry) is in place.

If we wanted to be strict, `sendTyping` could thread a `noRetry` flag through `request()`. Not required for merge.

---

## Fresh Review — New Code

### `dispatch.ts` (extraction)
Pure code-motion from `channel.ts`. Spot-checked vs the deleted block — logic, abort semantics, `isCurrent()` reference-equality guards, `editQueue` ordering, draft seal/fallback flow all preserved. Import of `Message` from `@cove/shared` is consistent with existing type surface. ✅

### `gateway-client.ts` — RESUME machinery
- **HELLO branch** (`:122-126`): correctly attempts RESUME when `sessionId && seq !== null`, else IDENTIFY. ✅
- **`sendResume` + `resumeTimer`** (`:269-289`): 5s fallback to IDENTIFY if server never responds (e.g. older server without RESUME support). Clears `sessionId`/`seq` before re-identifying. ✅
- **`RESUMED` handler** (`:196-203`): does NOT emit `reconnect` — instead emits `resumed`. This is the critical fix: `channel.ts` aborts pending dispatches on `reconnect` but leaves them alone on `resumed`. State preserved across transient WS blips. ✅
- **`INVALID_SESSION`** (`:148-162`): clears session state, schedules re-IDENTIFY with 1–5s jitter, guarded by `this.ws === currentWs` so a closed/reconnected socket won't double-IDENTIFY. ✅
- **`RECONNECT`** (`:164-170`): closes with 4000 but **preserves** `seq`/`sessionId`, so the subsequent reconnect attempts RESUME. Correct. ✅
- **HEARTBEAT seq** (`:312`): now sends `this.seq` as `d` (was `null`). Discord-compatible. ✅
- **Timer cleanup**: `cleanup()` clears all three timers (heartbeat, resume, invalidSession); `disconnect()` clears reconnect + invalidSession + resume timers. No leaks. ✅
- **`send()` privatized** (`:327`): good encapsulation hardening; eliminates the risk of external code firing arbitrary opcodes.

### `channel.ts` — orchestration
- Hard reconnect handler aborts pending dispatches and re-fetches channel list (with `TODO` for future routing). ✅
- `resumed` handler only logs — correct, since dispatches are still valid. ✅
- Single `restClient` instance hoisted out of the per-message path. Minor perf/clarity win. ✅
- Delegation to `dispatchMessage` is clean; no behavioral drift.

### `types.ts`
- New event signatures match `gateway-client.ts` emit shapes. ✅
- Added `Channel` import — used. ✅

### `shared/src/types.ts`
- `RESUME = 6`, `RECONNECT = 7`, `INVALID_SESSION = 9` — Discord-compatible numeric values. ✅
- `VOICE_STATE_UPDATE = 4` reserved with a comment explaining it's locked out. Defensive and clear. ✅

---

## Other Observations

- **`AbortSignal.timeout` error name**: in Node 20+ this throws `DOMException("TimeoutError")` rather than `AbortError`. The check at `rest-client.ts:69` (`err.name === "AbortError"`) only short-circuits user-supplied aborts. Timeout errors fall through to retry logic — which for POST means "no retry" (correct), for GET/DELETE means "retry" (also correct). Behavior is right, but worth a code comment to prevent future confusion.
- **Retry-After parsing** (`:44`): `parseFloat("") || 1` correctly defaults to 1s. `Math.min(..., 30)` caps the wait. Solid.
- **`dispatch.ts:115` `Message` import**: ensure `@cove/shared` exports `Message` (it does — channel.ts already imported it transitively). ✅

---

## Summary

R3's two carryover blockers are resolved with the correct semantics. The RESUME/RECONNECT/INVALID_SESSION machinery is well-formed and Discord-compatible. The `dispatch.ts` extraction is a faithful move. M2's residual 429-on-typing edge is benign and not blocking.

**Ship it.** 🚀

/home/kagura/.openclaw/workspace/code-review/reviews/cove-255-nova.md
