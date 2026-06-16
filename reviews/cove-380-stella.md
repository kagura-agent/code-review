# Review: PR #380 — feat(plugin): batch merge queued messages into single agent turn (#375)

## 1. Summary

This PR changes Cove plugin message processing so that once the current agent turn finishes, all queued messages for that channel are drained and dispatched as one batched turn. Ordering is mostly preserved: queued messages are drained FIFO, the last queued message becomes the primary dispatch, and earlier messages are prepended to `bodyForAgent` as named context.

Overall, the queue mechanics are reasonable and the implementation is small. I do see one important product/data-retention risk: earlier batched messages appear to be included only in the current `BodyForAgent`, while the recorded inbound turn metadata still represents only the primary/last message. That means earlier queued messages may not become durable conversation history as first-class inbound messages.

Rating: ⚠️ Needs Changes

## 2. Critical Issues

### Earlier batched messages may be lost from durable session history

The batch handler creates a synthetic message from the last queued message and attaches previous messages via `_batchedMessages`. `dispatchMessage` then prepends those earlier messages to `bodyForAgent`, but it still sends:

- `rawBody: message.content` from the primary/last message only
- `messageId` from the primary/last message only
- `senderId` / `SenderName` from the primary/last author only
- reply/reference metadata from the primary/last message only

From the OpenClaw direct-DM pipeline, `BodyForAgent` is passed into the agent context for this dispatch, while the envelope/body used for recording is built from `rawBody`. So the agent likely sees the earlier messages for this one response, but those earlier user messages are not recorded as separate inbound turns and may not appear in future conversation history except indirectly through the assistant reply.

Product impact: if users send messages 2, 3, and 4 while the bot is busy, message 2 and 3 are not dropped from the immediate prompt, but they are effectively downgraded from real messages to ephemeral prompt text. Later turns may lack that history, message IDs, timestamps, reply threading, and sender metadata.

Suggested fix: make the recorded inbound body/envelope represent the full batch, not only the primary message, or explicitly record each earlier message as inbound history before dispatching the single agent reply. If preserving one agent turn is the goal, a synthetic batch turn is fine, but its recorded `rawBody`/`Body` should include the same ordered batched context the agent saw.

## 3. Product Impact

- Positive: batching should reduce reply spam and gives the agent a better chance to answer a burst of messages coherently in one turn.
- Risk: users may reasonably expect every sent message to become part of the long-term conversation. In the current implementation, earlier messages in a batch can be absent from durable history and analytics/auditing keyed by message ID.
- Risk: group-chat attribution is partial. Earlier senders are represented in plain text (`Name: content`), but the official turn sender remains the last message author. This is probably acceptable for a single response, but not for durable metadata.
- Risk: attachments from batched messages are collected, but attribution/order is weak. Primary message images are added first, then earlier message images are appended later, which can invert chronological context for image-heavy batches.

## 4. Suggestions

1. **Record the full batch as the inbound body.** Build a single canonical `batchedBodyForAgent` / `batchedRawBody` string and use it consistently for `bodyForAgent` and recorded `rawBody` unless there is a deliberate reason not to.

2. **Preserve per-message metadata in `extraContext`.** Consider adding a structured `BatchedMessages` context with `id`, `timestamp`, `author id/name`, `content`, reply reference, and attachment URLs. This would avoid relying only on lossy plain-text prepending.

3. **Keep attachments inline or chronologically ordered.** Instead of appending all image URLs at the end, format each batched message with its own attachment URLs, e.g. `Alice: text\n[image: ...]`. At minimum, collect earlier-message attachments before primary attachments to match message order.

4. **Avoid `any`/private ad-hoc `_batchedMessages` if possible.** A typed wrapper or explicit `DispatchMessageOptions.batchedMessages?: Message[]` would be clearer and less fragile than mutating message shape through `Object.assign`.

5. **Add queue/batch unit tests.** I did not see dedicated `message-queue` tests. Useful cases:
   - FIFO order preserved in batch
   - messages enqueued during an in-flight dispatch are processed in the next batch
   - no batch handler falls back to sequential dispatch
   - max queue drop behavior remains explicit
   - batched `bodyForAgent` includes all messages and attachments in expected order

## 5. Positive Notes

- The queue drain approach is simple and avoids overlapping dispatches per channel.
- Backward compatibility for callers without `batchDispatchFn` is mostly preserved.
- The last-message-as-primary model is a practical way to keep one reply target while still giving the agent prior queued text.
- The implementation correctly avoids dropping queued messages in the normal batch path; the main concern is durable recording/context fidelity, not immediate prompt visibility.

Verification: fetched PR details/diff with `gh`; ran repository tests with `pnpm test` successfully (306 tests passed).
