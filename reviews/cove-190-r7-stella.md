# 🌟 Stella Review — PR #190 Round 7

## 1. Summary

R7 addresses the three R6 consensus carry-overs. The per-channel `AbortController` is now registered in the synchronous `messageCreate` prologue before any `await`, plugin shutdown aborts and clears all pending controllers, and the timeout is now read from `channels.cove.dispatchTimeoutMs` with a 120s default. I re-read the updated diff and the relevant `channel.ts` / `gateway-client.ts` context with fresh eyes.

**Rating: ✅ Ready**

Local verification:
- `pnpm -F openclaw-cove test -- src/dispatch-resilience.test.ts` → passed: 3 plugin test files, 38 tests
- `pnpm -F openclaw-cove check` → passed

## 2. Previous Issues Status

1. 🔴 **Async handler ordering race — fixed**
   - Evidence: controller ownership is established immediately after `channelId` extraction and logging, before typing setup, dynamic import, `loadDirectDm()`, draft setup, and the `setTimeout(1)` yield (`packages/plugin/src/channel.ts:236-244`).
   - The previous failure mode where an older handler resumed after a newer one and replaced the newer controller is closed: arrival order now controls `pendingDispatches`, not async resume order.

2. 🔴 **Plugin shutdown does not abort pending dispatches — fixed**
   - Evidence: the `ctx.abortSignal` listener now iterates `pendingDispatches.values()`, aborts each controller, clears the map, then calls `gatewayClient.destroy()` (`packages/plugin/src/channel.ts:523-527`).
   - This mirrors the reconnect behavior closely enough for shutdown/reload safety.

3. 🟡 **Configurable timeout — fixed**
   - Evidence: `DEFAULT_DISPATCH_TIMEOUT_MS` remains the default, but per-channel config can override it via `channels.cove.dispatchTimeoutMs` (`packages/plugin/src/channel.ts:16`, `packages/plugin/src/channel.ts:274-275`).
   - This satisfies the R6 request for a configurable dispatch timeout.

## 3. Critical Issues

None blocking in this round.

I specifically re-checked the prior race surfaces:
- Same-channel supersession now aborts the previous controller synchronously before any awaited setup work.
- Reconnect and shutdown both clear `pendingDispatches`, making `isCurrent()` false for stale callbacks.
- Callback guards still cover partial replies, tool/progress events, compaction events, assistant-start events, and final delivery.
- The queued edit path still re-checks `isCurrent()` inside the serialized queue before REST writes.

## 4. Product Impact

- The original product problem — stuck or stale dispatches after gateway reconnects / duplicate channel traffic — is materially improved.
- Newer user messages in the same Cove channel now reliably supersede older in-flight dispatches instead of depending on handler resume timing.
- Plugin shutdown/reload no longer leaves pending wrapper promises alive until natural completion or timeout.
- Operators can tune timeout behavior for Cove deployments without code changes.

## 5. Suggestions

Non-blocking polish I would consider after merge:

1. **Validate `dispatchTimeoutMs`.** Guard against non-number, `NaN`, zero, negative, or extremely low values. A small resolver like `resolveDispatchTimeoutMs(channelEntry)` would make this safer and easier to test.
2. **Document the new config knob.** Add `dispatchTimeoutMs: 120000` to `packages/plugin/README.md` so operators can discover it.
3. **Clean up pending ownership on pre-dispatch setup errors.** Because the controller is now installed before `loadDirectDm()` and setup work, an exception before the inner `createAbortableDispatch(...)` `finally` would leave a stale entry in `pendingDispatches` until the next message/reconnect/shutdown. This is not a blocker because the next same-channel message overwrites it, but a wider `try/finally` around all post-registration setup would be cleaner.
4. **Keep hardening final fallback ownership checks.** The current final-delivery path checks `isCurrent()` after `draft.seal()`. For maximum defense, re-check before any fallback `cleanupAndSend()` after an awaited `editMessage()` failure, and/or pass an ownership predicate into `cleanupAndSend()`.
5. **Add integration-level handler tests.** The current resilience tests validate `createAbortableDispatch` and simulated controller behavior. A test that emits two `messageCreate` events with controlled `loadDirectDm()` delay would lock in the R7 ordering fix.

## 6. Positive Notes

- The synchronous controller-registration move is the right fix for the R6 race; it addresses the root cause instead of adding another late guard.
- AbortController reference equality remains a clean, low-leak identity model for per-channel ownership.
- Reconnect and shutdown cleanup are now symmetrical in intent.
- Custom `DispatchTimeoutError` / `DispatchAbortedError` classes keep timeout/abort handling robust compared with string matching.
- The local plugin test suite and TypeScript check both pass.
