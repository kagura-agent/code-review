# PR #190 Review — Stella

## Summary
This PR adds a dispatch timeout wrapper, a gateway `reconnect` event, and per-channel tracking so newer messages/reconnects can abort pending plugin dispatches. The direction is right and the new helper is unit-tested, with `pnpm --filter openclaw-cove test` and `pnpm --filter openclaw-cove check` passing locally. However, the current abort/timeout only stops waiting for the promise; it does not cancel or gate the underlying dispatch side effects, so stale dispatches can still send/edit Cove messages after being considered aborted. **Rate: ⚠️ Needs Changes**

## Critical Issues
1. **Abort/timeout does not actually cancel dispatch side effects** — `packages/plugin/src/channel.ts:25-57`, `packages/plugin/src/channel.ts:417-455`, `packages/plugin/src/channel.ts:326-349`
   - `createAbortableDispatch` races the dispatch promise against timeout/abort, but `dispatchInboundDirectDmWithRuntime` receives no abort signal and the reply `deliver` path has no `signal.aborted` / generation-token guard.
   - After a duplicate message, reconnect, or 120s timeout, the wrapper rejects/logs and removes tracking, but the original agent run can continue and later call the same `deliver` callback to edit/send a stale final response.
   - This defeats the main product goal of “cancel on reconnect or duplicate” and can create out-of-order replies, duplicate replies, or old-run edits after a newer message has taken over the channel.
   - Suggested fix: either plumb real cancellation into the OpenClaw dispatch/runtime if supported, or add a per-channel generation token / controller guard in every side-effect path (`onPartialReply`, tool progress updates, `deliver`, draft send/edit/delete) so aborted/stale dispatches cannot mutate Cove state. Keep the pending entry until the underlying dispatch finishes or is truly cancelled.

2. **Tests validate the helper race, not the plugin behavior that can regress** — `packages/plugin/src/dispatch-resilience.test.ts:53-102`
   - The reconnect and same-channel tests simulate a local `Map` and controllers, but they do not exercise `messageCreate`, `pendingDispatches`, the `reconnect` event handler, or the Cove side-effect callbacks.
   - Because of that, the current tests pass even though an aborted dispatch can still deliver a stale response later.
   - Add an integration-style test with a controllable fake dispatch/deliver: start dispatch A, abort it via same-channel message or reconnect, then resolve/fire A’s deliver callback and assert no REST send/edit/delete occurs; then assert dispatch B can still deliver normally.

## Product Impact
- The intended user-facing improvement is strong: Cove should recover from stuck plugin dispatches and avoid one channel blocking itself forever.
- As implemented, users can still see replies from superseded/stale turns after reconnects or after sending a newer message. That is especially confusing in a chat product because the bot may answer an old prompt after the conversation moved on.
- Timeout behavior is also misleading: after “timed out,” the agent run may still be active and later mutate the channel, while the plugin no longer tracks it.

## Suggestions
- Consider making `DISPATCH_TIMEOUT_MS` configurable per account/channel instead of hardcoding 120s in `packages/plugin/src/channel.ts:16`; some agent/tool runs may legitimately exceed two minutes.
- Clean up listener/timer state on the timeout path in `createAbortableDispatch` (`packages/plugin/src/channel.ts:36-55`). The timeout callback settles without removing the abort listener; if the underlying dispatch never resolves, the signal/listener closure can remain reachable longer than necessary.
- Add a focused `CoveGatewayClient` test for `reconnect` emission on second READY (`packages/plugin/src/gateway-client.ts:119-132`) so this event contract is protected directly.

## Positive Notes
- Per-channel tracking is the right granularity for Cove’s channel-to-session model.
- The controller identity check before deleting from `pendingDispatches` (`packages/plugin/src/channel.ts:464-468`) is a good guard against an old dispatch clearing a newer controller.
- Build/typecheck and plugin tests pass locally:
  - `pnpm --filter openclaw-cove test` — 38 passed
  - `pnpm --filter openclaw-cove check` — passed
