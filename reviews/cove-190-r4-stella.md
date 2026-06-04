# 🌟 Stella Review — Cove PR #190 Round 4

## 1. Summary

**Rating: ❌ Major Issues**

The Round 4 update fixes the most obvious `createAbortableDispatch` unhandled-rejection hole and adds broad callback-entry generation checks. Plugin typecheck and unit tests pass locally.

However, I still do **not** think this is safe to merge. Two previous R3 blockers remain materially unresolved:

1. `channelGeneration` is still leaked on the reconnect-abort path because reconnect clears `pendingDispatches` before each aborted handler reaches `finally`, so the `finally` cleanup condition skips deletion.
2. The stale-dispatch guard is still not close enough to the side effects. A dispatch can pass `isCurrent()` at callback entry, become stale while waiting in the edit queue or during `draft.seal()`, and then still send/edit Cove messages.

These are exactly the failure modes this PR is meant to harden: stale work after reconnect/replacement must not leak resources or produce visible output.

Verification run locally:

```bash
pnpm -F openclaw-cove test
# 38 passed

pnpm -F openclaw-cove check
# tsc --noEmit passed
```

## 2. Previous Issues Status

### R3-1 — 🔴 UnhandledPromiseRejection on pre-aborted signal

**Status: ✅ Addressed**

`createAbortableDispatch()` now attaches `dispatch.catch(() => {})` before returning on an already-aborted signal (`packages/plugin/src/channel.ts:54-59`). For normal timeout/abort races, it also attaches a rejection handler through `dispatch.then(..., err => ...)` (`channel.ts:65-68`), so a later dispatch rejection should be observed even after the wrapper has already rejected.

Minor cleanup note: the timeout path does not remove the abort listener, but because the controller is normally released this is not the blocker.

### R3-2 — 🔴 `channelGeneration` map never cleaned / unbounded growth

**Status: ❌ Still not fully addressed — escalated**

Normal completion/timeout now deletes the generation entry when the current controller is still in `pendingDispatches` (`channel.ts:503-508`). That fixes the happy path.

But the reconnect path still leaks entries:

- Reconnect increments `channelGeneration` for each pending channel (`channel.ts:208-214`).
- It then immediately calls `pendingDispatches.clear()` (`channel.ts:215`).
- Each aborted dispatch later reaches `finally`, but `pendingDispatches.get(channelId) === abortController` is now false because the map was cleared, so `channelGeneration.delete(channelId)` is skipped (`channel.ts:503-508`).

Result: every channel that had an in-flight dispatch during reconnect can leave a permanent generation entry unless another message later arrives in the same channel and completes normally. Across repeated reconnects and many channels, this is still an unbounded per-channel memory leak.

### R3-3 — 🔴 Incomplete callback guards / stale dispatch side effects

**Status: ⚠️ Partially addressed, but still unsafe — escalated via fresh race finding**

The PR now adds `isCurrent()` checks to the previously missing callback entry points: `onToolStart`, `onItemEvent`, `onPlanUpdate`, `onApprovalEvent`, `onCommandOutput`, `onPatchSummary`, `onCompactionStart`, `onCompactionEnd`, and `onAssistantMessageStart` (`channel.ts:384-433`). This is good progress.

But the guard is only at callback entry. It does not guard the actual async side-effect points:

- `sendOrEdit()` checks `isCurrent()` before enqueueing, but the queued `editQueue.then(async () => { ... restClient.editMessage/sendMessage ... })` does **not** re-check after waiting behind prior edits (`channel.ts:287-300`). If a new message or reconnect invalidates the dispatch while the stale update is queued, it can still edit/send after becoming stale.
- `deliver()` checks `isCurrent()` once, then awaits `draft.seal()` before final `editMessage`/`sendMessage` (`channel.ts:350-372`). If the dispatch becomes stale during `draft.seal()` or while waiting for an in-flight preview edit, the final reply can still be delivered after invalidation.
- `deleteMessage` inside the draft lifecycle also has no generation guard (`channel.ts:319-327`), so stale cleanup can delete a draft after ownership has changed if timing lines up.

The product promise is “stale dispatches cannot send messages.” The current implementation reduces the window but does not close it.

## 3. Critical Issues

### 🔴 Critical: reconnect still leaks `channelGeneration` entries

**Location:** `packages/plugin/src/channel.ts:208-215`, `503-508`

On reconnect, the code invalidates all pending generations and clears `pendingDispatches`. That prevents each aborted dispatch from satisfying the `finally` cleanup condition, leaving the `channelGeneration` entry behind.

Suggested shape:

- Track `{ controller, generation }` per pending dispatch, not just controller.
- In `finally`, delete `channelGeneration` when no newer dispatch owns the channel, even if reconnect already removed the pending entry.
- Or avoid clearing `pendingDispatches` until each aborted dispatch has had a chance to clean itself, while still preventing stale ownership from deleting newer controllers.

The key invariant should be: after abort/timeout/reconnect settles and there is no newer dispatch for that channel, both `pendingDispatches` and `channelGeneration` are empty for that channel.

### 🔴 Critical: stale dispatch can still perform queued/final message side effects

**Location:** `packages/plugin/src/channel.ts:287-300`, `350-372`, `319-327`

Generation checks need to be immediately adjacent to the Cove REST side effects, not only at callback entry. The current code allows this sequence:

1. Dispatch A calls `sendOrEdit()` while current and queues an edit.
2. Dispatch B arrives or gateway reconnects, invalidating A.
3. A's queued edit runs later and calls `restClient.editMessage()` or `restClient.sendMessage()` without re-checking `isCurrent()`.

A similar race exists in final delivery after `await draft.seal()`.

Suggested minimum fix:

- Re-check `isCurrent()` inside the `editQueue` callback immediately before mutating `lastSentText`, `draftMessageId`, or calling REST.
- Re-check after any awaited operation before final delivery, especially after `await draft.seal()`.
- Guard `deleteMessage` or ensure stale draft cleanup cannot affect a newer dispatch's draft.
- Add regression tests using controllable promises so invalidation happens while an edit/final delivery is queued or awaiting seal.

## 4. Product Impact

If merged as-is, Cove will be more resilient than before, but the core reconnect/replacement guarantee remains leaky:

- Long-lived plugin processes can still accumulate `channelGeneration` entries for channels active during reconnects.
- A user can still see stale streaming edits or final replies from a prior dispatch after sending a newer message or after a reconnect.
- The most confusing failure mode remains possible: the bot appears to answer with old context after a restart/replacement, undermining trust in per-channel dispatch isolation.

Because this PR specifically claims stale dispatches cannot send messages, the remaining race is a correctness blocker, not just polish.

## 5. Suggestions

1. **Make dispatch ownership explicit.** Store a small token object per channel, e.g. `{ generation, controller }`, and compare token identity at every side-effect boundary.
2. **Centralize stale checks.** Wrap Cove REST calls in helpers like `sendIfCurrent`, `editIfCurrent`, `deleteIfCurrent`, and call them after waits/queue delays.
3. **Add true integration-style unit tests.** Current reconnect/same-channel tests simulate local maps only (`dispatch-resilience.test.ts:53-102`); they do not exercise the plugin handler, generation cleanup, callback guards, or queued REST side effects. Add tests that prove:
   - reconnect leaves `channelGeneration.size === 0` after aborted dispatches settle;
   - a queued stale stream edit does not call `sendMessage`/`editMessage`;
   - final `deliver` does not call REST if invalidated during `draft.seal()`.
4. **Abort on plugin shutdown.** `ctx.abortSignal` currently only destroys the gateway client (`channel.ts:524-526`). It should also abort pending dispatches and cleanup typing/generation state.
5. **Consider configurable timeout.** `DISPATCH_TIMEOUT_MS` is still hard-coded at 120s. That is acceptable for an initial fix, but production tuning/debugging would benefit from config/env override.
6. **Document `reconnect` event semantics.** The new event fires after READY on subsequent connections (`gateway-client.ts:126-131`). A short JSDoc in `types.ts`/`gateway-client.ts` would clarify that it does not fire on first connect.

## 6. Positive Notes

- The pre-aborted unhandled-rejection bug from R3 was handled cleanly.
- Broad callback-entry guards were added for the previously missing tool/progress/compaction callbacks.
- The reconnect event avoids firing on the first READY, which is the right semantic distinction.
- Local plugin tests and TypeScript check pass.
- The PR is moving in the right direction; the remaining work is about tightening ownership invariants around async boundaries.
