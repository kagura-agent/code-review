# Review: cove PR #405 (Vega)

**Verdict:** ⚠️ Needs Changes

## Summary

This PR refactors the message delivery logic to use the `openclaw/plugin-sdk`'s `deliverWithFinalizableLivePreviewAdapter`, which is a solid architectural improvement. It also correctly fixes a typing keepalive bug. However, in replacing the SDK's `sendDurableMessageBatch` with a direct `restClient.sendMessage` call, it **removes the automatic message chunking for long replies**. This is a significant functional regression that could cause message delivery to fail silently or error out for any agent response that exceeds the platform's message character limit.

## Critical Issues (Blocking)

### 1. **Loss of Message Chunking for Final Delivery**

- **File:** `packages/plugin/src/dispatch.ts`
- **Function:** `freshSend`
- **Problem:** The previous implementation used `sendDurableMessageBatch` with a `formatting: { textLimit: COVE_TEXT_CHUNK_LIMIT }` option. This SDK utility was responsible for splitting a long message into multiple smaller chunks and sending them sequentially. The new implementation replaces this with a single, direct call to `await restClient.sendMessage(channelId, text)`.
- **Impact:** If the agent generates a final response longer than `COVE_TEXT_CHUNK_LIMIT`, the `restClient.sendMessage` call will likely be rejected by the Cove API, causing the message to fail to send. The user will not receive a response. This regression undermines the reliability of message delivery.
- **Fix:** The `freshSend` function (and the `deliverNormally` callback it powers) must re-introduce chunking logic. Either revert to using `sendDurableMessageBatch` (and investigate the "silent failure" issue from PR #404 that prompted its removal) or implement manual chunking before calling `restClient.sendMessage`.

## Suggestions (Non-blocking)

### 1. **Redundant Draft Deletion**

- **File:** `packages/plugin/src/dispatch.ts`
- **Functions:** `freshSend`, `adapter.clear`
- **Observation:** The `deliverWithFinalizableLivePreviewAdapter` framework calls `adapter.clear()` on fallback, which is wired to delete the draft message. The `freshSend` function, used as the `deliverNormally` fallback, *also* attempts to delete the draft message. This means in a fallback scenario, two `deleteMessage` calls are fired for the same draft.
- **Impact:** This is harmless but inefficient. The first successful call will delete the message, and the second will likely fail with a "not found" error, which is correctly caught and logged.
- **Fix:** Simplify `freshSend` to only be responsible for sending the new message. The SDK adapter's `clear` lifecycle hook is the correct place to handle the cleanup of the old draft. `freshSend` should not need to know about `draftMessageId`.

## Positive Notes

- **Excellent SDK Adoption:** The move to `deliverWithFinalizableLivePreviewAdapter` is the right direction. It replaces bespoke, hard-to-follow logic with a standardized, declarative pattern that is more robust and easier to maintain. The error handling within the adapter (edit failure → fallback to fresh send) is correctly implemented.
- **Typing Keepalive Fix:** Moving `onReplyStart` into `runDispatch` is a clean and correct fix for ensuring the typing indicator persists through tool execution.
- **Superb Test Coverage:** The addition of 23 new behavioral tests (Group H) to lock down the existing contract before refactoring is exemplary. This is exactly the right way to approach a sensitive refactor and gives high confidence in the new implementation (aside from the chunking issue).
- **Clear Spec:** The accompanying `SPEC-401.md` file is detailed and clearly outlines the plan, architecture, and risks.
