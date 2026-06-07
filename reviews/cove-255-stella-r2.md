# Cove PR #255 — Stella R2 Review

PR: `kagura-agent/cove#255`  
Round: 2 — author addressed R1 issues  
Reviewer: 🌟 Stella

## R1 Status

1. ✅ **RESUMED emits `reconnect`, killing in-flight dispatches**
   - Fixed. `GatewayEvents` now has a separate `resumed` event, `RESUMED` dispatch emits `resumed`, and `channel.ts` only aborts `pendingDispatches` on hard `reconnect`/READY fallback.
   - Evidence: `packages/plugin/src/gateway-client.ts:190-196`, `packages/plugin/src/channel.ts:130-152`.

2. ✅ **REST retry only handles 429 — no 5xx/network retry, no exponential backoff**
   - Fixed for the R1 concern. `request()` now retries 5xx and network errors with exponential backoff+jitter.
   - Evidence: `packages/plugin/src/rest-client.ts:48-55`, `packages/plugin/src/rest-client.ts:64-70`.
   - Note: this fix introduced a new 204/no-body regression below.

3. ✅ **`Retry-After` unbounded + NaN-unsafe**
   - Fixed. `Retry-After` parse now falls back to `1` and caps at `30s`.
   - Evidence: `packages/plugin/src/rest-client.ts:41-44`.

4. ✅ **INVALID_SESSION delayed IDENTIFY no socket guard**
   - Fixed. Delayed IDENTIFY captures `currentWs` and checks both socket identity and `OPEN` state before sending.
   - Evidence: `packages/plugin/src/gateway-client.ts:153-157`.

5. ❌ **Channel refetch log-only**
   - Still not really addressed. On hard reconnect it fetches channels, but only logs the count and leaves a TODO for cache update.
   - Evidence: `packages/plugin/src/channel.ts:138-145`.
   - This remains lower severity if channel routing/cache is not implemented yet, but it is unchanged from R1.

6. ✅ **RECONNECT preserves seq/sessionId undocumented**
   - Fixed. The RECONNECT branch now documents that `seq` and `sessionId` are intentionally preserved for RESUME.
   - Evidence: `packages/plugin/src/gateway-client.ts:162-166`.

7. ✅ **INVALID_SESSION timer not tracked/cleared**
   - Mostly fixed. `invalidSessionTimer` is now stored and cleared on `destroy()`, and stale timers are guarded by socket identity/state.
   - Evidence: `packages/plugin/src/gateway-client.ts:39`, `packages/plugin/src/gateway-client.ts:111-114`, `packages/plugin/src/gateway-client.ts:153-157`.
   - Minor caveat: repeated `INVALID_SESSION` frames before the first timer fires would overwrite the handle without clearing the older timeout, but the socket guard limits practical damage.

## New Issues / Regressions

### 🔴 `requestVoid()` now parses 204 responses as JSON, breaking successful DELETE and typing requests

`requestVoid()` was changed to delegate to `request<unknown>()`:

- `packages/plugin/src/rest-client.ts:79-80`

But `request()` always returns `res.json()` for any successful response:

- `packages/plugin/src/rest-client.ts:63`

Cove's server intentionally returns `204 No Content` for both message deletion and typing:

- `packages/server/src/routes/messages.ts:142` — DELETE message returns 204
- `packages/server/src/routes/messages.ts:225` — typing returns 204

On Node/fetch, `new Response(null, { status: 204 }).json()` rejects with `SyntaxError: Unexpected end of JSON input`. So successful `deleteMessage()` and `sendTyping()` calls now reject as failures.

Impact:
- `sendTyping()` fire-and-forget initial call is caught, but typing keepalive/onStart paths may log warnings and silently lose typing indicators.
- `deleteMessage()` now reports failure even when the server deleted the message successfully, so draft cleanup/fallback paths produce misleading warnings and public `deleteMessage()` is broken.
- Any future void endpoint using 204 will also fail.

Recommended fix:

```ts
if (res.status === 204) return undefined as T;
return res.json() as Promise<T>;
```

or keep `requestVoid()` as a separate implementation that does not parse the body.

## Verification

- `pnpm -F openclaw-cove test` ✅ — 38 tests passed
- `pnpm -F openclaw-cove check` ✅ — TypeScript passed
- Manual Node check: `Response(null, { status: 204 }).json()` rejects with `SyntaxError: Unexpected end of JSON input` ✅

## Verdict

⚠️ **Request changes.**

Most R1 gateway/retry issues were addressed, but the REST refactor introduced a real regression for all 204/no-content endpoints. I would not merge until `requestVoid()` / 204 handling is fixed. The channel-refetch TODO from R1 also remains unresolved, but the 204 parsing regression is the merge blocker.
