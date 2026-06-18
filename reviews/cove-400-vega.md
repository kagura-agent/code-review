# Code Review: PR #400

**Summary:**
This PR successfully adopts the SDK outbound adapter framework and implements the structural refactoring requested in Phases 0 through 3, cleanly extracting context logic into `build-context.ts` and reducing boilerplate via `createChatChannelPlugin`. However, there are multiple critical integration bugs in the `dispatch.ts` final delivery pipeline regarding how `sendDurableMessageBatch` is configured and when it is invoked.

**Critical Issues:**
1. **Missing Chunk Limit Check in `dispatch.ts`:**
   In the final stream delivery block, the condition is `if (draftMessageId && !draftState.stopped)`. It is missing the `text.length <= COVE_TEXT_CHUNK_LIMIT` check specified in Phase 2. Without this, replies exceeding 4000 characters will attempt an `editMessage` API call (which will fail with a 400 error) before falling back to `freshSend`. 
2. **Incorrect Formatting Keys in `sendDurableMessageBatch`:**
   In the `freshSend` fallback, `formatting: { textLimit: COVE_TEXT_CHUNK_LIMIT }` is passed. The SDK expects `textChunkLimit`, not `textLimit`. Additionally, `chunkMode: "markdown"` is missing, which was explicitly requested in the specification.
3. **Incorrect Dependency Key in `sendDurableMessageBatch`:**
   Also in `freshSend`, the network dependency is provided as `deps: { cove: (ctx) => ... }`. The SDK requires `deps: { sendText: (ctx) => ... }` to successfully dispatch the message. Using the `cove` key means the outbound adapter will crash or silently fail to deliver chunked messages.

**Product Impact:**
- The missing length check means long messages will trigger unnecessary API error logs (`cove: final edit failed...`) and introduce latency before chunking fallback kicks in.
- The incorrect `sendText` dependency in `sendDurableMessageBatch` will cause long messages (that hit `freshSend`) to completely fail delivery, leading to silent drops of agent replies in production.

**Suggestions:**
- **Update PR Description:** The PR states "Status: Phase 0 only" and "Zero implementation changes," but the diff contains the full Phase 1-3 implementation. Update the description to reflect reality.
- **Missing Tests:** Phase 2 explicitly required "New chunking tests assert Path 2 splits >4000 char text into multiple messages." `dispatch-behavior.test.ts` only asserts that `sendDurableMessageBatch` is called, without verifying the chunking split threshold or payload shape.

**Positive Notes:**
- The pure structural extraction in `build-context.ts` is perfectly executed.
- `channel.ts` is significantly simplified by correctly adopting the `createChatChannelPlugin` shell and removing legacy routing patches.

**Verdict:** ❌ Major Issues