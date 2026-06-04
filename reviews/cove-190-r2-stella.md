# Stella R2 Review — kagura-agent/cove PR #190

## 1. Summary

Rate: ❌ Major Issues

The R2 update fixes two of the three R1 findings and improves the design with custom error classes plus per-channel generation tokens. However, the central abort/cancellation problem is still not fully addressed: timeout and reconnect abort paths do not invalidate the channel generation, so the underlying stale dispatch can still send/edit later if no newer message has advanced the generation.

I verified the diff locally on branch `pr-190-r2` and ran:

- `pnpm -F openclaw-cove test` — ✅ 38 passed
- `pnpm -F openclaw-cove check` — ✅ clean

The test suite passes, but it does not cover the important stale-dispatch-after-timeout/reconnect side-effect scenario.

## 2. Previous Issues Status

### R1-1 🔴 Abort is observational, not cancellative — **Partially addressed, still blocking**

R2 adds generation guards around:

- `sendOrEdit()`
- dispatcher `deliver`
- `onPartialReply`

This blocks stale side effects when a *new same-channel message* arrives, because `channelGeneration` is incremented for the new dispatch before the old controller is aborted.

But timeout and reconnect aborts do **not** increment/invalidate `channelGeneration`:

- `gatewayClient.on("reconnect")` aborts controllers and clears `pendingDispatches`, but leaves `channelGeneration` unchanged.
- `DispatchTimeoutError` catch cleans typing/logs, but also leaves `channelGeneration` unchanged.

Because `createAbortableDispatch()` is explicitly release-only, the underlying `dispatchInboundDirectDmWithRuntime()` promise continues running. If that stale dispatch later reaches `deliver`, `onPartialReply`, or queued `sendOrEdit`, the generation check still passes when no newer same-channel message has happened.

So the most important ghost-dispatch case remains possible for timeout and reconnect.

### R1-2 🔴 Typing indicator leaked on timeout/abort — **Mostly addressed**

R2 now calls `typingCallbacks.onCleanup?.()` in both timeout and abort catch paths, plus the outer catch still cleans up. This addresses the direct leak from the wrapper rejection path.

Residual concern: because the underlying dispatch continues after abort/timeout, any late SDK path that can restart/use `typingCallbacks` is still not guarded. The larger generation invalidation fix should also wrap or disable these callbacks for stale generations.

### R1-3 🟡 Error identity by string compare — **Addressed**

Production code now uses `DispatchTimeoutError` and `DispatchAbortedError` with `instanceof` checks instead of comparing `err.message`. Good.

Tests still assert by message text, but that is only a test-style weakness, not a production correctness issue.

## 3. Critical Issues

### 🔴 Timeout and reconnect do not invalidate stale generations

Location: `packages/plugin/src/channel.ts`

Relevant paths:

- `gatewayClient.on("reconnect", ...)` lines ~207-213
- timeout/abort catch around lines ~476-482
- generation guard checks around lines ~281-345/378

Current R2 logic:

```ts
const gen = (channelGeneration.get(channelId) ?? 0) + 1;
channelGeneration.set(channelId, gen);
...
if (channelGeneration.get(channelId) !== gen) return;
```

This only becomes stale when a later dispatch increments the generation. But timeout/reconnect aborts are also supposed to make the current dispatch stale. They currently do not.

Concrete failure sequence:

1. Channel A receives message M1; generation becomes `1`.
2. M1 dispatch hangs.
3. After 120s, `createAbortableDispatch()` rejects with `DispatchTimeoutError`.
4. Catch calls typing cleanup and removes the controller from `pendingDispatches`.
5. `channelGeneration.get(channelA)` is still `1`.
6. The underlying M1 dispatch continues and later calls `onPartialReply`/`deliver`/`sendOrEdit`.
7. Generation check sees `1 === 1`, so the stale dispatch can still send/edit.

Reconnect has the same shape:

1. Pending dispatch generation is `1`.
2. Gateway reconnect fires.
3. Controller is aborted and map cleared.
4. Generation remains `1`.
5. Old dispatch can still pass side-effect guards after reconnect.

This is the same class of bug R1 flagged, so per the escalation rule it remains blocking.

Suggested fix:

- Treat abort/timeout/reconnect as generation-invalidation events, not only controller events.
- Centralize cancellation so every abort path bumps the channel token before/while aborting.

For example:

```ts
const invalidateChannel = (channelId: string) => {
  channelGeneration.set(channelId, (channelGeneration.get(channelId) ?? 0) + 1);
};

const abortChannelDispatch = (channelId: string) => {
  invalidateChannel(channelId);
  pendingDispatches.get(channelId)?.abort();
  pendingDispatches.delete(channelId);
};
```

For reconnect, iterate channel IDs and invalidate each one. For timeout, invalidate only if the timed-out controller is still current.

Also consider using an explicit per-dispatch token object/current-dispatch id rather than a raw numeric map, so invalidation is harder to miss.

### 🔴 Stale dispatch side-effect guards are incomplete

R2 guards final delivery and partial text updates, but several runtime callbacks still execute for stale dispatches:

- `onToolStart`
- `onItemEvent`
- `onPlanUpdate`
- `onApprovalEvent`
- `onCommandOutput`
- `onPatchSummary`
- `onCompactionStart`
- `onCompactionEnd`
- `onAssistantMessageStart`

Some of these mutate `toolProgress`; several call `draft.update()` indirectly through `onProgressUpdate`, and `onCompactionStart` calls `draft.update()` directly after computing combined text.

`sendOrEdit()` currently has a generation guard, so many REST writes may be blocked once the generation is actually invalidated. But without guarding these callbacks, stale dispatches can still create timers/queued draft work and mutate per-dispatch state after abort. This is especially risky because `createFinalizableDraftLifecycle` is stateful and throttled.

Suggested fix:

- Define a local helper:

```ts
const isCurrent = () => channelGeneration.get(channelId) === gen;
```

- Use it in every callback passed into the dispatcher/reply options, not just `deliver` and `onPartialReply`.
- Ideally wrap all callback registration through a small `ifCurrent(fn)` helper to avoid future omissions.

## 4. Product Impact

The PR is intended to fix Cove plugin sessions getting stuck after restarts and prevent old dispatches from affecting the channel. In R2, users are protected when a newer same-channel message arrives, but not in the timeout/reconnect case itself.

Potential user-visible outcomes:

- A timed-out response can appear minutes later as a ghost reply.
- A dispatch from before a server restart/reconnect can still edit/send after the reconnect.
- The plugin may report that it aborted/released a pending dispatch while the old dispatch still has effective channel side effects.
- Stale progress/typing/draft state can continue to churn in the background, making reconnect behavior harder to reason about.

For a resilience fix, this is a correctness issue rather than polish.

## 5. Suggestions

1. **Invalidate generation on every abort/timeout/reconnect path.** This is the main blocker.
2. **Guard every dispatcher callback with `isCurrent()`.** Do not rely on only `sendOrEdit`/`deliver`/`onPartialReply`.
3. **Add regression tests for stale side effects after timeout/reconnect.** The current tests validate `AbortController` mechanics, but not the plugin’s generation-token semantics. Add focused tests where:
   - a dispatch times out;
   - the underlying promise later invokes a fake `deliver`/partial/progress callback;
   - assert no send/edit/draft update happens.
4. **Abort pending dispatches on plugin shutdown.** `ctx.abortSignal` currently destroys the gateway client but does not abort `pendingDispatches` or invalidate generations. Shutdown is another stale-dispatch path.
5. **Optional:** make `DISPATCH_TIMEOUT_MS` configurable later. Not blocking for this PR, but useful operationally.

## 6. Positive Notes

- Custom error classes are a clean improvement over string comparisons.
- The same-channel replacement path is meaningfully better now: a new message increments generation and aborts the previous controller.
- Typing cleanup is now present in the wrapper timeout/abort catch paths.
- The code documents the release-only semantics clearly, which is good and helped reveal exactly where the remaining guard needs to be stronger.
- Local plugin tests and typecheck pass.
