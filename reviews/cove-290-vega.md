# Code Review: PR #290 (kagura-agent/cove)
**Reviewer:** 💫 Vega
**Verdict:** Needs Changes ❌

## Summary
The PR sets out to remove the 120s dispatch timeout while keeping the abort-on-superseding-message logic. While the timeout is successfully removed, the abort functionality is completely broken due to a classic AI-generated code failure mode: **plausible-but-wrong logic** and **dead code**. 

## Findings

### 1. Plausible-but-wrong Logic (Broken Abort)
By removing `createAbortableDispatch`, the code now directly awaits `dispatchInboundDirectDmWithRuntime(...)`. 
```typescript
    } catch (err: any) {
      if (abortController.signal.aborted) {
        typingCallbacks.onCleanup?.();
        log?.info?.(`cove: dispatch aborted in [${channelId}]`);
```
This `catch` block looks correct at a glance, but **it will never be reached during an abort**. `dispatchInboundDirectDmWithRuntime` does not accept an `AbortSignal`, so it does not know it was aborted. It will simply finish its work and resolve successfully. The `catch` block will only execute if the agent runtime naturally throws an independent error. 

### 2. Leaked Typing Keepalives & Resources
Because the `catch` block is bypassed when a superseding message arrives:
- `typingCallbacks.onCleanup?.()` is never called for the superseded message.
- The `keepaliveIntervalMs` typing indicator loop will keep firing uselessly in the background until its 60-second `maxDurationMs` expires.
- The outer `dispatchMessage` promise chain will block unnecessarily until the orphaned background task finishes.

## Recommendation

Do not completely remove `createAbortableDispatch`. Instead, remove the `setTimeout` / timeout logic from it, but **keep the `AbortSignal` listener**. This allows the wrapper to detach the promise chain and throw `DispatchAbortedError` when `abortController.abort()` is called.

**Suggested Fix:**
Restore `createAbortableDispatch` and `DispatchAbortedError`, but refactor it to only handle the signal:

```typescript
export class DispatchAbortedError extends Error {
  constructor() { super("dispatch aborted"); this.name = "DispatchAbortedError"; }
}

export function createAbortableDispatch(
  dispatch: Promise<unknown>,
  signal: AbortSignal,
): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    if (signal.aborted) {
      dispatch.catch(() => {}); // Prevent unhandled rejection
      return reject(new DispatchAbortedError());
    }

    const onAbort = () => {
      dispatch.catch(() => {});
      reject(new DispatchAbortedError());
    };
    signal.addEventListener("abort", onAbort, { once: true });

    dispatch.then(
      () => { signal.removeEventListener("abort", onAbort); resolve(); },
      (err) => { signal.removeEventListener("abort", onAbort); reject(err); },
    );
  });
}
```

Then, revert the `await dispatchInboundDirectDmWithRuntime` call to use this updated wrapper:
```typescript
await createAbortableDispatch(
  dispatchInboundDirectDmWithRuntime({ ... }),
  abortController.signal
);
```

This restores the abort hook, ensures the catch block is reached, and properly cleans up typing indicators on superseding messages.