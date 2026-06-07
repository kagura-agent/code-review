# Stella Review — PR #255 Round 4

## Verdict: ⚠️ Needs Changes

The duplicate-message blocker from Round 3 is fixed in the current diff, and the refactor still looks structurally sound. One previous Round 3 issue is only partially addressed: `sendTyping` now has a 3s fetch timeout, but it can still enter the shared 429 retry loop and wait up to ~120s across retry-after sleeps. Per the re-review escalation rule, this remains a blocker.

## Previous Issues Status

### 🔴 M1: POST `sendMessage` retries on 5xx/network → duplicate user messages
**Status: Addressed.**

- `packages/plugin/src/rest-client.ts:31` adds an idempotency check.
- `packages/plugin/src/rest-client.ts:51-59` retries 5xx only for idempotent methods.
- `packages/plugin/src/rest-client.ts:69-77` retries network errors only for idempotent methods.
- `sendMessage()` uses POST at `packages/plugin/src/rest-client.ts:110-114`, so ambiguous 5xx/network failures now fail fast instead of replaying potentially committed sends.

429 retry remains allowed for all methods (`packages/plugin/src/rest-client.ts:43-49`), which matches the previous review's accepted assumption that Cove's 429 means the request was not processed.

### 🔴 M2 escalated: `sendTyping` is still not true zero-retry best-effort
**Status: Partially addressed, still needs changes.**

`sendTyping()` now passes a 3s timeout signal:

- `packages/plugin/src/rest-client.ts:134-136`

But the request helper still applies the generic 429 retry loop before it returns:

- `packages/plugin/src/rest-client.ts:43-49`

That sleep is not bounded by the passed `AbortSignal`, and the code does not check `attempt < MAX_RETRIES` before sleeping. A typing request that receives `429 Retry-After: 30` can still keep the typing promise alive through multiple 30s sleeps. That violates the requested Round 3 fix: **zero retries + 3s timeout for typing**.

Why this matters:

- Typing is best-effort UX, not delivery-critical work.
- `dispatch.ts` calls typing both as an early fire-and-forget cue and through `createTypingCallbacks` (`packages/plugin/src/dispatch.ts:129-136`). If the SDK awaits `start()`, a long 429 sleep can still delay or entangle dispatch behavior for something that should be disposable.
- The 3s timeout only bounds the `fetch()`, not retry-after backoff sleeps.

Recommended fix: give `request()` per-call retry options, e.g. `{ retries: 0, timeoutMs: 3000, retry429: false }`, and call `sendTyping()` with all retries disabled. Alternatively, implement `sendTyping()` as a one-shot `fetch` with a 3s `AbortSignal.timeout(3000)` and no shared retry helper.

## Fresh Review Notes

No additional correctness blockers found in the current diff.

Positive points:

- The channel orchestration vs dispatch extraction is clearer (`channel.ts` delegates to `dispatch.ts`).
- The RESUME/reconnect split is sensible: `RESUMED` no longer aborts pending dispatches, while hard `READY` reconnect does.
- HEARTBEAT now includes the last sequence number (`gateway-client.ts:310-315`).
- `INVALID_SESSION` uses a current-socket guard before delayed IDENTIFY (`gateway-client.ts:153-158`).
- 204 responses are handled correctly (`rest-client.ts:67`).

## Verification

Ran locally on fetched PR head `52865fa`:

- `pnpm -F openclaw-cove test` ✅ 38 tests passed
- `pnpm -F openclaw-cove check` ✅ TypeScript check passed

## Rating

⚠️ Needs Changes — fix `sendTyping` so it is truly zero-retry / bounded to 3s, including 429 retry-after handling.