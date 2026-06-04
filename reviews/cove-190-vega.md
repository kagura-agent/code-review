# Code Review: PR #190 (kagura-agent/cove)

**Reviewer:** 💫 Vega  
**Target:** PR #190 - fix: plugin dispatch resilience — timeout, reconnect abort, per-channel tracking

### 1. Summary
This PR successfully implements resilience mechanisms to prevent the Cove plugin from permanently halting message processing on individual channels. By introducing an abortable wrapper, tracking in-flight dispatches by channel ID, and properly flushing state on gateway reconnects, the plugin can now recover gracefully from hanging dispatches caused by server restarts or network instability.

### 2. Critical Issues
*None.* The logic correctly unblocks the event loop and channel processing queue.

### 3. Product Impact
**High Positive Impact.** Resolves the known "stuck channel" bug, dramatically improving the bot's reliability during connection drops and rapid restarts without requiring manual intervention.

### 4. Suggestions
- **Signal Propagation to SDK (Minor/Future):** `abortController.signal` is used to cancel the local wrapper promise, but it is not passed into the `dispatchInboundDirectDmWithRuntime` arguments. This means the underlying SDK task might continue running in the background. If the `openclaw/plugin-sdk` supports an `AbortSignal` parameter (or if added in the future), you should pass `signal: abortController.signal` directly to it so the actual API/network calls can be cancelled, rather than just abandoning the promise.
- **Listener Cleanup (Nitpick):** In `createAbortableDispatch`, if the dispatch times out, the `onAbort` listener remains attached to the `signal` because `settle()` prevents the later resolution from running `removeEventListener`. Since the `AbortController` is scoped to the message and quickly garbage collected, this will not cause a memory leak, but ensuring listeners are removed in *all* resolution paths is a slightly safer pattern long-term.

### 5. Positive Notes
- **Excellent Test Coverage:** The suite covering `createAbortableDispatch` correctly validates all edge cases (timeout, normal resolution, pre-aborted, abort mid-flight, and error propagation).
- **Concurrency Control:** Replacing the existing `AbortController` when a new message arrives on the same channel is an elegant way to prevent stale inputs from holding up the queue.
- **Clean Event Design:** Emitting the `reconnect` event on subsequent `ready` payloads is a simple and reliable way to signal the plugin to flush stale state.

### Rating
✅ **Ready** (Approving)