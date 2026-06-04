# PR #190 Round 5 Review — Stella

## 1. Summary

❌ **Major Issues**

Round 5 correctly removes the generation-counter reuse bug by switching stale-dispatch checks to `AbortController` reference equality. That is the right direction.

However, the PR still does not fully enforce that aborted/timed-out/replaced dispatches cannot perform side effects. Two Round 4 issues remain unaddressed and must escalate under the review rules:

- queued stream edits can still run after the dispatch is no longer current;
- final delivery can still send/edit after the dispatch was invalidated while awaiting `draft.seal()`.

There is also a fresh ordering race: because the per-channel controller is installed only after several awaits, an older message handler can resume late and abort a newer message's dispatch.

## 2. Previous Issues Status

1. 🔴 **Generation ID reuse via `.delete()`** — ✅ **Addressed**
   - `channelGeneration` is gone in the PR head, and `isCurrent()` now compares `pendingDispatches.get(channelId) === abortController` (`packages/plugin/src/channel.ts:277-278`).
   - This avoids the previous counter-reset/reuse class of stale-output bugs.

2. 🟡 **Reconnect leaks `channelGeneration` entries** — ✅ **Addressed by removal**
   - Since `channelGeneration` was eliminated, this specific leak is gone.
   - `pendingDispatches.clear()` after abort is acceptable for map cleanup because stale callbacks now consult controller identity rather than a generation map (`packages/plugin/src/channel.ts:206-211`).

3. 🟡 **Queued side-effect race** — ❌ **Unaddressed; escalated**
   - `sendOrEdit()` checks `isCurrent()` before enqueueing, but the queued function performs REST writes later without rechecking (`packages/plugin/src/channel.ts:280-301`).
   - `deliver()` checks `isCurrent()` only at callback entry, then awaits `draft.seal()` and afterwards may call `editMessage`, `sendMessage`, or `cleanupAndSend` without another freshness check (`packages/plugin/src/channel.ts:343-366`).
   - This still permits stale dispatches to mutate Cove after replacement, timeout, reconnect, or shutdown.

4. 🟡 **Configurable timeout** — ❌ **Unaddressed; escalated**
   - Timeout remains a file-level constant: `const DISPATCH_TIMEOUT_MS = 120_000` (`packages/plugin/src/channel.ts:16`).
   - There is still no config/env path for deployments with different latency and model-runtime profiles.

5. 🟡 **Plugin shutdown should abort pending dispatches** — ❌ **Unaddressed; escalated**
   - Shutdown only destroys the gateway client (`packages/plugin/src/channel.ts:514-516`).
   - It does not abort controllers in `pendingDispatches`, clear the map, or invalidate in-flight side effects.

## 3. Critical Issues

### 🔴 1. Stale queued stream edits can still send after abort/replacement

**Location:** `packages/plugin/src/channel.ts:280-301`

`sendOrEdit()` does this:

1. checks `isCurrent()`;
2. appends work to `editQueue`;
3. later, inside `editQueue.then(...)`, sends/edits via REST without rechecking currentness.

If a stream update is queued while current, then a newer message/reconnect/timeout aborts this dispatch before the queued work executes, the stale queued task still sends or edits a message.

This directly violates the PR's safety claim that stale dispatches cannot send messages.

**Fix:** recheck freshness inside the queued section immediately before any state mutation / REST call, and ideally after awaits too:

```ts
editQueue = editQueue.then(async () => {
  if (!isCurrent()) { resolve(false); return; }
  ...
  if (!isCurrent()) { resolve(false); return; }
  await restClient.editMessage(...);
});
```

Also consider passing the abort signal into helper/lifecycle code so queued work can be cancelled instead of only becoming no-op.

### 🔴 2. Final delivery can still send after invalidation while awaiting `draft.seal()`

**Location:** `packages/plugin/src/channel.ts:343-366`

`deliver()` checks `isCurrent()` only at entry. Then it calls:

```ts
await draft.seal();
```

After that await, the dispatch may have been replaced, aborted by reconnect, timed out, or stopped by plugin shutdown. The code still proceeds to `editMessage()` / `cleanupAndSend()`.

This is the same side-effect race from Round 4 and must be fixed before merge.

**Fix:** recheck after `await draft.seal()` and before each fallback send/edit/delete path:

```ts
await draft.seal();
if (!isCurrent()) return;
```

Also ensure `cleanupAndSend()` is not called from a stale dispatch unless explicitly guarded by the caller.

### 🔴 3. Fresh issue: older same-channel handlers can abort newer dispatches before tracking is installed

**Location:** `packages/plugin/src/channel.ts:250-443`

The controller is added to `pendingDispatches` only after multiple asynchronous steps:

- dynamic import (`await loadDirectDm()`);
- plugin/draft/tool-progress setup;
- `await setTimeout(..., 1)`.

Because `messageCreate` handlers are async and EventEmitter does not serialize them, two same-channel messages can overlap like this:

1. older message A enters and pauses on an await;
2. newer message B resumes first, sets controller B, starts dispatch;
3. older message A resumes later, sees controller B as existing, aborts B, sets controller A, and starts the stale older dispatch.

That means "new message replaces pending dispatch" is not reliably tied to message arrival order; it is tied to whichever async handler reaches line 436 last.

**Product impact:** a newer user message can be cancelled by an older delayed handler, causing Cove to answer the wrong prompt and discard the latest user intent.

**Fix options:**

- install a per-channel sequence/controller synchronously at the top of `messageCreate`, before any await, then use that token for all later `isCurrent()` checks; or
- maintain a per-channel serialized queue that records arrival order and only lets the latest arrival proceed; or
- compare monotonic message timestamps/sequence numbers before aborting/replacing.

### 🔴 4. Plugin shutdown still leaves dispatches running

**Location:** `packages/plugin/src/channel.ts:514-516`

On `ctx.abortSignal`, the code only calls `gatewayClient.destroy()`. Existing `pendingDispatches` controllers are not aborted.

Since `createAbortableDispatch()` is release-only and the underlying dispatch can keep running, shutdown should invalidate all pending channel controllers and clear the map exactly like reconnect does. Otherwise a stopped/reloaded plugin can still send messages or continue queue work after lifecycle teardown.

**Fix:** centralize an `abortAllPending(reason)` helper and call it from reconnect and shutdown:

```ts
const abortAllPending = (reason: string) => {
  log?.info?.(`cove: ${reason} — aborting ${pendingDispatches.size} pending dispatch(es)`);
  for (const controller of pendingDispatches.values()) controller.abort();
  pendingDispatches.clear();
};

ctx.abortSignal.addEventListener("abort", () => {
  abortAllPending("plugin shutdown");
  gatewayClient.destroy();
});
```

Then combine this with the rechecks above so already-queued side effects cannot leak.

## 4. Product Impact

- Users can still receive stale assistant output after sending a newer same-channel message.
- A Cove reconnect or timeout may release the channel lock but not fully prevent old REST writes.
- Plugin shutdown/reload can leave old dispatches alive, causing confusing duplicate or late messages after the plugin is supposed to be stopped.
- Hardcoded 120s timeout may be too short for slow legitimate runs or too long for interactive channels, with no deployment-level override.

## 5. Suggestions

1. Move per-channel invalidation token/controller creation to the very top of the `messageCreate` handler, before any await.
2. Recheck `isCurrent()`:
   - inside `editQueue.then(...)` before touching `lastSentText`, `draftMessageId`, or REST;
   - after `await draft.seal()`;
   - before every fallback `cleanupAndSend()` / `sendMessage()` / `editMessage()` path.
3. Add tests that model the actual races, not only simplified controller maps:
   - queued edit enqueued while current, then controller replaced before queue runs → no REST call;
   - `deliver()` enters, `draft.seal()` is delayed, controller replaced during seal → no REST call;
   - older handler delayed before controller registration, newer handler starts first → older must not abort newer;
   - `ctx.abortSignal.abort()` aborts all pending dispatches.
4. Make dispatch timeout configurable via `channels.cove.dispatchTimeoutMs` and/or env var, with validation and 120s as the default.
5. Consider aborting on socket close as well as on READY/reconnect, or explicitly document why pending dispatches should continue during the reconnect gap.

## 6. Positive Notes

- The switch from generation counters to `AbortController` reference equality is a solid simplification and fixes the specific `.delete()`/counter reuse bug.
- `createAbortableDispatch()` has focused unit coverage for timeout, normal completion, abort, pre-abort, and dispatch rejection.
- The reconnect event is now typed in `GatewayEvents`, and emitting it only after the first READY avoids false reconnects during initial connect.
- Cleanup comments and logging are clear enough to debug production behavior once the stale side-effect gaps are closed.
