# PR #190 (Round 3) Code Review by Vega

## 1. Summary
The resilience mechanism has been improved by correctly incrementing the generation counter on timeouts and reconnects, which prevents the most critical form of stale state leakage. However, several previously identified issues remain entirely unaddressed. Following the Escalation Rule, these unaddressed issues must now block the PR.

## 2. Previous Issues Status
1. 🔴 **Generation not incremented on timeout/reconnect**: ✅ Fixed.
2. 🟡 **Configurable DISPATCH_TIMEOUT_MS**: ❌ Unaddressed (still hardcoded to `120_000`).
3. 🟡 **channelGeneration map never cleaned up**: ❌ Unaddressed (memory leak over time for ephemeral channels).
4. 🟡 **UnhandledPromiseRejection risk**: ❌ Unaddressed.
5. 🟡 **Not all dispatcher callbacks guarded**: ❌ Unaddressed (only `deliver` and `onPartialReply` are guarded).

## 3. Critical Issues (Escalated)
* **UnhandledPromiseRejection (Escalated from R2)**: In `createAbortableDispatch`, if `signal.aborted` is true when called, you `return` early and skip `dispatch.then(...)`. If the `dispatch` promise later rejects, Node.js will trigger an UnhandledPromiseRejection, crashing the process. You must always attach a `.catch` to `dispatch`, even if returning early.
  * *Fix*: Do not skip attaching to `dispatch`. Attach `.then`/`.catch` before evaluating the early return, or attach a dummy sink `.catch(() => {})` if returning early.
* **Unguarded Callbacks (Escalated from R2)**: Callbacks like `onToolStart`, `onToolProgress`, `onToolEnd`, and `onCompactionStart` in `dispatcherOptions` do not check the generation counter. A stale dispatch can still pollute the `toolProgress` tracker or emit unwanted side effects.
  * *Fix*: Apply `if (channelGeneration.get(channelId) !== gen) return;` to all callbacks.
* **channelGeneration Memory Leak (Escalated from R2)**: Entries are added to `channelGeneration` but never deleted. For a long-running server processing many unique/ephemeral channel IDs, this map grows indefinitely.
  * *Fix*: Clean up the generation key when it's no longer needed, or use an LRU Cache. Since generation is meant to block delayed callbacks, you might keep it for a grace period, or clear it if `pendingDispatches` for that channel is empty after a delay.

## 4. Product Impact
If merged as-is, the Node.js process could crash if a pre-aborted signal coincides with a failing dispatch. Memory will slowly leak for every unique channel ID that ever receives a message. Tool execution logs from stale dispatches will occasionally bleed into current runs.

## 5. Suggestions
* Update `createAbortableDispatch` to safely sink the promise:
  ```typescript
    dispatch.then(
      () => settle(() => { clearTimeout(timer); signal.removeEventListener("abort", onAbort); resolve(); }),
      (err) => settle(() => { clearTimeout(timer); signal.removeEventListener("abort", onAbort); reject(err); }),
    );

    if (signal.aborted) {
      clearTimeout(timer);
      reject(new DispatchAbortedError());
      return;
    }
    // (This guarantees `dispatch` is always handled).
  ```
* Make `DISPATCH_TIMEOUT_MS` configurable via `cfg` or environment.

## 6. Positive Notes
The timeout and reconnect handlers are now properly coordinated with the generation system. The race condition that allowed stale dispatch messages has been plugged for the `deliver` and `onPartialReply` events, and the logic cleanly increments generations when dropping bad states.

## Rate
❌ Major Issues