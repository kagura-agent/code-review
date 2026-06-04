# Summary
This PR adds dispatch resilience through timeouts, WS reconnect cancellation, and per-channel concurrency control to fix the issue where the Cove plugin gets stuck on individual channels. The side-effect queue race condition has been correctly addressed in this round. However, the other three issues raised in the previous round remain unresolved.

# Previous Issues Status
- ✅ **Queued side-effect race:** FIXED. The `isCurrent()` check was correctly added inside the `editQueue.then()` callback and right after `await draft.seal()` in the `deliver` callback.
- ❌ **Async handler ordering race:** UNRESOLVED. The `abortController` setup is still located *after* `await loadDirectDm()` and `await new Promise(...)`. This means older messages that take longer to resolve their promises can still overwrite and cancel newer messages.
- ❌ **Plugin shutdown doesn't abort pending dispatches:** UNRESOLVED. `ctx.abortSignal.addEventListener("abort")` only destroys the gateway client. It does not iterate over `pendingDispatches` to abort them, which could cause phantom REST API messages after the plugin shuts down.
- ❌ **Configurable timeout:** UNRESOLVED. `DISPATCH_TIMEOUT_MS` is still a hardcoded `120_000` at the top of the file instead of reading from configuration.

# Critical Issues
1. **Async Ordering Race:** The concurrency control is compromised if an older event resumes from `await loadDirectDm()` later than a newer event. The older event will see the newer event's dispatch as "existing", abort it, and install itself. **Fix:** Move `const abortController = new AbortController(); pendingDispatches.set(channelId, abortController);` completely synchronously to the top of the `gatewayClient.on("messageCreate")` handler, before *any* `await` statements.
2. **Missing Shutdown Cancellation:** When `ctx.abortSignal` fires, in-flight dispatches will keep running in the background and might issue REST API requests even though the plugin is considered stopped. **Fix:** Add a loop in the plugin shutdown handler to abort all controllers in `pendingDispatches.values()`.

# Product Impact
Without fixing the ordering race, users who send messages rapidly could see their latest message cancelled by a delayed older message. If the plugin is reloaded or gracefully restarted, the old dispatches will continue running concurrently with the new plugin instance, causing double-replies or ghost edits.

# Suggestions
1. **Move AbortController initialization:**
```typescript
gatewayClient.on("messageCreate", async (message) => {
  if (message.author.bot) return;
  const channelId = message.channel_id;

  // Do this BEFORE any await!
  const existing = pendingDispatches.get(channelId);
  if (existing) existing.abort();
  const abortController = new AbortController();
  pendingDispatches.set(channelId, abortController);
  // ... rest of the handler
```
2. **Clean up on shutdown:**
```typescript
ctx.abortSignal.addEventListener("abort", () => {
  for (const controller of pendingDispatches.values()) {
    controller.abort();
  }
  pendingDispatches.clear();
  gatewayClient.destroy();
});
```
3. **Make timeout configurable:**
Read from `cfg`:
```typescript
const channelEntry = cfg?.channels?.["cove"] ?? {};
const timeoutMs = channelEntry.dispatchTimeoutMs ?? 120_000;
// Use timeoutMs in createAbortableDispatch
```

# Positive Notes
The `isCurrent()` protection added into the asynchronous callbacks (`sendOrEdit` queue and `deliver` post-seal check) is robust and correctly prevents side-effect leakage. The tests cover the abort state machine cleanly.

**Rate:** ❌ Major Issues
