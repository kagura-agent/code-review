# 🌟 Stella Review — kagura-agent/cove PR #190 Round 3

**Rating: ⚠️ Needs Changes**

## 1. Summary

Round 3 fixes the most important R2 correctness hole: timeout and reconnect now invalidate the per-channel generation before releasing/aborting the wrapper, so a timed-out or reconnected stale dispatch can no longer pass the guarded send/edit/final-deliver paths (`packages/plugin/src/channel.ts:207-214`, `479-483`). The plugin tests and typecheck pass locally (`pnpm -F openclaw-cove test && pnpm -F openclaw-cove check`: 38 tests, clean tsc). However, several R2 items remain unaddressed, and under the explicit escalation rule they now block my approval: the exported abort wrapper still has the pre-aborted unhandled-rejection path, `channelGeneration` is still never cleaned, and not every dispatcher callback is explicitly generation-guarded.

## 2. Previous Issues Status

1. 🔴 **Generation not incremented on timeout/reconnect** — ✅ **Addressed.** Reconnect increments each pending channel generation before aborting (`channel.ts:207-214`), and timeout increments the channel generation before logging/releasing (`channel.ts:479-483`). This closes the stale send/edit-after-timeout/reconnect path I raised in R2.

2. 🟡 **Configurable `DISPATCH_TIMEOUT_MS`** — ❌ **Not addressed; escalated.** Timeout remains a hardcoded module constant (`channel.ts:14`). This is not the highest-risk issue, but it was explicitly raised in R2 and remains unchanged.

3. 🟡 **`channelGeneration` map never cleaned up** — ❌ **Not addressed; escalated.** `pendingDispatches` is cleaned, but `channelGeneration` only ever `set()`s (`channel.ts:205`, `211`, `281`, `481`) and never deletes. Cove channel IDs can be dynamic/ephemeral, so a long-running plugin accumulates one entry per channel ever touched.

4. 🟡 **UnhandledPromiseRejection risk on pre-aborted signal** — ❌ **Not addressed; escalated.** `createAbortableDispatch()` still returns before attaching `dispatch.then(...)` when `signal.aborted` is already true (`channel.ts:58-68`). If the already-created dispatch promise later rejects, nothing observes that rejection. This is currently covered by a test only for the wrapper rejection, not for the later dispatch rejection.

5. 🟡 **Not all dispatcher callbacks guarded** — ⚠️ **Partially mitigated, not fully addressed; escalated.** `deliver`, `onPartialReply`, and `sendOrEdit` are guarded (`channel.ts:283-285`, `346-348`, `380-382`). But `onToolStart`, `onItemEvent`, `onPlanUpdate`, `onApprovalEvent`, `onCommandOutput`, `onPatchSummary`, `onCompactionStart/End`, and `onAssistantMessageStart` still execute for stale dispatches (`channel.ts:387-420`). Many eventual visible updates are blocked by `sendOrEdit`, so this is less user-visible than R2's stale final delivery bug, but it is still not the explicit all-callback fence requested.

## 3. Critical Issues

### 1. Pre-aborted signals can still leave the underlying dispatch promise unobserved

`createAbortableDispatch()` accepts an already-created `dispatch` promise, but the pre-aborted branch rejects and returns before installing the `.then(..., ...)` observer (`channel.ts:58-68`). If that dispatch later rejects, Node can emit an unhandled rejection. R2 called this out; Round 3 did not change it.

**Fix:** Always attach the dispatch observer before handling abort state, or attach a rejection sink in the pre-aborted path, e.g. `dispatch.catch(() => {})` before returning. Prefer the former so cleanup behavior stays uniform.

### 2. `channelGeneration` is still an unbounded long-lived map

The new map is scoped to the account lifetime and never deletes entries. Normal completion, timeout, abort, reconnect, and plugin shutdown all leave generation entries behind (`channel.ts:202-214`, `280-281`, `479-493`). For stable channels this is small; for generated/test/ephemeral channel IDs, it is a slow memory leak.

**Fix:** Delete the generation entry once it is no longer needed. A safe pattern is: after normal completion, delete if `channelGeneration.get(channelId) === gen`; after timeout/reconnect invalidation, deletion is also safe because `undefined !== staleGen` still blocks stale callbacks. Add a unit/integration test for cleanup.

### 3. Stale dispatch progress callbacks still run

The side-effect fence is incomplete. Stale `onToolStart`/progress/compaction callbacks still mutate their old `toolProgress`/draft lifecycle and can enqueue work (`channel.ts:387-420`). The final network write is usually stopped by `sendOrEdit`'s generation check, but stale callbacks are still executing after the dispatch has been declared aborted/timed out.

**Fix:** Add a small `isCurrent()` helper and guard every callback at entry, not only the final send paths. This also makes the release-only semantics easier to audit.

## 4. Product Impact

- ✅ The original stuck-channel symptom is materially improved: a hung dispatch releases after 120s, reconnect aborts pending wrappers, and stale timeout/reconnect replies are now fenced.
- ⚠️ Long-running Cove instances can accumulate `channelGeneration` entries indefinitely as channels are touched.
- ⚠️ A rare pre-aborted wrapper path can still produce process-level unhandled rejection noise or test/runtime instability.
- ⚠️ Stale background dispatches may continue doing local progress work after users believe that dispatch was cancelled. Most user-visible message writes are blocked now, but resource waste and confusing logs remain possible.

## 5. Suggestions

1. Make `DISPATCH_TIMEOUT_MS` configurable via channel config and/or env, with `120_000` as the default (`channel.ts:14`). Different agents and tools have very different normal runtimes.
2. On plugin/account abort (`channel.ts:510-518`), also invalidate generations and abort all pending dispatch controllers, mirroring reconnect. Destroying the WebSocket alone does not stop already-running dispatches from using `restClient` before timeout.
3. Add integration tests around the actual `messageCreate → pendingDispatches → generation fence` lifecycle. The current tests mostly simulate maps/controllers rather than exercising the plugin callback wiring.
4. Add a regression test specifically for: timeout invalidates generation; reconnect invalidates generation; stale `deliver`/`onPartialReply`/tool-progress callback after invalidation causes no send/edit and no unhandled rejection.

## 6. Positive Notes

- The R3 generation bump on timeout/reconnect is the right fix for the main stale-reply bug.
- The controller identity check in `finally` remains correct and prevents an older dispatch from deleting a newer controller (`channel.ts:490-494`).
- Custom `DispatchTimeoutError` / `DispatchAbortedError` keep error classification robust.
- Tests and typecheck pass locally: 38 plugin tests, clean `tsc --noEmit`.
- The code now honestly documents release-only semantics instead of claiming true cancellation.
