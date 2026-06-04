# Code Review: PR #190 (cove) - Round 5

## 1. Summary
The shift to `AbortController` reference equality in `pendingDispatches` completely solves the Generation ID race conditions and memory leaks. The fundamental architecture for cancellation is now sound. However, three of the issues raised in R4 remain unresolved, including the queued side-effect race which can still leak stale messages. 

## 2. Previous Issues Status
1. 🟢 **Generation ID reuse via .delete()** — **FIXED**. Replaced by robust `AbortController` reference equality check (`isCurrent()`).
2. 🟢 **Reconnect leaks channelGeneration entries** — **FIXED**. Handled correctly with `pendingDispatches.clear()` and safe `finally` block cleanup.
3. 🔴 **Queued side-effect race** — **UNRESOLVED**. (See Critical Issues).
4. 🟡 **Configurable timeout** — **UNRESOLVED**. Timeout is still hardcoded to `const DISPATCH_TIMEOUT_MS = 120_000`.
5. 🟡 **Plugin shutdown should abort pending dispatches** — **UNRESOLVED**. No plugin teardown/destroy listener clears pending dispatches.

## 3. Critical Issues
**Queued Side-Effect Race condition still exists**
In `sendOrEdit`, the `isCurrent()` check runs synchronously *before* the operation enters the `editQueue`:
```typescript
const sendOrEdit = async (text: string): Promise<boolean> => {
  if (!isCurrent()) return false;
  return new Promise<boolean>((resolve) => {
    editQueue = editQueue.then(async () => {
      // isCurrent() is NOT checked here!
      if (draftState.stopped && !draftState.final) { resolve(false); return; }
      // REST calls happen here...
```
If a new dispatch starts while an old dispatch's edit is waiting in `editQueue`, the old edit will still execute because it passed the `isCurrent()` check before queuing.

**Fix:** Move the `isCurrent()` check *inside* the `editQueue.then()` block (or add a second check there) so it evaluates right before the network request fires.

## 4. Product Impact
If a user rapidly sends messages (or reconnect happens during active streaming), edits already queued by the previous dispatch will flush to the channel, potentially corrupting the draft or interleaving with the new dispatch.

## 5. Suggestions
- **Side-effect queue:** Add `if (!isCurrent()) { resolve(false); return; }` inside the `editQueue.then(async () => { ... })` block in `sendOrEdit`.
- **Configurable timeout:** Pass `dispatchTimeout` via plugin configuration (`cfg.dispatchTimeout` or similar) rather than relying on a top-level `120_000` constant.
- **Teardown:** If the plugin framework exposes an `onStop` or `onDestroy` hook, ensure you abort all `pendingDispatches` there just as you do for `reconnect`.

## 6. Positive Notes
The new `createAbortableDispatch` abstraction and the unit tests you added in `dispatch-resilience.test.ts` are excellent. They cover the exact edge cases we care about (reconnects, new messages). The `finally` cleanup logic is also bulletproof now.

**Rating:** ⚠️ Needs Changes
