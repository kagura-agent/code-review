# 🌠 Nova — Round 6 Review: cove PR #255

**Verdict: ✅ Ready**

## R5 Critical Bug — RESOLVED

The "POST/PATCH retry on 5xx via try/catch fallthrough" bug is fixed.

In the new `rest-client.ts` `request()`:

- 5xx branch in the `try`: `lastError = new Error(...); if (isIdempotent && attempt < MAX_RETRIES) { ...continue; } throw lastError;`
- That `throw lastError` is caught by the `catch (err)` below, which re-sets `lastError` to the same error and then runs:
  ```ts
  if (isIdempotent && attempt < MAX_RETRIES) { ...continue; }
  throw lastError;
  ```
- For POST/PATCH (`isIdempotent === false`), the catch block now ends with `throw lastError;` — the loop exits, no second fetch. ✅

This is the missing terminal throw that R5 flagged. Verified by inspection of the diff.

## Test Coverage — Confirmed

`packages/plugin/src/rest-client.test.ts` (new file) explicitly asserts the regression cases:

- ✅ `POST (sendMessage) does NOT retry on 500` → `toHaveBeenCalledTimes(1)`
- ✅ `PATCH (editMessage) does NOT retry on 500` → `toHaveBeenCalledTimes(1)`
- ✅ `POST does NOT retry on fetch error` → `toHaveBeenCalledTimes(1)`
- ✅ `AbortError thrown immediately without retry` (GET and POST)
- ✅ `429 retries all methods including POST` (post-rejection retry is safe)
- ✅ `Retry-After capped at 30s` and garbage falls back to 1s
- ✅ `GET retries up to 3 times then succeeds / throws after exhausting`
- ✅ `DELETE retries on 500`
- ✅ `204 returns undefined` for both deleteMessage and sendTyping
- ✅ `sendTyping passes AbortSignal to fetch`

This is exactly the test surface R5 asked for. The regression is now locked down.

## Cross-Check on Previously Confirmed Items

All confirmed good across rounds — re-verified in this diff:

- **Gateway RESUME/RESUMED** (`gateway-client.ts`): seq tracked on DISPATCH, sessionId stored on READY, RESUME sent on HELLO when state present, RESUME_TIMEOUT_MS fallback to IDENTIFY, INVALID_SESSION clears state with 1–5s jitter, RECONNECT preserves seq/sessionId for next RESUME attempt, HEARTBEAT carries seq, `clearResumeTimer()` called on close/cleanup, `invalidSessionTimer` cleared in `destroy()` and `cleanup()`. ✅
- **dispatch.ts extraction**: `channel.ts` reduced to wiring/event-handling; all per-message state (draft lifecycle, tool progress, edit queue, isCurrent check) moved verbatim into `dispatchMessage()`. Behavior preserved (controller registered synchronously before any `await`, finally only deletes its own controller). ✅
- **`reconnect` semantics**: now correctly describes hard reconnect (post-failed-RESUME). Channel refetch on reconnect is a sensible recovery hook (TODO documented). ✅
- **`resumed` event**: emitted distinctly from `reconnect`; channel handler logs without aborting in-flight dispatches — correct, since RESUME implies no event loss. ✅
- **`send()` privatised** on the gateway client (was `public`); all sends go through typed methods. ✅
- **204 handling**, **Retry-After parsing + 30s cap**, **sendTyping 3s timeout** via `AbortSignal.timeout(3000)`. ✅

## Minor Observations (non-blocking)

1. **Edge in 429 loop termination** (`rest-client.ts`): the 429 branch only `continue`s without checking `attempt < MAX_RETRIES`. The `for` bound still caps total attempts at 4, but if every attempt returns 429, the loop exits without `lastError` ever being set and throws the generic `"failed after retries"`. Cosmetic — error message is less informative than the 429 path warrants. Suggest: in the 429 branch, set `lastError = new Error(\`Cove API ${method} ${path} rate-limited (429)\`)` before `continue`.

2. **`request()` `signal` parameter** is plumbed but only `sendTyping` uses it. Future callers can wire per-call cancellation; current uses are fine.

3. **`reconnect` channel refresh**: fire-and-forget; the result is logged but the TODO admits no consumer yet. Acceptable as a placeholder hook — just don't let the TODO age silently.

4. **`VOICE_STATE_UPDATE = 4` "reserved/locked out"** comment in `shared/types.ts` is added as an enum member but there's no runtime guard in `send()` to refuse it. Comment-only enforcement. Low risk because `send()` is now private and no caller emits opcode 4, but if hardening is desired, an assertion in the typed senders would make "locked out" literal.

5. **`pendingDispatches` Map of `channelId → controller`** continues to be the single source of identity. Verified `dispatch.ts` keeps the synchronous-register-before-await invariant.

## Summary

R5's critical bug is fixed with the correct control-flow change AND backed by unit tests that pin the regression. Refactor extraction of `dispatch.ts` is faithful to the original. Gateway RESUME path is complete and defensively timed. No new issues of consequence introduced. The minor items above are quality-of-life polish, not blockers.

**Recommendation: merge.**
