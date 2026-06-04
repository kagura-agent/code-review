# Cove PR #190 Code Review — Round 4 (Vega)

## 1. Summary
The resilience additions—dispatch timeouts, reconnect cancellation, and per-channel state tracking—are structurally sound and target the root cause of stalled dispatches gracefully. The core logic of isolating runaway dispatches with `createAbortableDispatch` is solid. However, the mechanism used to protect against stale callbacks (`channelGeneration` combined with `.delete()`) introduces a critical ID reuse vulnerability that needs fixing.

## 2. Previous Issues Status
- ✅ **UnhandledPromiseRejection (Pre-aborted):** Fixed. `dispatch.catch(() => {})` is now cleanly attached when returning early on a pre-aborted signal.
- ✅ **Incomplete callback guards:** Fixed. All callbacks (onToolStart, onCompactionStart, etc.) now properly evaluate `isCurrent()`.
- ⚠️ **channelGeneration map never cleaned:** Addressed in the `finally` block via `.delete(channelId)`, but this deletion introduces a fatal logic flaw (see Critical Issues).

## 3. Critical Issues
### 🔴 Generation ID Reuse via Deletion (Critical Bug)
In the `finally` block, `channelGeneration.delete(channelId)` is executed if the dispatch completes or times out without being replaced. This breaks the monotonicity of the generation counter, effectively resetting it to 0 for the next message and allowing stale dispatches to resurrect their permissions. 

**Trace:**
1. **Dispatch A** starts. `channelGeneration` gets set to `1`.
2. **Dispatch A** hits the 120s timeout. `createAbortableDispatch` throws.
3. The `catch` block safely increments generation to `2` to orphan the running promise.
4. The `finally` block immediately calls `channelGeneration.delete(channelId)`.
5. The user sends a new message (**Dispatch B**). Because the map is empty, `gen` is calculated as `(undefined ?? 0) + 1 = 1`.
6. **Dispatch A** (which is still running in the background) wakes up and fires `onPartialReply`.
7. **Dispatch A**'s closure checks `channelGeneration.get(channelId) === 1`. Since Dispatch B just set it to `1`, the check passes (`TRUE`)!
8. **Dispatch A**'s output leaks directly into **Dispatch B**'s stream.

## 4. Product Impact
If a dispatch times out, the very next message sent by the user will share a generation ID with the orphaned dispatch, causing their UI streams and draft states to become intermingled. 

## 5. Suggestions

### 💡 The Refactor: Use AbortController for Identity (Removes channelGeneration map)
Since `abortController` is already a unique object reference per dispatch, you don't need a numerical generation map at all. Object equality guarantees IDs are never reused, and it naturally mirrors the lifecycle of `pendingDispatches`.

You can delete `channelGeneration` entirely and just do:
```typescript
const abortController = new AbortController();
pendingDispatches.set(channelId, abortController);

/** Returns true if this dispatch is still the active one for this channel. */
const isCurrent = () => pendingDispatches.get(channelId) === abortController;
```
**Why this works in all scenarios:**
- **Completion/Timeout:** `finally` removes the controller from `pendingDispatches`. `isCurrent()` evaluates `undefined === abortController` (false).
- **New Message:** Replaces the controller in `pendingDispatches`. The old dispatch evaluates `newController === oldController` (false).
- **Reconnect:** Clears `pendingDispatches`. Old dispatch evaluates `undefined === oldController` (false).

## 6. Positive Notes
- `createAbortableDispatch` is an excellent pattern for safely wrapping untrusted/stalling promises.
- `hasConnectedOnce` correctly ensures `reconnect` doesn't fire on the very first boot.
- The Vitest tests for the abort behavior comprehensively prove the wrapper logic.

## Rating
⚠️ **Needs Changes** (Escalated: Generation ID reuse bug needs fixing. Highly recommend the `AbortController` reference equality fix above to solve both the bug and simplify the code).
