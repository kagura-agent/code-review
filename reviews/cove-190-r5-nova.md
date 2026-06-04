# 🌠 Nova — Re-review (R5) — cove#190

**PR**: kagura-agent/cove#190 — plugin dispatch resilience
**Round**: 5
**Verdict**: ⚠️ **Needs Changes** (one critical fixed, several yellows still open)

---

## 1. Summary

Big positive: R4's 🔴 generation-ID-reuse bug is **fixed properly** by switching from a separate `channelGeneration: Map<string, number>` counter to **AbortController reference equality** (`pendingDispatches.get(channelId) === abortController`). This is exactly the design Vega proposed — the staleness check now keys off an object identity that cannot collide, eliminating the reuse window entirely. Cleanup is also race-safe: the old dispatch's `finally` only deletes the map entry when its controller is still the one stored, so a fast replace-then-finish sequence cannot accidentally evict the new controller.

However, three R4 yellows are still untouched, and the queued side-effect race that was flagged in R4 is only *partially* mitigated. The PR is materially better than R4 but not yet "ready".

---

## 2. Previous Issues — Status

| # | R4 Issue | R5 Status | Notes |
|---|---|---|---|
| 1 | 🔴 Generation ID reuse via `.delete()` | ✅ **Fixed** | Counter removed; identity check via AbortController instance. Vega's recommendation applied correctly. |
| 2 | 🟡 Reconnect leaks `channelGeneration` entries | ✅ **N/A → Fixed** | The map is gone; `pendingDispatches.clear()` in the reconnect handler does the right thing now. |
| 3 | 🟡 Queued side-effect race | ⚠️ **Partially addressed** | `isCurrent()` is checked at `sendOrEdit` *entry*, but **not** re-checked inside the `editQueue.then(async () => { ... restClient.editMessage/sendMessage ... })` body. A dispatch can pass the entry check, be enqueued, then have the abort fire while waiting in the queue — the REST call still goes out, and worse, it may edit a `draftMessageId` that belongs to a stale draft (or send a fresh message on a channel that has already moved on). See Critical Issues #1. |
| 4 | 🟡 Configurable timeout | ❌ **Not addressed** | Still `const DISPATCH_TIMEOUT_MS = 120_000;` hardcoded at module top. No config plumbing. |
| 5 | 🟡 Plugin shutdown should abort pending dispatches | ❌ **Not addressed** | `ctx.abortSignal` handler calls `gatewayClient.destroy()` only; `pendingDispatches` is left intact. On plugin teardown, in-flight dispatches keep running with no chance to flush gracefully or release the wrapper promises. |

**Escalation note**: per the re-review rules, unaddressed yellows do not downgrade. #3, #4, #5 remain 🟡.

---

## 3. Critical Issues

### 🟡 C1 — `editQueue` body skips the freshness check
**Where**: `packages/plugin/src/channel.ts` ~lines 280–303

```ts
const sendOrEdit = async (text: string): Promise<boolean> => {
  if (!isCurrent()) return false;          // ← only check
  return new Promise<boolean>((resolve) => {
    editQueue = editQueue.then(async () => {
      if (draftState.stopped && !draftState.final) { resolve(false); return; }
      // ❌ no isCurrent() re-check here
      ...
      await restClient.editMessage(channelId, draftMessageId, trimmed);
      // or restClient.sendMessage(channelId, trimmed);
```

Sequence that leaks:
1. Dispatch A: callback fires → `sendOrEdit("...")` → `isCurrent()` = true → task enqueued behind a slow previous edit.
2. New message arrives → handler aborts A and installs Dispatch B's controller in the map.
3. The queued task from A wakes up → no freshness check → executes `restClient.sendMessage` or `editMessage`. If A had not yet created a draft, this **creates a new bot message in the channel after A was supposed to be silent**. If A had a draft, it edits stale content.

Fix: add `if (!isCurrent()) { resolve(false); return; }` inside the `editQueue.then` body, just below the `draftState.stopped` guard.

### 🟡 C2 — `deliver` race between `isCurrent()` and `draft.seal()`
**Where**: ~lines 343–362

```ts
deliver: async (payload, _info) => {
  if (!isCurrent()) return;
  typingCallbacks.onCleanup?.();
  ...
  draftState.final = true;
  await draft.seal();          // awaited — abort can happen here
  if (draftMessageId && !draftState.stopped) {
    await restClient.editMessage(channelId, draftMessageId, text);
  } else {
    await cleanupAndSend(restClient, channelId, draftMessageId, text, log);
  }
```

Same shape as C1: the `isCurrent()` gate is passed once, then the function `await`s. If abort fires during the `await draft.seal()` (or even during the subsequent `editMessage`/`cleanupAndSend`), the final reply is still sent on behalf of a stale dispatch. Recommend re-checking `isCurrent()` after the `await draft.seal()` (and before each subsequent REST call), or — cleaner — wrap the entire `deliver` body with a single check + an abort-aware abortable REST helper.

### 🟡 C3 — Plugin shutdown leaves dispatches dangling
**Where**: ~line 514

```ts
ctx.abortSignal.addEventListener("abort", () => {
  gatewayClient.destroy();
});
```

`pendingDispatches` is not iterated/aborted here. Result:
- Wrapper promises (`createAbortableDispatch`) never reject, so any awaiter (none today, but easy regression) hangs.
- Underlying dispatches keep streaming into LLM/runtime with their side-effect guards still pointing at a torn-down channel.
- The `Map` is never cleared, so we hold the AbortController GC roots until the surrounding closure dies.

Fix is one block:
```ts
ctx.abortSignal.addEventListener("abort", () => {
  for (const c of pendingDispatches.values()) c.abort();
  pendingDispatches.clear();
  gatewayClient.destroy();
});
```

### 🟡 C4 — Timeout still hardcoded
R4 #4 explicitly asked for this to be configurable; nothing changed in R5. Suggest `cfg?.channels?.cove?.dispatchTimeoutMs ?? 120_000`, read once per `startAccount` invocation. Low-risk one-liner, but ignoring repeated feedback is a smell.

---

## 4. Product Impact

- **C1 / C2** are the highest-impact bugs in this round. They are the *exact* class of "ghost message" that #180 was filed to prevent: a stale dispatch sneaks a REST write into a channel after a newer message has taken over. The visible symptom would be a Cove channel receiving an out-of-order/duplicate reply, or a draft from message *N* getting edited into message *N+1*'s response. Worse, because the dispatch is now technically "released" (timeout/abort fires the wrapper), there is no log line tying the orphan REST back to the original message — making it hard to diagnose in prod.
- **C3** is a graceful-shutdown issue. Low frequency, but during plugin reloads or process exits a few in-flight conversations can produce stray messages or wedged promises.
- **C4** is debt; not a bug.

Net: the main user-visible bug from #180 (stuck channels) is solved. The new bug surface introduced by the resilience layer (ghost writes) is narrowed by R5 but **not closed**.

---

## 5. Suggestions

1. **(must)** Add an `isCurrent()` re-check inside the `editQueue.then` body (C1).
2. **(must)** Re-check `isCurrent()` after every `await` inside the `deliver` callback before any REST write (C2). A small helper like `const guarded = async (fn) => { if (!isCurrent()) return; await fn(); }` would centralize this and prevent regression.
3. **(should)** Abort `pendingDispatches` in the shutdown handler (C3).
4. **(should)** Make `DISPATCH_TIMEOUT_MS` configurable via channel config (C4).
5. **(nice)** Add a test that exercises C1: simulate `sendOrEdit` enqueued behind a slow edit, abort the controller, assert the REST client is not called for the stale dispatch. The current "same-channel cancellation" test only checks Map bookkeeping, not the queued-side-effect window.
6. **(nice)** Consider passing `abortController.signal` into `restClient.editMessage/sendMessage` so aborts terminate in-flight HTTP too, not just future ones. This would also start closing C2 properly instead of relying on post-await guards.
7. **(nice)** When a stuck dispatch times out, the underlying runtime keeps running forever consuming tokens. Worth filing a follow-up to thread the abort signal into `dispatchInboundDirectDmWithRuntime` itself when that helper supports it; today the timeout is purely cosmetic for the runtime.

---

## 6. Positive Notes

- The **AbortController-identity** design is clean, race-free for the bookkeeping, and removes a whole category of off-by-one/reset bugs that R4 had. Solid response to Vega's suggestion.
- The `finally` block's `pendingDispatches.get(channelId) === abortController` check is *exactly* the right pattern and is the subtle thing that makes the design correct under fast replace-then-finish ordering.
- `createAbortableDispatch` is well-isolated, easy to test, properly removes its `abort` listener on completion, and prevents unhandled-rejection on a pre-aborted signal — small but important details.
- The `hasConnectedOnce` gate on `reconnect` emission avoids spurious reconnect-on-first-ready, and the reconnect handler logs the count being aborted — good operability.
- The docstring on `createAbortableDispatch` honestly calls out that this is "release-only, not cancellation" and explains how reference equality compensates. Future maintainers will thank R5 for this comment.
- Tests cover the new wrapper's happy path, timeout, abort-then, pre-aborted, and dispatch-fails cases. Coverage of the *plugin handler* logic is still thin (the "same-channel" test simulates the Map directly), but the wrapper itself is well-tested.

---

**Final rating: ⚠️ Needs Changes** — land the queue/deliver freshness re-checks (C1, C2) and the shutdown abort (C3) before merge. C4 can ship as a follow-up if there's time pressure, but ignoring it again would be the third round with the same yellow.
