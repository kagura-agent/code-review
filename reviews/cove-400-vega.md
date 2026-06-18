# Cove PR #400 Round 2 Re-Review (Vega)

## R1 Issue Status
- **C1. `freshSend` deps key mismatch** — 🔄 **Disputed (Verified author is correct)**: R1 incorrectly claimed the key should be `sendText`. The SDK's `OutboundSendDeps` is an index signature `[channelId: string]: unknown`, so the key must indeed be the channel ID (`cove`).
- **C2. `freshSend` formatting key mismatch** — 🔄 **Disputed (Verified author is correct)**: R1 incorrectly requested `textChunkLimit` and `markdown` mode for `sendDurableMessageBatch`. The SDK's `OutboundDeliveryFormattingOptions` explicitly uses `textLimit` and `ChunkMode` only has `length` | `newline`. (The author correctly used `textChunkLimit` and `chunkerMode: "markdown"` for the `createChannelMessageAdapterFromOutbound` shell base options, but for the inline formatting object, `textLimit` is exactly right).
- **C3. `freshSend` fallback `?? text`** — ✅ **Fixed**: The fallback was removed. The callback now properly extracts `const chunk = ctx.text ?? ctx.body` and throws if empty, matching strict SDK expectations.
- **C4. `freshSend` deletes draft before sending** — ✅ **Fixed**: Draft deletion logic is now executed after the `await sendDurableMessageBatch(...)` call. The send-before-delete order guarantees message delivery before clearing the preview.
- **C5. `recordInboundSession` binding** — ✅ **Fixed**: `.bind(channelRuntime.session)` is properly applied.

## Summary
The author has successfully navigated the complexities of the SDK adapter framework. The disputes against R1 were completely valid and factually correct based on the SDK type definitions. The subsequent fixes for C3, C4, and C5 handle the remaining lifecycle edge cases perfectly.

## Critical Issues
None.

## Suggestions
- *None required.* The separation of the `freshSend` multi-chunk path from the `editMessage` single-draft path effectively mitigates SDK risk while securing chunking behavior.

## Positive Notes
Excellent pushback on the R1 hallucinations regarding the SDK types. Validating against the actual `OutboundSendDeps` and `OutboundDeliveryFormattingOptions` schemas proves the PR was adhering to the correct boundaries.

## Verdict
✅ **Ready**