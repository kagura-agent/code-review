# Review: kagura-agent/cove PR #367 — Stella

## Summary
This PR replaces per-channel “new message aborts old dispatch” behavior with a small FIFO queue, which directly addresses the lost-reply workflow problem and keeps processing isolated per channel. The implementation is simple and type-checks; plugin tests also pass locally (`pnpm -F openclaw-cove check`, `pnpm -F openclaw-cove test`). I don’t see a blocking functional or security issue in the diff, but the new queue behavior is currently untested, and one existing test still documents the old supersede/abort behavior, so coverage should be tightened before relying on this in production.

## Critical Issues
None found.

## Product Impact
- `packages/plugin/src/channel.ts:345-356` changes user-visible behavior: messages sent while the bot is busy are no longer discarded/aborted, but processed later in FIFO order. This should improve bursty issue-notification handling.
- `packages/plugin/src/message-queue.ts:40-47` caps pending messages at 5 per channel and drops the oldest queued message when full. That is a reasonable safety bound, but users in very active channels may see older messages silently skipped except for server logs.
- `packages/plugin/src/channel.ts:259-266` clears queued messages on hard reconnect, so any messages received before reconnect but not yet dispatched can be lost. This matches the PR description, but it is worth making sure that tradeoff is acceptable.

## Suggestions
- Add focused tests for `ChannelMessageQueue` in `packages/plugin/src/message-queue.ts`: FIFO ordering, one in-flight dispatch per channel, independent channels processing concurrently, queue overflow dropping the oldest queued message, and `clearAll()` behavior.
- Update or remove the stale test in `packages/plugin/src/dispatch-resilience.test.ts:25-48`; it still describes “new message to same channel cancels old dispatch,” which is now intentionally false and could mislead future maintainers even though it is only testing an inline simulation.
- Consider making the overflow log in `packages/plugin/src/message-queue.ts:43` include the current/new message id as well as the dropped id, to make burst-loss debugging easier.
- In `packages/plugin/src/message-queue.ts:67-68`, use a safer error formatter (`err instanceof Error ? err.message : String(err)`) so unusual thrown values do not break the queue’s error path.

## Positive Notes
- The queue is per-channel, so long processing in one channel does not block other channels (`packages/plugin/src/message-queue.ts:22-23`).
- The implementation keeps reconnect/shutdown cleanup explicit in `packages/plugin/src/channel.ts:259-266` and `packages/plugin/src/channel.ts:378-383`.
- The bounded queue prevents unbounded memory growth during bursts, which is the right default for a chat plugin.

## Rating
✅ Ready
